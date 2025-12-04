import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { InitiateUploadRequest, InitiateUploadResponse, UploadError } from '../types';
import { generatePresignedUrl, getBucketName } from '../services/s3.service';
import { saveUploadRecord, generateUploadId } from '../services/db.service';

/**
 * Handle POST /initiate
 * Generates presigned S3 URL and saves metadata to DynamoDB
 */
export async function handleInitiate(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
  console.log('📥 Initiate upload request');

  // Parse request body
  if (!event.body) {
    throw new UploadError('Request body is required', 400, 'MISSING_BODY');
  }

  let request: InitiateUploadRequest;
  try {
    request = JSON.parse(event.body);
  } catch (error) {
    throw new UploadError('Invalid JSON in request body', 400, 'INVALID_JSON');
  }

  // Validate request
  if (!request.filename || typeof request.filename !== 'string') {
    throw new UploadError('filename is required and must be a string', 400, 'INVALID_FILENAME');
  }

  if (!request.size || typeof request.size !== 'number' || request.size <= 0) {
    throw new UploadError('size is required and must be a positive number', 400, 'INVALID_SIZE');
  }

  if (!request.contentType || typeof request.contentType !== 'string') {
    throw new UploadError('contentType is required and must be a string', 400, 'INVALID_CONTENT_TYPE');
  }

  // Validate file size (max 100MB for this PoC)
  const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB
  if (request.size > MAX_FILE_SIZE) {
    throw new UploadError(
      `File size exceeds maximum allowed size of ${MAX_FILE_SIZE} bytes`,
      413,
      'FILE_TOO_LARGE'
    );
  }

  console.log(`📤 File: ${request.filename}, Size: ${(request.size / 1024 / 1024).toFixed(2)}MB`);

  // Generate unique upload ID
  const uploadId = generateUploadId();

  // Generate presigned S3 URL
  const { presignedUrl, s3Key, expiresAt } = await generatePresignedUrl(
    uploadId,
    request.filename,
    request.contentType
  );

  // Save metadata to DynamoDB
  await saveUploadRecord({
    uploadId,
    filename: request.filename,
    contentType: request.contentType,
    expectedSize: request.size,
    s3Bucket: getBucketName(),
    s3Key,
    status: 'PENDING',
    presignedUrl,
    presignedUrlExpiry: expiresAt,
    initiatedAt: new Date().toISOString()
  });

  // Prepare response
  const response: InitiateUploadResponse = {
    uploadId,
    presignedUrl,
    expiresAt,
    s3Key
  };

  console.log(`✅ Upload initiated: ${uploadId}`);

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(response)
  };
}
