import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { AWSConfig } from '../types';

// AWS SDK configuration for LocalStack
const config: AWSConfig = {
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

const s3Client = new S3Client(config);
const BUCKET_NAME = process.env.S3_BUCKET || 'poc-file-uploads';
const PRESIGNED_URL_EXPIRY = 15 * 60; // 15 minutes in seconds

/**
 * Generate a presigned S3 PUT URL for file upload
 * @param uploadId Unique upload identifier
 * @param filename Original filename
 * @param contentType MIME type of the file
 * @returns Presigned URL and S3 key
 */
export async function generatePresignedUrl(
  uploadId: string,
  filename: string,
  contentType: string
): Promise<{ presignedUrl: string; s3Key: string; expiresAt: string }> {
  // Construct S3 key: uploads/{uploadId}/{filename}
  const s3Key = `uploads/${uploadId}/${filename}`;

  console.log(`📤 Generating presigned URL for: ${s3Key}`);

  // Create PutObject command
  const command = new PutObjectCommand({
    Bucket: BUCKET_NAME,
    Key: s3Key,
    ContentType: contentType
  });

  // Generate presigned URL
  const presignedUrl = await getSignedUrl(s3Client, command, {
    expiresIn: PRESIGNED_URL_EXPIRY
  });

  // Calculate expiry timestamp
  const expiresAt = new Date(Date.now() + PRESIGNED_URL_EXPIRY * 1000).toISOString();

  console.log(`✅ Presigned URL generated, expires at: ${expiresAt}`);

  return {
    presignedUrl,
    s3Key,
    expiresAt
  };
}

/**
 * Get S3 bucket name
 */
export function getBucketName(): string {
  return BUCKET_NAME;
}
