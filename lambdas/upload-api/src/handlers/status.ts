import { APIGatewayProxyResult } from 'aws-lambda';
import { UploadStatusResponse, UploadError } from '../types';
import { getUploadRecord } from '../services/db.service';

/**
 * Handle GET /status/:uploadId
 * Returns upload status - HTTP 201 when completed, HTTP 200 when pending
 */
export async function handleStatus(uploadId: string): Promise<APIGatewayProxyResult> {
  console.log(`🔍 Status check for upload: ${uploadId}`);

  // Validate uploadId
  if (!uploadId || uploadId.trim() === '') {
    throw new UploadError('uploadId is required', 400, 'MISSING_UPLOAD_ID');
  }

  // Get upload record from DynamoDB
  const record = await getUploadRecord(uploadId);

  if (!record) {
    throw new UploadError('Upload not found', 404, 'UPLOAD_NOT_FOUND');
  }

  // Prepare response
  const response: UploadStatusResponse = {
    uploadId: record.uploadId,
    status: record.status,
    filename: record.filename,
    expectedSize: record.expectedSize,
    actualSize: record.actualSize,
    s3Bucket: record.s3Bucket,
    s3Key: record.s3Key,
    initiatedAt: record.initiatedAt,
    completedAt: record.completedAt,
    errorMessage: record.errorMessage
  };

  // Determine HTTP status code based on upload status
  // Return 201 Created when upload is completed
  // Return 200 OK for all other statuses (pending, failed)
  const statusCode = record.status === 'COMPLETED' ? 201 : 200;

  console.log(`✅ Status: ${record.status} (HTTP ${statusCode})`);

  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(response)
  };
}
