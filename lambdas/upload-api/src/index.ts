import awsLambdaFastify from '@fastify/aws-lambda';
import { createApp } from './app';

/**
 * Lambda handler using Fastify with AWS Lambda adapter
 * This allows the same Fastify app to run in both Lambda and standalone mode
 */

// Create Fastify app
const app = createApp();

// Wrap Fastify app with AWS Lambda adapter
export const handler = awsLambdaFastify(app, {
  binaryMimeTypes: [
    'application/octet-stream',
    'application/pdf',
    'image/*',
    'video/*',
    'audio/*'
  ]
});
