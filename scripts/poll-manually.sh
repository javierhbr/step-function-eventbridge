#!/bin/bash
# Manual polling script - simulates what EventBridge Scheduler would do

ENDPOINT="http://localhost:4566"
JOB_ID=$1

if [ -z "$JOB_ID" ]; then
  echo "Usage: ./scripts/poll-manually.sh <job-id>"
  echo ""
  echo "Get job ID from DynamoDB:"
  echo "  aws --endpoint-url=$ENDPOINT dynamodb scan --table-name poc-task-tokens"
  exit 1
fi

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "🔄 Polling job: $JOB_ID"
echo ""

aws --endpoint-url=$ENDPOINT lambda invoke \
  --function-name poc-poller \
  --payload "{\"jobId\": \"$JOB_ID\"}" \
  --cli-binary-format raw-in-base64-out \
  /dev/stdout 2>/dev/null | jq . 2>/dev/null || cat

echo ""
