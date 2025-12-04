# File Upload System with S3 Presigned URLs

A complete serverless file upload system using **Fastify**, AWS Lambda, S3, and DynamoDB, running on LocalStack for local development and testing.

## Architecture Overview

This system implements a production-ready file upload pattern using S3 presigned URLs to bypass Lambda's 6MB payload limit, supporting files up to 100MB.

**Built with Fastify** - The upload-api Lambda uses Fastify web framework and can run in three modes:
1. **Standalone Fastify Server** - Fast local development (~1s startup)
2. **AWS SAM Local** - Lambda + API Gateway simulation
3. **Lambda Deployment** - LocalStack/AWS production

See **[DEVELOPMENT.md](DEVELOPMENT.md)** for detailed development guide covering all three run modes.

### Components

1. **upload-api Lambda** - REST API powered by Fastify
   - GET /health - Health check endpoint
   - POST /initiate - Generate presigned S3 URL
   - GET /status/:uploadId - Check upload status (returns HTTP 201 when completed)
   - Supports Lambda Function URL and API Gateway

2. **upload-complete Lambda** - S3 event handler
   - Triggered when file lands in S3
   - Updates DynamoDB with completion status

3. **DynamoDB Table** - `poc-file-uploads`
   - Stores upload metadata and status

4. **S3 Bucket** - `poc-file-uploads`
   - Stores uploaded files
   - Configured with CORS for presigned URL uploads

## Directory Structure

```
lambdas/
├── upload-api/                    # REST API Lambda (Fastify)
│   ├── package.json               # Dependencies & npm scripts
│   ├── tsconfig.json             # TypeScript configuration
│   ├── template.yaml             # SAM/CloudFormation template
│   ├── README.md                 # This file
│   ├── DEVELOPMENT.md            # Detailed development guide
│   ├── src/
│   │   ├── app.ts                # Fastify application (shared)
│   │   ├── server.ts             # Standalone server entry point
│   │   ├── index.ts              # Lambda handler (uses @fastify/aws-lambda)
│   │   ├── types.ts              # TypeScript interfaces
│   │   └── services/
│   │       ├── s3.service.ts     # Presigned URL generation
│   │       └── db.service.ts     # DynamoDB operations
│   └── dist/                     # Build output (gitignored)
└── upload-complete/               # S3 event handler Lambda
    ├── package.json
    ├── tsconfig.json
    ├── src/
    │   └── index.ts              # S3 event processor
    └── dist/                     # Build output

scripts/
├── deploy-upload.sh              # Deploy upload system to LocalStack
├── test-upload.sh                # End-to-end tests
└── cleanup-upload.sh             # Remove all resources
```

## Upload Flow

```
1. Client → POST /initiate
   ├─ Generates unique uploadId: "upload-{timestamp}-{random}"
   ├─ Creates S3 presigned PUT URL (15 min expiry)
   ├─ Saves metadata to DynamoDB (status: PENDING)
   └─ Returns: { uploadId, presignedUrl, expiresAt, s3Key }

2. Client → PUT to S3 presigned URL (direct upload)
   ├─ Uploads file directly to S3
   ├─ Bypasses Lambda 6MB limit
   └─ Supports files >6MB (up to 100MB)

3. S3 → ObjectCreated event → upload-complete Lambda
   ├─ Gets file metadata from S3 (size, ETag)
   ├─ Updates DynamoDB (status: COMPLETED)
   └─ Records actual file size and completion timestamp

4. Client → GET /status/:uploadId (polling)
   ├─ Returns HTTP 200 when status = PENDING
   └─ Returns HTTP 201 when status = COMPLETED ✅
```

## API Endpoints

### GET /health

Health check endpoint for monitoring.

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-04T17:24:21.798Z"
}
```

### POST /initiate

Initiates a file upload and returns a presigned S3 URL.

**Request:**
```json
{
  "filename": "video.mp4",
  "size": 50000000,
  "contentType": "video/mp4"
}
```

**Response (200 OK):**
```json
{
  "uploadId": "upload-1701705600-abc123",
  "presignedUrl": "http://localhost:4566/poc-file-uploads/...",
  "expiresAt": "2024-12-04T10:15:00Z",
  "s3Key": "uploads/upload-1701705600-abc123/video.mp4"
}
```

**Validation:**
- `filename`: Required, must be a string
- `size`: Required, must be a positive number ≤ 100MB
- `contentType`: Required, must be a string (MIME type)

### GET /status/:uploadId

Checks the status of an upload.

**Response (200 OK - Pending):**
```json
{
  "uploadId": "upload-1701705600-abc123",
  "status": "PENDING",
  "filename": "video.mp4",
  "expectedSize": 50000000,
  "s3Bucket": "poc-file-uploads",
  "s3Key": "uploads/upload-1701705600-abc123/video.mp4",
  "initiatedAt": "2024-12-04T10:00:00Z"
}
```

**Response (201 Created - Completed):**
```json
{
  "uploadId": "upload-1701705600-abc123",
  "status": "COMPLETED",
  "filename": "video.mp4",
  "expectedSize": 50000000,
  "actualSize": 50000123,
  "s3Bucket": "poc-file-uploads",
  "s3Key": "uploads/upload-1701705600-abc123/video.mp4",
  "initiatedAt": "2024-12-04T10:00:00Z",
  "completedAt": "2024-12-04T10:05:00Z"
}
```

**Error Responses:**
- `404 Not Found` - Upload ID doesn't exist
- `400 Bad Request` - Invalid request parameters

## DynamoDB Schema

**Table:** `poc-file-uploads`

**Primary Key:** `uploadId` (String, HASH)

**Attributes:**
```typescript
interface FileUploadRecord {
  uploadId: string;          // "upload-{timestamp}-{random}"
  filename: string;          // Original filename
  contentType: string;       // MIME type
  expectedSize: number;      // Expected file size in bytes
  actualSize?: number;       // Actual uploaded size (from S3)
  s3Bucket: string;          // "poc-file-uploads"
  s3Key: string;             // "uploads/{uploadId}/{filename}"
  status: 'PENDING' | 'COMPLETED' | 'FAILED';

  // Presigned URL
  presignedUrl?: string;
  presignedUrlExpiry?: string;

  // Timestamps
  initiatedAt: string;       // ISO timestamp
  completedAt?: string;      // ISO timestamp

  // S3 metadata
  s3ETag?: string;
  s3VersionId?: string;

  // Error tracking
  errorMessage?: string;
}
```

## S3 Configuration

**Bucket:** `poc-file-uploads`

**Object Key Pattern:** `uploads/{uploadId}/{filename}`

**CORS Configuration:**
```json
{
  "CORSRules": [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["PUT", "POST", "GET"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }]
}
```

**Event Notification:**
- Event: `s3:ObjectCreated:*`
- Target: `poc-upload-complete` Lambda
- Filter: Prefix `uploads/`

## Development

> 📖 **See [DEVELOPMENT.md](DEVELOPMENT.md)** for comprehensive development guide covering all three run modes, debugging, and best practices.

### Prerequisites

- Node.js 18+
- Docker Desktop
- AWS CLI
- TypeScript
- AWS SAM CLI (optional, for SAM local mode)

### Quick Start - Standalone Development Mode

The fastest way to develop locally is using the standalone Fastify server:

```bash
# Install dependencies
cd lambdas/upload-api
npm install

# Start standalone server (runs TypeScript directly with tsx)
npm run dev

# Or with auto-reload on file changes
npm run dev:watch
```

Server will be available at **http://localhost:3000**

**Test the API:**
```bash
# Health check
curl http://localhost:3000/health

# Initiate upload
curl -X POST http://localhost:3000/initiate \
  -H "Content-Type: application/json" \
  -d '{"filename":"test.mp4","size":10485760,"contentType":"video/mp4"}'

# Check status
curl http://localhost:3000/status/UPLOAD_ID
```

### Three Development Modes

**1. Standalone Fastify Server** (Recommended for Development)
- ⚡ Fast startup (~1 second)
- 🔄 Hot reload with `npm run dev:watch`
- 🐛 Easy debugging
- 📝 Full logging with Fastify logger
- **Run:** `npm run dev`

**2. AWS SAM Local** (Lambda Testing)
- 🐳 Real Lambda environment (Docker containers)
- 🌐 API Gateway simulation
- 🔐 IAM policy testing
- **Run:** `npm run sam:build && npm run sam:start`

**3. LocalStack Deployment** (Integration Testing)
- ☁️ Full AWS stack simulation
- 🔗 S3 event triggers
- 📊 DynamoDB integration
- **Run:** `./scripts/deploy-upload.sh` (from project root)

### Available Scripts (upload-api)

```bash
# Development (uses tsx to run TypeScript directly)
npm run dev          # Start standalone Fastify server
npm run dev:watch    # Auto-reload on file changes (recommended!)

# Building
npm run build        # Compile TypeScript to JavaScript
npm run clean        # Remove dist/ and *.zip files
npm run package      # Build and create ZIP for deployment
npm run watch        # TypeScript watch mode

# SAM Local
npm run sam:build    # Build with SAM
npm run sam:start    # Start SAM local API Gateway (port 3000)
npm run sam:invoke   # Invoke Lambda function directly
```

**Note:** The `dev` and `dev:watch` scripts use `tsx` to run TypeScript files directly without pre-compilation for faster development iteration.

### Install Dependencies

```bash
# Upload API Lambda (includes Fastify, @fastify/aws-lambda, tsx)
cd lambdas/upload-api
npm install

# Upload Complete Lambda
cd ../upload-complete
npm install
```

## Deployment

### Start LocalStack

```bash
# From project root
docker-compose up -d
```

### Deploy Upload System

```bash
./scripts/deploy-upload.sh
```

This script will:
1. Create S3 bucket with CORS configuration
2. Create DynamoDB table
3. Build and package both Lambda functions
4. Deploy Lambdas to LocalStack
5. Create Lambda Function URL
6. Configure S3 → Lambda event trigger

**Output:**
```
✅ Function URL: http://xxxxxxxxxxxx.lambda-url.us-east-1.localhost.localstack.cloud:4566/
```

Save this URL for testing!

## Testing

### Automated Tests

```bash
./scripts/test-upload.sh
```

This runs a complete end-to-end test:
1. Initiates upload for 10MB test file
2. Uploads file to S3 via presigned URL
3. Polls for completion status
4. Verifies DynamoDB record
5. Verifies S3 file

### Manual Testing

**1. Initiate Upload:**
```bash
curl -X POST "http://YOUR_FUNCTION_URL/initiate" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test.mp4",
    "size": 10485760,
    "contentType": "video/mp4"
  }'
```

**2. Upload File to S3:**
```bash
# Use the presignedUrl from previous response
curl -X PUT "PRESIGNED_URL" \
  -H "Content-Type: video/mp4" \
  --upload-file /path/to/file.mp4
```

**3. Check Status:**
```bash
curl "http://YOUR_FUNCTION_URL/status/UPLOAD_ID"
```

## Cleanup

Remove all upload system resources:

```bash
./scripts/cleanup-upload.sh
```

This removes:
- Lambda functions and Function URL
- S3 bucket and all files
- DynamoDB table
- Local build artifacts

## Fastify Architecture

The upload-api uses **Fastify** web framework with a unique architecture that allows the same code to run in multiple environments:

```
┌─────────────────────────────────────────────────┐
│           src/app.ts                            │
│     (Fastify application code)                  │
│  ┌─────────────────────────────────┐            │
│  │ Routes:                         │            │
│  │  GET  /health                   │            │
│  │  POST /initiate                 │            │
│  │  GET  /status/:uploadId         │            │
│  └─────────────────────────────────┘            │
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

**Key Components:**
- **[src/app.ts](src/app.ts)** - Core Fastify application with all routes and middleware (framework-agnostic)
- **[src/server.ts](src/server.ts)** - Standalone server entry point for local development
- **[src/index.ts](src/index.ts)** - Lambda handler using `@fastify/aws-lambda` adapter
- **[template.yaml](template.yaml)** - SAM/CloudFormation template for Lambda deployment

This architecture provides maximum flexibility: develop fast with the standalone server, test with SAM local, and deploy to Lambda seamlessly.

## Key Features

### 1. **Fastify-Powered Performance**
- ⚡ Fast startup and low overhead
- 🔄 Run as standalone server OR Lambda
- 🎯 Same code, multiple deployment targets
- 📝 Built-in structured logging
- 🔌 Extensive plugin ecosystem

### 2. **Large File Support**
- Bypasses Lambda 6MB payload limit
- Supports files up to 100MB (configurable)
- Uses S3 presigned URLs for direct upload
- No API Gateway timeout issues

### 3. **Production-Ready Patterns**
- Type-safe TypeScript implementation
- Comprehensive error handling with custom error classes
- Structured logging with Fastify logger
- Idempotent operations
- CORS enabled for browser uploads

### 4. **LocalStack Compatible**
- Full local development environment
- No AWS account required for testing
- S3 checksum compatibility fixes included
- Identical to production AWS behavior

### 5. **RESTful API Design**
- Clear HTTP status codes (200 PENDING, 201 COMPLETED)
- Standard error responses
- Health check endpoint for monitoring
- Path parameter routing (/status/:uploadId)

### 6. **Event-Driven Architecture**
- S3 triggers Lambda automatically
- Decoupled components
- Scalable design
- Asynchronous upload completion

## AWS SDK Configuration

### LocalStack Configuration

All Lambdas use consistent LocalStack configuration:

```typescript
const config = {
  endpoint: process.env.LOCALSTACK_HOSTNAME
    ? `http://${process.env.LOCALSTACK_HOSTNAME}:4566`
    : 'http://localhost:4566',
  region: 'us-east-1',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test'
  },
  forcePathStyle: true  // CRITICAL for LocalStack S3 presigned URLs
};
```

### S3 Client Configuration (LocalStack Compatibility)

To avoid checksum validation issues with LocalStack, the S3 client disables automatic checksums:

```typescript
const s3Client = new S3Client({
  ...config,
  // Disable request checksums for LocalStack compatibility
  requestChecksumCalculation: 'WHEN_REQUIRED'
});
```

This prevents the AWS SDK from adding `x-amz-checksum-crc32` headers to presigned URLs, which LocalStack doesn't support properly. For production AWS, this configuration works fine as checksums are still calculated when required by the service.

## Error Handling

### Custom Error Class

```typescript
class UploadError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public code: string
  ) {
    super(message);
  }
}
```

### Error Codes

- `MISSING_BODY` (400) - Request body is missing
- `INVALID_JSON` (400) - Invalid JSON in request body
- `INVALID_FILENAME` (400) - Filename is invalid
- `INVALID_SIZE` (400) - File size is invalid
- `INVALID_CONTENT_TYPE` (400) - Content type is invalid
- `FILE_TOO_LARGE` (413) - File exceeds maximum size
- `UPLOAD_NOT_FOUND` (404) - Upload ID doesn't exist
- `INTERNAL_SERVER_ERROR` (500) - Unexpected error

## Monitoring

### CloudWatch Logs (LocalStack)

View Lambda logs:
```bash
docker logs localstack-poc -f
```

### DynamoDB Inspection

```bash
aws --endpoint-url=http://localhost:4566 dynamodb scan \
  --table-name poc-file-uploads \
  --output table
```

### S3 Inspection

```bash
aws --endpoint-url=http://localhost:4566 s3 ls \
  s3://poc-file-uploads/uploads/ --recursive
```

## Production Deployment

For AWS production deployment, modify:

1. **Remove LocalStack endpoint:**
   - Remove endpoint configuration from AWS SDK clients
   - Remove `forcePathStyle: true` from S3Client

2. **Configure IAM:**
   - Create proper IAM role for Lambdas
   - Grant S3 read/write permissions
   - Grant DynamoDB read/write permissions
   - Grant Lambda invoke permissions

3. **Set up CloudWatch:**
   - Configure log retention
   - Set up alarms for errors
   - Monitor Lambda duration and memory

4. **Configure API Gateway:**
   - Replace Lambda Function URL with API Gateway
   - Add authentication (Cognito, IAM, etc.)
   - Configure rate limiting
   - Enable caching

5. **S3 Configuration:**
   - Enable versioning
   - Configure lifecycle policies
   - Set up bucket policies
   - Enable encryption at rest

## Troubleshooting

### Issue: TypeScript compilation errors

```bash
cd lambdas/upload-api  # or upload-complete
npm run clean
npm install
npm run build
```

### Issue: "Cannot find module" when running npm run dev

Make sure `tsx` is installed as a dev dependency:
```bash
npm install --save-dev tsx
```

The `tsx` package allows running TypeScript files directly without pre-compilation, which is used by `npm run dev` for fast development.

### Issue: Port 3000 already in use

Kill the process using port 3000:
```bash
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=3001 npm run dev
```

### Issue: LocalStack not responding

```bash
docker-compose down
docker-compose up -d
# Wait 30 seconds for LocalStack to fully start
curl http://localhost:4566/_localstack/health
```

### Issue: Presigned URL upload fails with checksum error

The S3 service is configured with `requestChecksumCalculation: 'WHEN_REQUIRED'` to avoid LocalStack checksum validation issues. If you still see checksum errors:

1. Verify the S3 client configuration in [src/services/s3.service.ts](src/services/s3.service.ts)
2. Check CORS configuration:
```bash
aws --endpoint-url=http://localhost:4566 s3api get-bucket-cors \
  --bucket poc-file-uploads
```

### Issue: S3 event not triggering upload-complete Lambda

Verify event notification configuration:
```bash
aws --endpoint-url=http://localhost:4566 s3api get-bucket-notification-configuration \
  --bucket poc-file-uploads
```

Check LocalStack logs for errors:
```bash
docker logs localstack-poc -f
```

### Issue: SAM local can't connect to LocalStack

Update `template.yaml` environment variables to use `host.docker.internal`:
```yaml
Environment:
  Variables:
    AWS_ENDPOINT_URL: http://host.docker.internal:4566
    LOCALSTACK_HOSTNAME: host.docker.internal
```

This allows SAM's Docker container to access LocalStack running on the host machine.

## Contributing

When making changes:

1. Update TypeScript source files in `src/`
2. Test with standalone server: `npm run dev`
3. Test with SAM local: `npm run sam:build && npm run sam:start`
4. Run `npm run build` to compile for deployment
5. Deploy to LocalStack: `./scripts/deploy-upload.sh` (from project root)
6. Update this README if API changes

## Development Workflow

**Typical development flow:**

```bash
# 1. Make code changes in src/
vim src/app.ts

# 2. Test with standalone server (instant feedback, hot reload)
npm run dev:watch

# 3. Test specific changes
curl http://localhost:3000/initiate -X POST ...

# 4. When ready, test with SAM (Lambda simulation)
npm run sam:build
npm run sam:start

# 5. Deploy to LocalStack for integration testing
cd ../../
./scripts/deploy-upload.sh
./scripts/test-upload.sh
```

See **[DEVELOPMENT.md](DEVELOPMENT.md)** for detailed information on:
- Running in all three modes
- Debugging techniques
- Environment variables
- Performance tips
- Comparison matrix of deployment modes

## Resources

- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Comprehensive development guide
- [Fastify Documentation](https://www.fastify.io/)
- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [@fastify/aws-lambda](https://github.com/fastify/aws-lambda-fastify)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS SDK for JavaScript v3](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/)

## License

This is a Proof of Concept project for demonstrating AWS Lambda file upload patterns with S3 presigned URLs and Fastify framework.
