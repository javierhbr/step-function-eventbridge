import { DynamoDBClient, GetItemCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { SFNClient, SendTaskSuccessCommand, SendTaskFailureCommand } from '@aws-sdk/client-sfn';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

// Types
interface PollerEvent {
  jobId: string;
}

interface TaskTokenRecord {
  jobId: string;
  taskToken: string;
  executionId: string;
  attemptCount: number;
  maxAttempts: number;
  status: 'POLLING' | 'COMPLETED' | 'FAILED' | 'MAX_ATTEMPTS' | 'TIMEOUT';
}

interface JobStatus {
  jobId: string;
  status: 'IN_PROGRESS' | 'COMPLETED' | 'FAILED';
  pollCount: number;
  completionPolls: number;
}

interface PollerResponse {
  status: string;
  reconnected?: boolean;
  attempt?: number;
  maxAttempts?: number;
  error?: string;
}

interface CompletedJobResult {
  jobId: string;
  status: string;
  completedAt: string;
  attempts: number;
  result: JobStatus;
}

// AWS SDK configuration
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
const sfnClient = new SFNClient(config);
const lambdaClient = new LambdaClient(config);

const TOKENS_TABLE = 'poc-task-tokens';
const SIMULATED_API_LAMBDA = 'poc-simulated-api';

export const handler = async (event: PollerEvent): Promise<PollerResponse> => {
  console.log('🔍 Poller Event:', JSON.stringify(event, null, 2));

  const { jobId } = event;

  try {
    // 1. Get Task Token
    const tokenResponse = await dynamoClient.send(new GetItemCommand({
      TableName: TOKENS_TABLE,
      Key: { jobId: { S: jobId } }
    }));

    if (!tokenResponse.Item) {
      console.error(`❌ No token found for job ${jobId}`);
      return { status: 'ERROR', error: 'Token not found' };
    }

    const taskToken = tokenResponse.Item.taskToken.S!;
    const currentAttempts = parseInt(tokenResponse.Item.attemptCount.N || '0');
    const maxAttempts = parseInt(tokenResponse.Item.maxAttempts.N || '10');
    const currentStatus = tokenResponse.Item.status.S as TaskTokenRecord['status'];

    // 2. Check idempotency
    if (currentStatus !== 'POLLING') {
      console.log(`⚠️ Job ${jobId} already processed: ${currentStatus}`);
      return { status: currentStatus };
    }

    // 3. Increment attempt count
    const newAttemptCount = currentAttempts + 1;
    await dynamoClient.send(new UpdateItemCommand({
      TableName: TOKENS_TABLE,
      Key: { jobId: { S: jobId } },
      UpdateExpression: 'SET attemptCount = :count',
      ExpressionAttributeValues: { ':count': { N: newAttemptCount.toString() } }
    }));

    // 4. Check max attempts
    if (newAttemptCount > maxAttempts) {
      console.log(`❌ Max attempts exceeded for job ${jobId}`);
      await updateStatus(jobId, 'MAX_ATTEMPTS');
      await sfnClient.send(new SendTaskFailureCommand({
        taskToken,
        error: 'MaxAttemptsExceeded',
        cause: `Exceeded ${maxAttempts} polling attempts`
      }));
      return { status: 'MAX_ATTEMPTS' };
    }

    // 5. Check job status
    console.log(`📊 Checking status for job ${jobId}, attempt ${newAttemptCount}/${maxAttempts}`);

    const statusResponse = await lambdaClient.send(new InvokeCommand({
      FunctionName: SIMULATED_API_LAMBDA,
      Payload: JSON.stringify({
        action: 'CHECK_STATUS',
        jobId: jobId
      })
    }));

    const payloadString = Buffer.from(statusResponse.Payload!).toString();
    const jobStatus: JobStatus = JSON.parse(payloadString);
    console.log('Job status:', jobStatus);

    // 6. Act on status
    if (jobStatus.status === 'COMPLETED') {
      console.log(`🎉 Job ${jobId} COMPLETED! Reconnecting workflow...`);

      await updateStatus(jobId, 'COMPLETED');

      // MAGIC HAPPENS HERE: SendTaskSuccess reconnects the workflow!
      const result: CompletedJobResult = {
        jobId,
        status: 'COMPLETED',
        completedAt: new Date().toISOString(),
        attempts: newAttemptCount,
        result: jobStatus
      };

      await sfnClient.send(new SendTaskSuccessCommand({
        taskToken: taskToken,
        output: JSON.stringify(result)
      }));

      console.log(`✅ SendTaskSuccess sent! Workflow should continue now.`);
      return { status: 'COMPLETED', reconnected: true };

    } else if (jobStatus.status === 'FAILED') {
      console.log(`❌ Job ${jobId} FAILED`);
      await updateStatus(jobId, 'FAILED');
      await sfnClient.send(new SendTaskFailureCommand({
        taskToken,
        error: 'JobFailed',
        cause: 'External job failed'
      }));
      return { status: 'FAILED' };

    } else {
      console.log(`⏳ Job ${jobId} still IN_PROGRESS (${newAttemptCount}/${maxAttempts})`);
      return {
        status: 'IN_PROGRESS',
        attempt: newAttemptCount,
        maxAttempts
      };
    }

  } catch (error) {
    console.error('❌ Poller error:', error);
    throw error;
  }
};

async function updateStatus(
  jobId: string,
  status: TaskTokenRecord['status']
): Promise<void> {
  await dynamoClient.send(new UpdateItemCommand({
    TableName: TOKENS_TABLE,
    Key: { jobId: { S: jobId } },
    UpdateExpression: 'SET #s = :status, completedAt = :time',
    ExpressionAttributeNames: { '#s': 'status' },
    ExpressionAttributeValues: {
      ':status': { S: status },
      ':time': { S: new Date().toISOString() }
    }
  }));
}
