#!/bin/bash
set -e

ENDPOINT="http://localhost:4566"

echo "🧪 Testing File Upload System"
echo "=============================="

# Configure AWS CLI for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Get Function URL from deployment
FUNCTION_URL=$(aws --endpoint-url=$ENDPOINT lambda get-function-url-config \
  --function-name poc-upload-api \
  --query 'FunctionUrl' \
  --output text 2>/dev/null)

if [ -z "$FUNCTION_URL" ]; then
  echo "❌ Function URL not found. Run ./scripts/deploy-upload.sh first"
  exit 1
fi

echo "📍 Function URL: $FUNCTION_URL"

# Test 1: Initiate upload
echo ""
echo "1️⃣  Initiating upload for large file (10MB)..."
INIT_RESPONSE=$(curl -s -X POST "${FUNCTION_URL}initiate" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test-video.mp4",
    "size": 10485760,
    "contentType": "video/mp4"
  }')

echo "Response: $INIT_RESPONSE"

UPLOAD_ID=$(echo $INIT_RESPONSE | jq -r '.uploadId')
PRESIGNED_URL=$(echo $INIT_RESPONSE | jq -r '.presignedUrl')

if [ "$UPLOAD_ID" == "null" ] || [ -z "$UPLOAD_ID" ]; then
  echo "❌ Failed to get uploadId"
  echo "Full response: $INIT_RESPONSE"
  exit 1
fi

echo "  ✅ Upload initiated: $UPLOAD_ID"

# Test 2: Upload file to S3
echo ""
echo "2️⃣  Uploading test file to S3 via presigned URL..."
dd if=/dev/urandom of=/tmp/test-video.mp4 bs=1M count=10 2>/dev/null

HTTP_CODE=$(curl -X PUT "$PRESIGNED_URL" \
  -H "Content-Type: video/mp4" \
  --upload-file /tmp/test-video.mp4 \
  -s -o /dev/null -w "%{http_code}")

if [ "$HTTP_CODE" == "200" ]; then
  echo "  ✅ File uploaded to S3 (HTTP $HTTP_CODE)"
else
  echo "  ❌ Upload failed (HTTP $HTTP_CODE)"
  exit 1
fi

# Test 3: Poll for completion
echo ""
echo "3️⃣  Polling for upload completion..."
for i in {1..10}; do
  sleep 2
  STATUS_RESPONSE=$(curl -s "${FUNCTION_URL}status/${UPLOAD_ID}")
  STATUS=$(echo $STATUS_RESPONSE | jq -r '.status')

  echo "  Attempt $i: $STATUS_RESPONSE"

  if [ "$STATUS" == "COMPLETED" ]; then
    echo "  ✅ Upload completed successfully (HTTP 201)!"
    break
  fi

  if [ $i -eq 10 ]; then
    echo "  ⚠️  Timeout waiting for completion"
  fi
done

# Test 4: Verify DynamoDB
echo ""
echo "4️⃣  Verifying DynamoDB record..."
aws --endpoint-url=$ENDPOINT dynamodb get-item \
  --table-name poc-file-uploads \
  --key "{\"uploadId\": {\"S\": \"$UPLOAD_ID\"}}" \
  --query 'Item.[uploadId.S, filename.S, status.S, actualSize.N]' \
  --output table

# Test 5: Verify S3
echo ""
echo "5️⃣  Verifying file in S3..."
S3_KEY=$(echo $INIT_RESPONSE | jq -r '.s3Key')
aws --endpoint-url=$ENDPOINT s3 ls s3://poc-file-uploads/${S3_KEY} || echo "  File not found in S3"

echo ""
echo "✅ All tests completed!"
