import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

// Types
interface PollingConfig {
  intervalMinutes: number;
  maxAttempts: number;
  timeoutMinutes: number;
}

interface RecordData {
  id: string;
  data: Record<string, any>;
}

interface CreateJobEvent {
  record: RecordData;
  taskToken: string;
  executionId: string;
  pollingConfig: PollingConfig;
}

interface CreateJobResponse {
  jobId: string;
  status: string;
}

interface SimulatedApiResponse {
  jobId: string;
  status: string;
  completionPolls: number;
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
const lambdaClient = new LambdaClient(config);

const TOKENS_TABLE = 'poc-task-tokens';
const SIMULATED_API_LAMBDA = 'poc-simulated-api';

export const handler = async (event: CreateJobEvent): Promise<CreateJobResponse> => {
  console.log('CreateJob Event:', JSON.stringify(event, null, 2));

  const { record, taskToken, executionId, pollingConfig } = event;

  // 1. Create job in simulated API
  console.log('📤 Creating job in external API...');

  const apiResponse = await lambdaClient.send(new InvokeCommand({
    FunctionName: SIMULATED_API_LAMBDA,
    Payload: JSON.stringify({
      action: 'CREATE_JOB',
      payload: {
        recordId: record.id,
        data: record.data
      }
    })
  }));

  // Parse the response from the simulated API
  const payloadString = Buffer.from(apiResponse.Payload!).toString();
  const jobData: SimulatedApiResponse = JSON.parse(payloadString);
  const jobId = jobData.jobId;

  console.log(`✅ Job created: ${jobId}`);

  // 2. Save Task Token to DynamoDB
  const expiresAt = new Date(
    Date.now() + (pollingConfig.timeoutMinutes * 60 * 1000)
  ).toISOString();

  await dynamoClient.send(new PutItemCommand({
    TableName: TOKENS_TABLE,
    Item: {
      jobId: { S: jobId },
      taskToken: { S: taskToken },
      executionId: { S: executionId },
      createdAt: { S: new Date().toISOString() },
      expiresAt: { S: expiresAt },
      attemptCount: { N: '0' },
      maxAttempts: { N: pollingConfig.maxAttempts.toString() },
      status: { S: 'POLLING' }
    }
  }));

  console.log(`💾 Task token saved for job ${jobId}`);
  console.log(`⏳ Workflow now WAITING for callback...`);
  console.log(`🔄 Run manual polling: ./scripts/poll-manually.sh ${jobId}`);

  // Return job info (but workflow waits for SendTaskSuccess)
  return {
    jobId,
    status: 'POLLING'
  };
};
