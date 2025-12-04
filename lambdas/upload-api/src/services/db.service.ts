import { DynamoDBClient, PutItemCommand, GetItemCommand } from '@aws-sdk/client-dynamodb';
import { FileUploadRecord, UploadError, AWSConfig } from '../types';

// AWS SDK configuration for LocalStack
const config: Omit<AWSConfig, 'forcePathStyle'> = {
  endpoint: process.env.LOCALSTACK_HOSTNAME
    ? `http://${process.env.LOCALSTACK_HOSTNAME}:4566`
    : 'http://localhost:4566',
  region: 'us-east-1',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test'
  }
};

const dynamoClient = new DynamoDBClient(config);
const TABLE_NAME = process.env.TABLE_NAME || 'poc-file-uploads';

/**
 * Save upload metadata to DynamoDB
 * @param record File upload record
 */
export async function saveUploadRecord(record: FileUploadRecord): Promise<void> {
  console.log(`💾 Saving upload record for: ${record.uploadId}`);

  const item: Record<string, any> = {
    uploadId: { S: record.uploadId },
    filename: { S: record.filename },
    contentType: { S: record.contentType },
    expectedSize: { N: record.expectedSize.toString() },
    s3Bucket: { S: record.s3Bucket },
    s3Key: { S: record.s3Key },
    status: { S: record.status },
    initiatedAt: { S: record.initiatedAt }
  };

  // Only add optional fields if they exist
  if (record.presignedUrl) {
    item.presignedUrl = { S: record.presignedUrl };
  }
  if (record.presignedUrlExpiry) {
    item.presignedUrlExpiry = { S: record.presignedUrlExpiry };
  }

  await dynamoClient.send(new PutItemCommand({
    TableName: TABLE_NAME,
    Item: item
  }));

  console.log(`✅ Upload record saved: ${record.uploadId}`);
}

/**
 * Get upload record from DynamoDB
 * @param uploadId Upload identifier
 * @returns File upload record or null if not found
 */
export async function getUploadRecord(uploadId: string): Promise<FileUploadRecord | null> {
  console.log(`🔍 Fetching upload record for: ${uploadId}`);

  const result = await dynamoClient.send(new GetItemCommand({
    TableName: TABLE_NAME,
    Key: {
      uploadId: { S: uploadId }
    }
  }));

  if (!result.Item) {
    console.log(`❌ Upload record not found: ${uploadId}`);
    return null;
  }

  // Parse DynamoDB item into FileUploadRecord
  const record: FileUploadRecord = {
    uploadId: result.Item.uploadId.S!,
    filename: result.Item.filename.S!,
    contentType: result.Item.contentType.S!,
    expectedSize: parseInt(result.Item.expectedSize.N!),
    actualSize: result.Item.actualSize?.N ? parseInt(result.Item.actualSize.N) : undefined,
    s3Bucket: result.Item.s3Bucket.S!,
    s3Key: result.Item.s3Key.S!,
    status: result.Item.status.S! as FileUploadRecord['status'],
    presignedUrl: result.Item.presignedUrl?.S,
    presignedUrlExpiry: result.Item.presignedUrlExpiry?.S,
    initiatedAt: result.Item.initiatedAt.S!,
    completedAt: result.Item.completedAt?.S,
    s3ETag: result.Item.s3ETag?.S,
    s3VersionId: result.Item.s3VersionId?.S,
    errorMessage: result.Item.errorMessage?.S
  };

  console.log(`✅ Upload record found: ${uploadId} (status: ${record.status})`);

  return record;
}

/**
 * Generate unique upload ID
 * Format: upload-{timestamp}-{random}
 */
export function generateUploadId(): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return `upload-${timestamp}-${random}`;
}
