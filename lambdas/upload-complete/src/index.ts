import { S3Event } from 'aws-lambda';
import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';

// AWS SDK configuration for LocalStack
const config = {
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
const s3Client = new S3Client({ ...config, forcePathStyle: true });
const TABLE_NAME = process.env.TABLE_NAME || 'poc-file-uploads';

/**
 * S3 event handler for upload completion
 * Triggered when a file is uploaded to S3 via presigned URL
 */
export const handler = async (event: S3Event): Promise<void> => {
  console.log('📨 S3 Event:', JSON.stringify(event, null, 2));

  // Process each S3 record
  for (const record of event.Records) {
    try {
      const bucket = record.s3.bucket.name;
      const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));

      console.log(`📦 Processing S3 object: ${bucket}/${key}`);

      // Extract uploadId from key: uploads/{uploadId}/{filename}
      const pathParts = key.split('/');
      if (pathParts.length < 3 || pathParts[0] !== 'uploads') {
        console.log(`⚠️  Skipping invalid key format: ${key}`);
        continue;
      }

      const uploadId = pathParts[1];
      console.log(`🔍 Upload ID: ${uploadId}`);

      // Get actual file metadata from S3
      const headResult = await s3Client.send(new HeadObjectCommand({
        Bucket: bucket,
        Key: key
      }));

      const fileSize = headResult.ContentLength || 0;
      const etag = headResult.ETag || '';

      console.log(`📊 File size: ${(fileSize / 1024 / 1024).toFixed(2)}MB, ETag: ${etag}`);

      // Update DynamoDB record
      await dynamoClient.send(new UpdateItemCommand({
        TableName: TABLE_NAME,
        Key: {
          uploadId: { S: uploadId }
        },
        UpdateExpression: 'SET #status = :status, actualSize = :size, completedAt = :completedAt, s3ETag = :etag',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':status': { S: 'COMPLETED' },
          ':size': { N: fileSize.toString() },
          ':completedAt': { S: new Date().toISOString() },
          ':etag': { S: etag }
        }
      }));

      console.log(`✅ Upload ${uploadId} marked COMPLETED`);
    } catch (error: any) {
      console.error(`❌ Error processing record:`, error);
      // Continue processing other records even if one fails
    }
  }

  console.log('✅ All S3 records processed');
};
