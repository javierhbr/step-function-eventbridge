#!/bin/bash
set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

echo "🧹 Cleaning up File Upload System from LocalStack"
echo "=================================================="

# Configure AWS CLI for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo ""
echo "🗑️  Deleting Lambda functions..."

# Delete Lambda Function URL first
echo "  - Deleting Function URL for poc-upload-api..."
aws --endpoint-url=$ENDPOINT lambda delete-function-url-config \
  --function-name poc-upload-api \
  --no-cli-pager 2>/dev/null || echo "    Function URL not found"

# Delete Lambda functions
echo "  - Deleting poc-upload-api..."
aws --endpoint-url=$ENDPOINT lambda delete-function \
  --function-name poc-upload-api \
  --no-cli-pager 2>/dev/null || echo "    Function not found"

echo "  - Deleting poc-upload-complete..."
aws --endpoint-url=$ENDPOINT lambda delete-function \
  --function-name poc-upload-complete \
  --no-cli-pager 2>/dev/null || echo "    Function not found"

echo "✅ Lambda functions deleted"

echo ""
echo "🗑️  Emptying and deleting S3 bucket..."
# Empty the bucket first
aws --endpoint-url=$ENDPOINT s3 rm s3://poc-file-uploads --recursive \
  --no-cli-pager 2>/dev/null || echo "  Bucket already empty or not found"

# Delete the bucket
aws --endpoint-url=$ENDPOINT s3 rb s3://poc-file-uploads \
  --no-cli-pager 2>/dev/null || echo "  Bucket not found"

echo "✅ S3 bucket deleted"

echo ""
echo "🗑️  Deleting DynamoDB table..."
aws --endpoint-url=$ENDPOINT dynamodb delete-table \
  --table-name poc-file-uploads \
  --no-cli-pager 2>/dev/null || echo "  Table not found"

echo "✅ DynamoDB table deleted"

echo ""
echo "🗑️  Cleaning local build artifacts..."
rm -f lambdas/upload-api/upload-api.zip
rm -f lambdas/upload-complete/upload-complete.zip
rm -rf lambdas/upload-api/dist
rm -rf lambdas/upload-complete/dist
rm -f /tmp/s3-cors.json

echo "✅ Local build artifacts cleaned"

echo ""
echo "🎉 Cleanup Complete!"
echo ""
echo "All upload system resources have been removed from LocalStack."
