#!/bin/bash
# Cleanup script - removes all LocalStack resources

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo "🧹 Cleaning up LocalStack resources..."
echo "======================================"

echo ""
echo "Deleting Step Functions state machine..."
aws --endpoint-url=$ENDPOINT stepfunctions delete-state-machine \
  --state-machine-arn arn:aws:states:$REGION:000000000000:stateMachine:poc-callback-workflow \
  2>/dev/null || echo "  State machine not found"

echo ""
echo "Deleting Lambda functions..."
for func in poc-simulated-api poc-create-job poc-poller; do
  aws --endpoint-url=$ENDPOINT lambda delete-function \
    --function-name $func \
    2>/dev/null || echo "  $func not found"
done

echo ""
echo "Deleting DynamoDB tables..."
for table in poc-task-tokens poc-jobs; do
  aws --endpoint-url=$ENDPOINT dynamodb delete-table \
    --table-name $table \
    2>/dev/null || echo "  $table not found"
done

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To stop LocalStack: docker-compose down"
echo "To remove volumes: docker-compose down -v"
