#!/bin/bash
set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

echo "🚀 Deploying File Upload System to LocalStack"
echo "=============================================="

# Check for AWS CLI
echo ""
echo "Checking prerequisites..."
if ! command -v aws &> /dev/null; then
  echo "❌ AWS CLI is not installed."
  exit 1
fi
echo "✅ AWS CLI found: $(aws --version | head -1)"

# Check LocalStack is running
echo ""
echo "Checking LocalStack status..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ENDPOINT/health 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" != "200" ]; then
  echo "❌ LocalStack is not running. Start it with: docker-compose up -d"
  exit 1
fi

echo "✅ LocalStack is running (HTTP $HTTP_STATUS)"

# Configure AWS CLI for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo ""
echo "📦 Creating S3 bucket for file uploads..."
aws --endpoint-url=$ENDPOINT s3 mb s3://poc-file-uploads 2>/dev/null || \
  echo "  Bucket poc-file-uploads already exists"

# Configure CORS (critical for presigned URLs)
cat > /tmp/s3-cors.json <<EOF
{
  "CORSRules": [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["PUT", "POST", "GET"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }]
}
EOF

aws --endpoint-url=$ENDPOINT s3api put-bucket-cors \
  --bucket poc-file-uploads \
  --cors-configuration file:///tmp/s3-cors.json

echo "✅ S3 bucket ready with CORS configured"

echo ""
echo "📦 Creating DynamoDB table for file uploads..."
aws --endpoint-url=$ENDPOINT dynamodb create-table \
  --table-name poc-file-uploads \
  --attribute-definitions AttributeName=uploadId,AttributeType=S \
  --key-schema AttributeName=uploadId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --no-cli-pager 2>/dev/null || echo "  Table poc-file-uploads already exists"

echo "✅ DynamoDB table for file uploads ready"

echo ""
echo "🔨 Building and packaging Upload Lambda functions..."

# Build upload-api
echo ""
echo "  Building upload-api..."
cd lambdas/upload-api

# Clean previous builds
npm run clean 2>/dev/null || true

# Build TypeScript
echo "    - Compiling TypeScript..."
npm run build

# Create deployment package
echo "    - Creating ZIP package..."
cd dist

# Copy node_modules to dist for Lambda runtime
if [ -d "../node_modules" ]; then
  cp -r ../node_modules .
fi

# Create ZIP with all dependencies
zip -r "../upload-api.zip" . -q
cd ..

echo "    ✅ upload-api.zip created"
cd ../..

# Build upload-complete
echo ""
echo "  Building upload-complete..."
cd lambdas/upload-complete

# Clean previous builds
npm run clean 2>/dev/null || true

# Build TypeScript
echo "    - Compiling TypeScript..."
npm run build

# Create deployment package
echo "    - Creating ZIP package..."
cd dist

# Copy node_modules to dist for Lambda runtime
if [ -d "../node_modules" ]; then
  cp -r ../node_modules .
fi

# Create ZIP with all dependencies
zip -r "../upload-complete.zip" . -q
cd ..

echo "    ✅ upload-complete.zip created"
cd ../..

echo ""
echo "✅ All Lambda packages created"

echo ""
echo "🚀 Deploying Lambda functions to LocalStack..."

# Deploy Upload API
echo ""
echo "  Deploying poc-upload-api..."
aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name poc-upload-api \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://lambdas/upload-api/upload-api.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 30 \
  --memory-size 512 \
  --environment Variables={S3_BUCKET=poc-file-uploads,TABLE_NAME=poc-file-uploads} \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda update-function-code \
  --function-name poc-upload-api \
  --zip-file fileb://lambdas/upload-api/upload-api.zip \
  --no-cli-pager

echo "  ✅ poc-upload-api deployed"

# Deploy Upload Complete
echo ""
echo "  Deploying poc-upload-complete..."
aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name poc-upload-complete \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://lambdas/upload-complete/upload-complete.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 60 \
  --memory-size 256 \
  --environment Variables={TABLE_NAME=poc-file-uploads} \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda update-function-code \
  --function-name poc-upload-complete \
  --zip-file fileb://lambdas/upload-complete/upload-complete.zip \
  --no-cli-pager

echo "  ✅ poc-upload-complete deployed"

echo ""
echo "⏳ Waiting for Lambda functions to become active..."

# Wait for each function to become active
for func in poc-upload-api poc-upload-complete; do
  echo "   - Waiting for $func..."
  aws --endpoint-url=$ENDPOINT lambda wait function-active-v2 \
    --function-name $func \
    2>/dev/null || sleep 5
done

echo "✅ All Lambda functions are active"

echo ""
echo "🔗 Creating Function URL for poc-upload-api..."
FUNCTION_URL=$(aws --endpoint-url=$ENDPOINT lambda create-function-url-config \
  --function-name poc-upload-api \
  --auth-type NONE \
  --cors AllowOrigins="*",AllowMethods="POST,GET",AllowHeaders="*",ExposeHeaders="*" \
  --query 'FunctionUrl' \
  --output text 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda get-function-url-config \
  --function-name poc-upload-api \
  --query 'FunctionUrl' \
  --output text)

echo "  ✅ Function URL: $FUNCTION_URL"

echo ""
echo "🔔 Configuring S3 → Lambda event trigger..."
aws --endpoint-url=$ENDPOINT s3api put-bucket-notification-configuration \
  --bucket poc-file-uploads \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
      "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:poc-upload-complete",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [{"Name": "prefix", "Value": "uploads/"}]
        }
      }
    }]
  }'

echo "  ✅ S3 event trigger configured"

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "Resources created in LocalStack:"
echo "  - S3: poc-file-uploads bucket with CORS"
echo "  - DynamoDB: poc-file-uploads table"
echo "  - Lambda: poc-upload-api, poc-upload-complete"
echo "  - Function URL: $FUNCTION_URL"
echo ""
echo "📝 Save the Function URL above for testing!"
echo ""
echo "To test: ./scripts/test-upload.sh"
