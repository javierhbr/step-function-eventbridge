// Upload status types
export type UploadStatus = 'PENDING' | 'COMPLETED' | 'FAILED';

// DynamoDB record interface
export interface FileUploadRecord {
  uploadId: string;          // HASH key: "upload-{timestamp}-{random}"
  filename: string;          // Original filename
  contentType: string;       // MIME type
  expectedSize: number;      // Expected file size
  actualSize?: number;       // Actual uploaded size (from S3)
  s3Bucket: string;          // "poc-file-uploads"
  s3Key: string;             // "uploads/{uploadId}/{filename}"
  status: UploadStatus;

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

// POST /initiate request body
export interface InitiateUploadRequest {
  filename: string;
  size: number;
  contentType: string;
}

// POST /initiate response
export interface InitiateUploadResponse {
  uploadId: string;
  presignedUrl: string;
  expiresAt: string;
  s3Key: string;
}

// GET /status/:uploadId response
export interface UploadStatusResponse {
  uploadId: string;
  status: UploadStatus;
  filename: string;
  expectedSize?: number;
  actualSize?: number;
  s3Bucket?: string;
  s3Key?: string;
  initiatedAt: string;
  completedAt?: string;
  errorMessage?: string;
}

// AWS SDK configuration
export interface AWSConfig {
  endpoint: string;
  region: string;
  credentials: {
    accessKeyId: string;
    secretAccessKey: string;
  };
  forcePathStyle: boolean;
}

// Custom error class
export class UploadError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public code: string
  ) {
    super(message);
    this.name = 'UploadError';
  }
}
