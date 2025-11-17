#!/bin/bash
# Monitor LocalStack resources - Comprehensive View

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION
export AWS_PAGER=""

# Parse command line arguments
WATCH_MODE=false
INTERVAL=5

show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -w, --watch [INTERVAL]    Watch mode - refresh every INTERVAL seconds (default: 5)"
  echo "  -h, --help                Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                        Run once and exit"
  echo "  $0 --watch                Watch mode with 5 second refresh"
  echo "  $0 --watch 10             Watch mode with 10 second refresh"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -w|--watch)
      WATCH_MODE=true
      if [[ -n $2 ]] && [[ $2 =~ ^[0-9]+$ ]]; then
        INTERVAL=$2
        shift
      fi
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      ;;
  esac
done

show_resources() {
  clear
  echo "📊 LocalStack Resource Monitor - Complete View"
  if [ "$WATCH_MODE" = true ]; then
    echo "   [Watch Mode: Refreshing every ${INTERVAL}s - Press Ctrl+C to exit]"
  fi
  echo "==============================================="
  echo ""

# DynamoDB Tables
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 DYNAMODB TABLES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔹 Task Tokens Table (poc-task-tokens):"
TOKENS_COUNT=$(aws --endpoint-url=$ENDPOINT dynamodb scan --table-name poc-task-tokens --select COUNT --output json 2>/dev/null | jq -r '.Count // 0')
echo "   Total items: $TOKENS_COUNT"
if [ "$TOKENS_COUNT" -gt 0 ]; then
  aws --endpoint-url=$ENDPOINT dynamodb scan \
    --table-name poc-task-tokens \
    --query 'Items[].{JobID: jobId.S, Status: status.S, Attempts: attemptCount.N, MaxAttempts: maxAttempts.N, ExecutionID: executionId.S}' \
    --output table 2>/dev/null
else
  echo "   (empty)"
fi

echo ""
echo "🔹 Jobs Table (poc-jobs):"
JOBS_COUNT=$(aws --endpoint-url=$ENDPOINT dynamodb scan --table-name poc-jobs --select COUNT --output json 2>/dev/null | jq -r '.Count // 0')
echo "   Total items: $JOBS_COUNT"
if [ "$JOBS_COUNT" -gt 0 ]; then
  aws --endpoint-url=$ENDPOINT dynamodb scan \
    --table-name poc-jobs \
    --query 'Items[].{JobID: jobId.S, Status: status.S, PollCount: pollCount.N, CompletionPolls: completionPolls.N, Created: createdAt.S}' \
    --output table 2>/dev/null
else
  echo "   (empty)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ LAMBDA FUNCTIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
FUNCTIONS=$(aws --endpoint-url=$ENDPOINT lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `poc-`)].[FunctionName]' \
  --output text 2>/dev/null)

if [ -n "$FUNCTIONS" ]; then
  echo "$FUNCTIONS" | while read -r func; do
    echo "🔹 $func"
    aws --endpoint-url=$ENDPOINT lambda get-function \
      --function-name "$func" \
      --query '{Runtime: Configuration.Runtime, Handler: Configuration.Handler, State: Configuration.State, LastModified: Configuration.LastModified, CodeSize: Configuration.CodeSize, Timeout: Configuration.Timeout, Memory: Configuration.MemorySize}' \
      --output json 2>/dev/null | jq -r '
        "   Runtime: \(.Runtime)",
        "   Handler: \(.Handler)",
        "   State: \(.State // "Active")",
        "   Timeout: \(.Timeout)s | Memory: \(.Memory)MB",
        "   Code Size: \((.CodeSize / 1024 / 1024 * 100 | floor) / 100)MB",
        "   Last Modified: \(.LastModified)"
      '
    echo ""
  done
else
  echo "   No Lambda functions found"
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 STEP FUNCTIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔹 State Machine: poc-callback-workflow"
STATE_MACHINE_ARN="arn:aws:states:$REGION:000000000000:stateMachine:poc-callback-workflow"
SM_INFO=$(aws --endpoint-url=$ENDPOINT stepfunctions describe-state-machine \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --output json 2>/dev/null)

if [ -n "$SM_INFO" ]; then
  echo "$SM_INFO" | jq -r '
    "   Status: \(.status)",
    "   Created: \(.creationDate)",
    "   Type: \(.type)"
  '
  echo ""

  echo "🔹 Recent Executions:"
  EXECUTIONS=$(aws --endpoint-url=$ENDPOINT stepfunctions list-executions \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --max-results 10 \
    --output json 2>/dev/null)

  EXEC_COUNT=$(echo "$EXECUTIONS" | jq -r '.executions | length')
  echo "   Total: $EXEC_COUNT"

  if [ "$EXEC_COUNT" -gt 0 ]; then
    echo ""
    echo "$EXECUTIONS" | jq -r '.executions[] |
      "   • \(.name)",
      "     Status: \(.status)",
      "     Started: \(.startDate)",
      if .stopDate then "     Stopped: \(.stopDate)" else "     Running..." end,
      ""
    '

    # Show details of most recent execution
    LATEST_EXEC_ARN=$(echo "$EXECUTIONS" | jq -r '.executions[0].executionArn')
    if [ -n "$LATEST_EXEC_ARN" ] && [ "$LATEST_EXEC_ARN" != "null" ]; then
      echo "🔹 Latest Execution Details:"
      EXEC_DETAILS=$(aws --endpoint-url=$ENDPOINT stepfunctions describe-execution \
        --execution-arn "$LATEST_EXEC_ARN" \
        --output json 2>/dev/null)

      echo "$EXEC_DETAILS" | jq -r '
        "   ARN: \(.executionArn)",
        "   Status: \(.status)",
        "   Started: \(.startDate)",
        if .stopDate then "   Stopped: \(.stopDate)" else "" end,
        if .output then "   Output: \(.output)" else "" end,
        if .input then "   Input: \(.input)" else "" end
      '
      echo ""

      # Show execution history
      echo "🔹 Execution History (Recent Events):"
      aws --endpoint-url=$ENDPOINT stepfunctions get-execution-history \
        --execution-arn "$LATEST_EXEC_ARN" \
        --max-results 10 \
        --reverse-order \
        --output json 2>/dev/null | jq -r '.events[] |
          "   \(.timestamp) | \(.type) (id: \(.id))"
        '
      echo ""
    fi
  else
    echo "   (no executions)"
    echo ""
  fi
else
  echo "   State machine not found"
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
LAMBDA_COUNT=$(aws --endpoint-url=$ENDPOINT lambda list-functions --query 'Functions[?starts_with(FunctionName, `poc-`)] | length(@)' --output text 2>/dev/null)
echo "   Lambda Functions: $LAMBDA_COUNT"
echo "   DynamoDB Tables: 2 (task-tokens, jobs)"
echo "   Task Tokens: $TOKENS_COUNT"
echo "   Jobs: $JOBS_COUNT"
echo "   Recent Executions: $EXEC_COUNT"
echo ""
if [ "$WATCH_MODE" = false ]; then
  echo "✅ Monitoring complete!"
fi
echo ""
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
  # Watch mode - loop continuously
  trap 'echo ""; echo "👋 Monitoring stopped"; exit 0' INT TERM
  while true; do
    show_resources
    sleep "$INTERVAL"
  done
else
  # Single run
  show_resources
fi
