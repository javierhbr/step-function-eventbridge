#!/bin/bash
set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

echo "🚀 Deploying TypeScript PoC to LocalStack"
echo "=========================================="

# Check LocalStack is running
echo ""
echo "Checking LocalStack status..."
if ! curl -s $ENDPOINT/health | grep -q "running"; then
  echo "❌ LocalStack is not running. Start it with: docker-compose up -d"
  exit 1
fi

echo "✅ LocalStack is running"

# Configure AWS CLI for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo ""
echo "📦 Creating DynamoDB tables..."

# Create Task Tokens table
aws --endpoint-url=$ENDPOINT dynamodb create-table \
  --table-name poc-task-tokens \
  --attribute-definitions AttributeName=jobId,AttributeType=S \
  --key-schema AttributeName=jobId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --no-cli-pager 2>/dev/null || echo "  Table poc-task-tokens already exists"

# Create Jobs table
aws --endpoint-url=$ENDPOINT dynamodb create-table \
  --table-name poc-jobs \
  --attribute-definitions AttributeName=jobId,AttributeType=S \
  --key-schema AttributeName=jobId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --no-cli-pager 2>/dev/null || echo "  Table poc-jobs already exists"

echo "✅ DynamoDB tables ready"

echo ""
echo "🔨 Building and packaging TypeScript Lambda functions..."

for lambda_dir in lambdas/*/; do
  lambda_name=$(basename "$lambda_dir")
  echo ""
  echo "  Building $lambda_name..."

  cd "$lambda_dir"

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
  zip -r "../${lambda_name}.zip" . -q
  cd ..

  echo "    ✅ ${lambda_name}.zip created"
  cd ../..
done

echo ""
echo "✅ All Lambda packages created"

echo ""
echo "🚀 Deploying Lambda functions to LocalStack..."

# Deploy Simulated API
echo ""
echo "  Deploying poc-simulated-api..."
aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name poc-simulated-api \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://lambdas/simulated-api/simulated-api.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 30 \
  --memory-size 256 \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda update-function-code \
  --function-name poc-simulated-api \
  --zip-file fileb://lambdas/simulated-api/simulated-api.zip \
  --no-cli-pager

echo "  ✅ poc-simulated-api deployed"

# Deploy Create Job
echo ""
echo "  Deploying poc-create-job..."
aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name poc-create-job \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://lambdas/create-job/create-job.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 60 \
  --memory-size 256 \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda update-function-code \
  --function-name poc-create-job \
  --zip-file fileb://lambdas/create-job/create-job.zip \
  --no-cli-pager

echo "  ✅ poc-create-job deployed"

# Deploy Poller
echo ""
echo "  Deploying poc-poller..."
aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name poc-poller \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://lambdas/poller/poller.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 60 \
  --memory-size 256 \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT lambda update-function-code \
  --function-name poc-poller \
  --zip-file fileb://lambdas/poller/poller.zip \
  --no-cli-pager

echo "  ✅ poc-poller deployed"

echo ""
echo "🔧 Creating Step Functions state machine..."

# Create IAM role (LocalStack doesn't enforce this but it's needed)
aws --endpoint-url=$ENDPOINT iam create-role \
  --role-name StepFunctionsRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --no-cli-pager 2>/dev/null || true

# Create State Machine
STATE_MACHINE_DEF=$(cat state-machine/definition.json)

aws --endpoint-url=$ENDPOINT stepfunctions create-state-machine \
  --name poc-callback-workflow \
  --definition "$STATE_MACHINE_DEF" \
  --role-arn arn:aws:iam::000000000000:role/StepFunctionsRole \
  --no-cli-pager 2>/dev/null || \
aws --endpoint-url=$ENDPOINT stepfunctions update-state-machine \
  --state-machine-arn arn:aws:states:$REGION:000000000000:stateMachine:poc-callback-workflow \
  --definition "$STATE_MACHINE_DEF" \
  --no-cli-pager

echo "  ✅ poc-callback-workflow state machine deployed"

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "Resources created in LocalStack:"
echo "  - DynamoDB: poc-task-tokens, poc-jobs"
echo "  - Lambda: poc-simulated-api, poc-create-job, poc-poller (TypeScript)"
echo "  - Step Functions: poc-callback-workflow"
echo ""
echo "To test: ./scripts/test-local.sh"
