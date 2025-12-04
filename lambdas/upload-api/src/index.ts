import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { handleInitiate } from './handlers/initiate';
import { handleStatus } from './handlers/status';
import { UploadError } from './types';

/**
 * Main Lambda handler with simple path routing
 * Follows the same pattern as existing Lambdas (create-job, poller, simulated-api)
 */
export const handler = async (
  event: any
): Promise<APIGatewayProxyResult> => {
  console.log('📨 Upload API Event:', JSON.stringify(event, null, 2));

  // Extract path and method from event
  // Lambda Function URLs use rawPath and requestContext.http.method
  const path = event.rawPath || event.path || '';
  const method = event.requestContext?.http?.method || event.httpMethod || '';

  console.log(`🔀 Route: ${method} ${path}`);

  try {
    // Route: POST /initiate
    if (method === 'POST' && path === '/initiate') {
      return await handleInitiate(event);
    }

    // Route: GET /status/:uploadId
    if (method === 'GET' && path.startsWith('/status/')) {
      const uploadId = path.split('/')[2];
      if (!uploadId) {
        throw new UploadError('uploadId is required in path', 400, 'MISSING_UPLOAD_ID');
      }
      return await handleStatus(uploadId);
    }

    // 404 Not Found
    console.log(`❌ Route not found: ${method} ${path}`);
    return {
      statusCode: 404,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Not Found',
        message: `Route ${method} ${path} not found`
      })
    };
  } catch (error: any) {
    console.error('❌ Error:', error);

    // Handle custom UploadError
    if (error instanceof UploadError) {
      return {
        statusCode: error.statusCode,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: error.code,
          message: error.message
        })
      };
    }

    // Handle generic errors
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'INTERNAL_SERVER_ERROR',
        message: error.message || 'An unexpected error occurred'
      })
    };
  }
};
