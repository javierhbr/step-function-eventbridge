# Quick Start Guide

Get the Step Functions Callback Pattern PoC running in 5 minutes!

## Prerequisites Check

```bash
# Check Node.js (requires 18+)
node --version

# Check npm
npm --version

# Check Docker
docker --version

# Check Docker Compose
docker-compose --version
```

## Step 1: Install Dependencies (2 minutes)

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Install all Lambda dependencies
./scripts/setup.sh
```

This will:
- ✅ Install TypeScript and AWS SDK dependencies for all Lambdas
- ✅ Verify prerequisites
- ✅ Create necessary directories

## Step 2: Start LocalStack (30 seconds)

```bash
# Start LocalStack container
docker-compose up -d

# Verify it's running
docker ps | grep localstack-poc

# Check logs (optional)
docker logs localstack-poc -f
```

## Step 3: Deploy Everything (1 minute)

```bash
./scripts/deploy-local.sh
```

This script:
1. Creates DynamoDB tables (poc-task-tokens, poc-jobs)
2. Compiles TypeScript to JavaScript
3. Packages Lambda functions with dependencies
4. Deploys all 3 Lambda functions
5. Creates Step Functions state machine

Expected output:
```
🚀 Deploying TypeScript PoC to LocalStack
✅ LocalStack is running
📦 Creating DynamoDB tables...
🔨 Building and packaging TypeScript Lambda functions...
🚀 Deploying Lambda functions to LocalStack...
🔧 Creating Step Functions state machine...
🎉 Deployment Complete!
```

## Step 4: Run Test (1 minute)

```bash
./scripts/test-local.sh
```

This validates the complete callback pattern:
1. Starts Step Functions execution
2. Waits for job creation
3. Polls job status 2-3 times
4. Workflow reconnects via SendTaskSuccess
5. Verifies successful completion

Expected output:
```
🧪 Testing Local PoC: Callback Pattern (TypeScript)
1️⃣  Starting Step Functions execution...
   ✅ Execution started
2️⃣  Checking job created in DynamoDB...
   ✅ Job created: job-1234567890-abc123
3️⃣  Step Functions status: RUNNING
   ✅ Workflow is WAITING for callback
4️⃣  Starting manual polling...
   📊 Poll #1...
   📊 Poll #2...
   📊 Poll #3...
   🎉 Job completed and workflow reconnected!
5️⃣  Checking final execution status...
   Final Status: SUCCEEDED
✅ TEST PASSED! Workflow completed successfully!
```

## What Just Happened?

1. **Task Token Generated**: Step Functions created a unique token
2. **Job Created**: External job simulated with random completion (2-3 polls)
3. **Token Persisted**: Task Token saved to DynamoDB
4. **Workflow Paused**: Execution entered WAITING state at $0 cost
5. **Polling**: Manual polling checked job status every 5 seconds
6. **Reconnection**: When job completed, SendTaskSuccess reconnected the workflow
7. **Completion**: Workflow continued and reached SUCCESS state

## Monitoring

### View DynamoDB Tables

```bash
./scripts/monitor.sh
```

### Manual Polling

```bash
# Get job ID from monitor output
./scripts/poll-manually.sh job-1234567890-abc123
```

### View Lambda Logs

```bash
docker logs localstack-poc -f
```

### Cleanup

```bash
# Remove all resources (keeps LocalStack running)
./scripts/cleanup.sh

# Stop and remove LocalStack
docker-compose down -v
```

## Troubleshooting

### LocalStack not starting

```bash
docker-compose down
docker-compose up -d
docker logs localstack-poc
```

### Lambda build errors

```bash
cd lambdas/simulated-api
npm install
npm run build
```

### Test fails

```bash
# Check LocalStack health
curl http://localhost:4566/health

# View recent logs
docker logs localstack-poc --tail 100

# Re-deploy
./scripts/deploy-local.sh
./scripts/test-local.sh
```

### "Table already exists" error

This is normal on re-deploy - the script handles it automatically.

## Next Steps

1. **Explore the Code**: Check out [lambdas/](lambdas/) for TypeScript implementations
2. **Read Documentation**: See [README.md](README.md) for detailed info
3. **Understand the Pattern**: Review [CLAUDE.md](CLAUDE.md) for architecture details
4. **Implement US-003**: Add error handling and validation (see [TODO.md](TODO.md))

## Quick Reference

| Command | Purpose |
|---------|---------|
| `./scripts/setup.sh` | Install dependencies |
| `docker-compose up -d` | Start LocalStack |
| `./scripts/deploy-local.sh` | Deploy all resources |
| `./scripts/test-local.sh` | Run end-to-end test |
| `./scripts/monitor.sh` | View all resources |
| `./scripts/poll-manually.sh <job-id>` | Manual poll trigger |
| `./scripts/cleanup.sh` | Remove resources |
| `docker-compose down -v` | Stop and remove everything |

## Success Criteria

You've successfully validated the callback pattern when you see:

- ✅ Execution status: SUCCEEDED
- ✅ Multiple polling attempts (2-3)
- ✅ Workflow reconnected after SendTaskSuccess
- ✅ Final output contains job result
- ✅ DynamoDB shows COMPLETED status

**Congratulations!** You've validated an 87% cost reduction pattern! 🎉
