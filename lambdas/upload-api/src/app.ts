import Fastify, { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { InitiateUploadRequest, InitiateUploadResponse, UploadStatusResponse, UploadError } from './types';
import { generatePresignedUrl, getBucketName } from './services/s3.service';
import { saveUploadRecord, generateUploadId, getUploadRecord } from './services/db.service';

/**
 * Create and configure Fastify application
 */
export function createApp(): FastifyInstance {
  const app = Fastify({
    logger: true,
    requestIdHeader: 'x-request-id'
  });

  // CORS configuration
  app.addHook('onRequest', async (request, reply) => {
    reply.header('Access-Control-Allow-Origin', '*');
    reply.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    reply.header('Access-Control-Allow-Headers', '*');

    if (request.method === 'OPTIONS') {
      reply.code(204).send();
    }
  });

  // Health check endpoint
  app.get('/health', async (request, reply) => {
    return { status: 'healthy', timestamp: new Date().toISOString() };
  });

  // POST /initiate - Initiate file upload
  app.post<{ Body: InitiateUploadRequest }>('/initiate', async (request, reply) => {
    const { filename, size, contentType } = request.body;

    // Validate request
    if (!filename || typeof filename !== 'string') {
      throw new UploadError('filename is required and must be a string', 400, 'INVALID_FILENAME');
    }

    if (!size || typeof size !== 'number' || size <= 0) {
      throw new UploadError('size is required and must be a positive number', 400, 'INVALID_SIZE');
    }

    if (!contentType || typeof contentType !== 'string') {
      throw new UploadError('contentType is required and must be a string', 400, 'INVALID_CONTENT_TYPE');
    }

    // Validate file size (max 100MB)
    const MAX_FILE_SIZE = 100 * 1024 * 1024;
    if (size > MAX_FILE_SIZE) {
      throw new UploadError(
        `File size exceeds maximum allowed size of ${MAX_FILE_SIZE} bytes`,
        413,
        'FILE_TOO_LARGE'
      );
    }

    request.log.info({ filename, size, contentType }, 'Initiating upload');

    // Generate unique upload ID
    const uploadId = generateUploadId();

    // Generate presigned S3 URL
    const { presignedUrl, s3Key, expiresAt } = await generatePresignedUrl(
      uploadId,
      filename,
      contentType
    );

    // Save metadata to DynamoDB
    await saveUploadRecord({
      uploadId,
      filename,
      contentType,
      expectedSize: size,
      s3Bucket: getBucketName(),
      s3Key,
      status: 'PENDING',
      presignedUrl,
      presignedUrlExpiry: expiresAt,
      initiatedAt: new Date().toISOString()
    });

    const response: InitiateUploadResponse = {
      uploadId,
      presignedUrl,
      expiresAt,
      s3Key
    };

    request.log.info({ uploadId }, 'Upload initiated successfully');

    return reply.code(200).send(response);
  });

  // GET /status/:uploadId - Check upload status
  app.get<{ Params: { uploadId: string } }>('/status/:uploadId', async (request, reply) => {
    const { uploadId } = request.params;

    if (!uploadId || uploadId.trim() === '') {
      throw new UploadError('uploadId is required', 400, 'MISSING_UPLOAD_ID');
    }

    request.log.info({ uploadId }, 'Checking upload status');

    // Get upload record from DynamoDB
    const record = await getUploadRecord(uploadId);

    if (!record) {
      throw new UploadError('Upload not found', 404, 'UPLOAD_NOT_FOUND');
    }

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

    // Return 201 Created when upload is completed
    // Return 200 OK for all other statuses
    const statusCode = record.status === 'COMPLETED' ? 201 : 200;

    request.log.info({ uploadId, status: record.status }, 'Upload status retrieved');

    return reply.code(statusCode).send(response);
  });

  // Error handler
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);

    if (error instanceof UploadError) {
      return reply.code(error.statusCode).send({
        error: error.code,
        message: error.message
      });
    }

    return reply.code(500).send({
      error: 'INTERNAL_SERVER_ERROR',
      message: error.message || 'An unexpected error occurred'
    });
  });

  return app;
}
