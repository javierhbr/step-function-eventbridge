# Development Guide - Upload API

This guide explains how to run the upload-api Lambda in different modes for development and testing.

## Overview

The upload-api is built with **Fastify** and can run in three different modes:

1. **Standalone Fastify Server** - Fast local development
2. **AWS SAM Local** - Test as Lambda with API Gateway locally
3. **Lambda (LocalStack/AWS)** - Deploy and run in Lambda environment

## Architecture

```
┌─────────────────────────────────────────────────┐
│           src/app.ts                            │
│     (Fastify application code)                  │
│  ┌─────────────────────────────────────┐        │
│  │ Routes:                             │        │
│  │  POST /initiate                     │        │
│  │  GET  /status/:uploadId             │        │
│  │  GET  /health                       │        │
│  └─────────────────────────────────────┘        │
└────────────┬────────────────────┬────────────────┘
             │                    │
    ┌────────▼─────────┐   ┌──────▼──────────┐
    │  src/server.ts   │   │  src/index.ts   │
    │ (Standalone)     │   │ (Lambda)        │
    └──────────────────┘   └──────┬──────────┘
                                   │
                          @fastify/aws-lambda
                                   │
                          AWS Lambda Runtime
```

## Mode 1: Standalone Fastify Server (Recommended for Development)

**Best for:** Fast iteration, debugging, hot reload

### Setup

```bash
cd lambdas/upload-api

# Install dependencies
npm install

# Build TypeScript
npm run build
```

### Run

```bash
# Build and start server
npm run dev

# Or with auto-rebuild on file changes
npm run dev:watch
```

**Output:**
```
🚀 Upload API Server Started
================================
📍 URL: http://localhost:3000

Available endpoints:
  GET  /health
  POST /initiate
  GET  /status/:uploadId

Press Ctrl+C to stop
```

### Test

```bash
# Health check
curl http://localhost:3000/health

# Initiate upload
curl -X POST http://localhost:3000/initiate \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test.mp4",
    "size": 10485760,
    "contentType": "video/mp4"
  }'

# Check status
curl http://localhost:3000/status/UPLOAD_ID
```

### Features

✅ **Fast startup** (~1 second)
✅ **Hot reload** with `npm run dev:watch`
✅ **Full logging** with Fastify logger
✅ **Easy debugging** with standard Node debugger
✅ **CORS enabled** for browser testing
✅ **Health check** endpoint

### Environment Variables

```bash
# Optional: Override defaults
PORT=3001 npm run dev
HOST=127.0.0.1 npm run dev

# LocalStack endpoints (default values)
export LOCALSTACK_HOSTNAME=localhost
export S3_BUCKET=poc-file-uploads
export TABLE_NAME=poc-file-uploads
```

## Mode 2: AWS SAM Local (Lambda + API Gateway)

**Best for:** Testing Lambda behavior, API Gateway integration, IAM policies

### Prerequisites

Install AWS SAM CLI:
```bash
# macOS
brew install aws-sam-cli

# Verify installation
sam --version
```

### Setup

```bash
cd lambdas/upload-api

# Install dependencies
npm install

# Build for SAM
npm run sam:build
```

### Run

Start API Gateway locally:

```bash
npm run sam:start

# API will be available at http://localhost:3000
```

**Output:**
```
Mounting UploadApiFunction at http://localhost:3000/{proxy+} [GET, POST, OPTIONS]
You can now browse to the above endpoints to invoke your functions.
```

### Test

```bash
# Initiate upload
curl -X POST http://localhost:3000/initiate \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test.mp4",
    "size": 10485760,
    "contentType": "video/mp4"
  }'

# Check status
curl http://localhost:3000/status/UPLOAD_ID
```

### Invoke Lambda Directly

```bash
# Invoke function with event
npm run sam:invoke

# Or with custom event file
sam local invoke UploadApiFunction -e events/initiate.json
```

### Features

✅ **Real Lambda environment** (container-based)
✅ **API Gateway simulation** (path parameters, CORS, etc.)
✅ **IAM policy testing** (DynamoDB, S3 permissions)
✅ **CloudFormation validation**
✅ **Environment variables** from template.yaml

### SAM Configuration

Edit `template.yaml` to configure:
- Memory size (default: 512MB)
- Timeout (default: 30s)
- Environment variables
- IAM policies
- API Gateway routes

## Mode 3: Lambda (LocalStack/AWS)

**Best for:** Integration testing, pre-production validation

### LocalStack Deployment

```bash
# From project root
cd ../../

# Start LocalStack
docker-compose up -d

# Deploy upload system
./scripts/deploy-upload.sh
```

This deploys:
- Lambda function
- Lambda Function URL (not API Gateway)
- S3 bucket
- DynamoDB table
- S3 → Lambda event trigger

### Test

```bash
# Run end-to-end tests
./scripts/test-upload.sh
```

### AWS Deployment

```bash
# Build
cd lambdas/upload-api
npm run build

# Package
npm run package

# Deploy with SAM
sam deploy --guided

# Or use AWS CLI
aws lambda create-function \
  --function-name upload-api \
  --runtime nodejs18.x \
  --handler index.handler \
  --zip-file fileb://upload-api.zip \
  --role arn:aws:iam::ACCOUNT:role/lambda-role
```

## Development Workflow

### Typical Development Flow

```bash
# 1. Make code changes in src/
vim src/app.ts

# 2. Test with standalone server (instant feedback)
npm run dev:watch

# 3. Test specific changes
curl http://localhost:3000/initiate -X POST ...

# 4. When ready, test with SAM (Lambda simulation)
npm run sam:build
npm run sam:start

# 5. Test Lambda behavior
curl http://localhost:3000/initiate -X POST ...

# 6. Deploy to LocalStack for integration testing
cd ../../
./scripts/deploy-upload.sh
./scripts/test-upload.sh
```

### Debugging

**Standalone Server:**
```bash
# With Node debugger
node --inspect dist/server.js

# With Chrome DevTools
# Navigate to chrome://inspect
```

**SAM Local:**
```bash
# Enable debug mode
sam local start-api --debug

# With debugger
sam local start-api -d 5858
```

## File Structure

```
upload-api/
├── src/
│   ├── app.ts              # Fastify app (shared)
│   ├── server.ts           # Standalone server entry
│   ├── index.ts            # Lambda handler entry
│   ├── types.ts            # TypeScript interfaces
│   └── services/
│       ├── s3.service.ts   # S3 operations
│       └── db.service.ts   # DynamoDB operations
├── template.yaml           # SAM/CloudFormation template
├── package.json            # Dependencies & scripts
├── tsconfig.json           # TypeScript config
└── dist/                   # Compiled JavaScript
```

## Comparison Matrix

| Feature | Standalone | SAM Local | Lambda (LocalStack/AWS) |
|---------|-----------|-----------|-------------------------|
| **Startup Time** | ~1s | ~5s | ~10s |
| **Hot Reload** | ✅ Yes | ❌ No | ❌ No |
| **Lambda Runtime** | ❌ No | ✅ Yes | ✅ Yes |
| **API Gateway** | ❌ No | ✅ Yes | ⚠️ Function URL |
| **IAM Policies** | ❌ No | ✅ Yes | ✅ Yes |
| **S3 Integration** | ✅ Yes | ✅ Yes | ✅ Yes |
| **DynamoDB Integration** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Debugging** | ✅ Easy | ⚠️ Medium | ❌ Hard |
| **Best For** | Fast dev | Lambda testing | Integration |

## NPM Scripts

```json
{
  "dev": "Build and start standalone server",
  "dev:watch": "Auto-rebuild and restart on changes",
  "build": "Compile TypeScript to JavaScript",
  "clean": "Remove dist/ and *.zip files",
  "package": "Build and create deployment ZIP",
  "sam:build": "Build with SAM",
  "sam:start": "Start SAM local API Gateway",
  "sam:invoke": "Invoke Lambda function directly"
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 3000 | Server port (standalone mode only) |
| `HOST` | 0.0.0.0 | Server host (standalone mode only) |
| `S3_BUCKET` | poc-file-uploads | S3 bucket name |
| `TABLE_NAME` | poc-file-uploads | DynamoDB table name |
| `LOCALSTACK_HOSTNAME` | localhost | LocalStack endpoint |
| `AWS_ENDPOINT_URL` | http://localhost:4566 | AWS endpoint override |

## Troubleshooting

### Issue: Port already in use

```bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9

# Or use different port
PORT=3001 npm run dev
```

### Issue: TypeScript compilation errors

```bash
npm run clean
npm install
npm run build
```

### Issue: SAM can't connect to LocalStack

Make sure LocalStack is running:
```bash
docker ps | grep localstack
curl http://localhost:4566/health
```

Update `template.yaml`:
```yaml
Environment:
  Variables:
    AWS_ENDPOINT_URL: http://host.docker.internal:4566
```

### Issue: Cannot find module 'fastify'

```bash
npm install
npm run build
```

### Issue: CORS errors in browser

Standalone server has CORS enabled by default.

For SAM/Lambda, ensure API Gateway CORS is configured in `template.yaml`.

## Best Practices

### 1. Use Standalone for Development

✅ Fastest iteration cycle
✅ Best debugging experience
✅ Real-time logging

### 2. Use SAM for Lambda Testing

✅ Test before deployment
✅ Validate IAM policies
✅ Test API Gateway integration

### 3. Use LocalStack for Integration Testing

✅ Test complete system
✅ Test S3 events
✅ Test DynamoDB triggers

### 4. Keep app.ts Framework-Agnostic

The `app.ts` file should contain pure Fastify code with no AWS-specific logic.

AWS logic belongs in:
- `services/` - AWS SDK calls
- `index.ts` - Lambda wrapper only
- `template.yaml` - AWS configuration

### 5. Log Structured Data

```typescript
// ✅ Good
request.log.info({ uploadId, filename }, 'Upload initiated');

// ❌ Bad
console.log('Upload initiated for ' + uploadId);
```

## Performance Tips

### Standalone Server
- Use `npm run dev:watch` for hot reload
- Keep dependencies minimal
- Use async/await for all I/O

### SAM Local
- Use `sam build --cached` to speed up builds
- Keep Lambda package size small
- Pre-warm functions with health checks

### Lambda Production
- Increase memory for faster CPU
- Use provisioned concurrency for critical endpoints
- Enable X-Ray tracing for debugging

## Next Steps

1. **Add Tests**: Implement unit tests for services
2. **Add Metrics**: CloudWatch custom metrics
3. **Add Tracing**: AWS X-Ray integration
4. **Add Authentication**: Cognito or API Keys
5. **Add Rate Limiting**: Protect against abuse

## Resources

- [Fastify Documentation](https://www.fastify.io/)
- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [@fastify/aws-lambda](https://github.com/fastify/aws-lambda-fastify)
- [LocalStack Documentation](https://docs.localstack.cloud/)
