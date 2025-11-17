#!/bin/bash
# Monitor LocalStack resources

ENDPOINT="http://localhost:4566"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "📊 LocalStack Resource Monitor"
echo "==============================="

echo ""
echo "🔹 Task Tokens Table:"
aws --endpoint-url=$ENDPOINT dynamodb scan \
  --table-name poc-task-tokens \
  --query 'Items[].{JobID: jobId.S, Status: status.S, Attempts: attemptCount.N, MaxAttempts: maxAttempts.N}' \
  --output table 2>/dev/null || echo "  Table not found or empty"

echo ""
echo "🔹 Jobs Table:"
aws --endpoint-url=$ENDPOINT dynamodb scan \
  --table-name poc-jobs \
  --query 'Items[].{JobID: jobId.S, Status: status.S, Polls: pollCount.N, CompletesAt: completionPolls.N}' \
  --output table 2>/dev/null || echo "  Table not found or empty"

echo ""
echo "🔹 Step Functions Executions:"
aws --endpoint-url=$ENDPOINT stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:000000000000:stateMachine:poc-callback-workflow \
  --query 'executions[].{Name: name, Status: status, StartDate: startDate}' \
  --output table 2>/dev/null || echo "  No state machine found"

echo ""
echo "🔹 Lambda Functions (TypeScript):"
aws --endpoint-url=$ENDPOINT lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `poc-`)].{Name: FunctionName, Runtime: Runtime, Handler: Handler}' \
  --output table 2>/dev/null || echo "  No functions found"

echo ""
