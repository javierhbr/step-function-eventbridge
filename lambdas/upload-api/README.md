# File Upload System with S3 Presigned URLs

A complete serverless file upload system using AWS Lambda, S3, and DynamoDB, running on LocalStack for local development and testing.

## Architecture Overview

This system implements a production-ready file upload pattern using S3 presigned URLs to bypass Lambda's 6MB payload limit, supporting files up to 100MB.

### Components

1. **upload-api Lambda** - REST API with Lambda Function URL
   - POST /initiate - Generate presigned S3 URL
   - GET /status/:uploadId - Check upload status (returns HTTP 201 when completed)

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
├── upload-api/                    # REST API Lambda
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   ├── index.ts              # Main handler with path routing
│   │   ├── types.ts              # TypeScript interfaces
│   │   ├── handlers/
│   │   │   ├── initiate.ts       # POST /initiate
│   │   │   └── status.ts         # GET /status/:id
│   │   └── services/
│   │       ├── s3.service.ts     # Presigned URL generation
│   │       └── db.service.ts     # DynamoDB operations
│   └── dist/                     # Build output
└── upload-complete/               # S3 event handler Lambda
    ├── package.json
    ├── tsconfig.json
    ├── src/
    │   └── index.ts              # S3 event processor
    └── dist/                     # Build output

scripts/
├── deploy-upload.sh              # Deploy upload system
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

### Prerequisites

- Node.js 18+
- Docker Desktop
- AWS CLI
- TypeScript

### Install Dependencies

```bash
# Upload API Lambda
cd lambdas/upload-api
npm install

# Upload Complete Lambda
cd lambdas/upload-complete
npm install
```

### Build

```bash
# Build upload-api
cd lambdas/upload-api
npm run build

# Build upload-complete
cd lambdas/upload-complete
npm run build
```

### Available Scripts

Each Lambda has these npm scripts:

- `npm run build` - Compile TypeScript to JavaScript
- `npm run clean` - Remove dist/ and *.zip files
- `npm run package` - Build and create ZIP for deployment
- `npm run watch` - Watch mode for development

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

## Key Features

### 1. **Large File Support**
- Bypasses Lambda 6MB payload limit
- Supports files up to 100MB (configurable)
- Uses S3 presigned URLs for direct upload

### 2. **Production-Ready Patterns**
- Type-safe TypeScript implementation
- Comprehensive error handling
- Structured logging
- Idempotent operations

### 3. **LocalStack Compatible**
- Full local development environment
- No AWS account required for testing
- Identical to production AWS behavior

### 4. **RESTful API Design**
- Clear HTTP status codes
- HTTP 201 Created for completed uploads
- Standard error responses

### 5. **Event-Driven Architecture**
- S3 triggers Lambda automatically
- Decoupled components
- Scalable design

## AWS SDK Configuration

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
  forcePathStyle: true  // CRITICAL for LocalStack S3
};
```

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

### Issue: LocalStack not responding

```bash
docker-compose down
docker-compose up -d
# Wait 30 seconds for LocalStack to fully start
curl http://localhost:4566/health
```

### Issue: Presigned URL upload fails

Check CORS configuration:
```bash
aws --endpoint-url=http://localhost:4566 s3api get-bucket-cors \
  --bucket poc-file-uploads
```

### Issue: S3 event not triggering Lambda

Verify event notification:
```bash
aws --endpoint-url=http://localhost:4566 s3api get-bucket-notification-configuration \
  --bucket poc-file-uploads
```

## Contributing

When making changes:

1. Update TypeScript source files in `src/`
2. Run `npm run build` to compile
3. Test locally with LocalStack
4. Update this README if API changes

## License

This is a Proof of Concept project for demonstrating AWS Step Functions callback patterns and file upload architecture.
