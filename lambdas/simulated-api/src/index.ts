import { DynamoDBClient, PutItemCommand, GetItemCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';

// Types
interface SimulatedApiEvent {
  action: 'CREATE_JOB' | 'CHECK_STATUS';
  jobId?: string;
  payload?: Record<string, any>;
}

interface CreateJobResponse {
  jobId: string;
  status: string;
  completionPolls: number;
}

interface CheckStatusResponse {
  jobId: string;
  status: 'IN_PROGRESS' | 'COMPLETED' | 'FAILED';
  pollCount: number;
  completionPolls: number;
}

interface ErrorResponse {
  error: string;
}

type ApiResponse = CreateJobResponse | CheckStatusResponse | ErrorResponse;

// DynamoDB configuration
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
const TABLE_NAME = 'poc-jobs';

export const handler = async (event: SimulatedApiEvent): Promise<ApiResponse> => {
  console.log('Simulated API Event:', JSON.stringify(event, null, 2));

  const { action, jobId, payload } = event;

  try {
    if (action === 'CREATE_JOB') {
      return await createJob(payload || {});
    }

    if (action === 'CHECK_STATUS') {
      if (!jobId) {
        return { error: 'jobId is required for CHECK_STATUS action' };
      }
      return await checkStatus(jobId);
    }

    return { error: 'Unknown action' };

  } catch (error) {
    console.error('❌ Error:', error);
    return {
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
};

async function createJob(payload: Record<string, any>): Promise<CreateJobResponse> {
  const newJobId = `job-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`;
  const completionPolls = Math.floor(Math.random() * 2) + 2; // 2 or 3 polls

  await dynamoClient.send(new PutItemCommand({
    TableName: TABLE_NAME,
    Item: {
      jobId: { S: newJobId },
      status: { S: 'IN_PROGRESS' },
      pollCount: { N: '0' },
      completionPolls: { N: completionPolls.toString() },
      payload: { S: JSON.stringify(payload) },
      createdAt: { S: new Date().toISOString() }
    }
  }));

  console.log(`✅ Created job ${newJobId}, completes after ${completionPolls} polls`);

  return {
    jobId: newJobId,
    status: 'IN_PROGRESS',
    completionPolls
  };
}

async function checkStatus(jobId: string): Promise<CheckStatusResponse | ErrorResponse> {
  const response = await dynamoClient.send(new GetItemCommand({
    TableName: TABLE_NAME,
    Key: { jobId: { S: jobId } }
  }));

  if (!response.Item) {
    return { error: 'Job not found' };
  }

  const pollCount = parseInt(response.Item.pollCount.N || '0');
  const completionPolls = parseInt(response.Item.completionPolls.N || '3');
  const newPollCount = pollCount + 1;

  // Update poll count
  await dynamoClient.send(new UpdateItemCommand({
    TableName: TABLE_NAME,
    Key: { jobId: { S: jobId } },
    UpdateExpression: 'SET pollCount = :count',
    ExpressionAttributeValues: { ':count': { N: newPollCount.toString() } }
  }));

  let status: 'IN_PROGRESS' | 'COMPLETED' = 'IN_PROGRESS';

  // Mark as completed if threshold reached
  if (newPollCount >= completionPolls) {
    status = 'COMPLETED';
    await dynamoClient.send(new UpdateItemCommand({
      TableName: TABLE_NAME,
      Key: { jobId: { S: jobId } },
      UpdateExpression: 'SET #s = :status, completedAt = :time',
      ExpressionAttributeNames: { '#s': 'status' },
      ExpressionAttributeValues: {
        ':status': { S: 'COMPLETED' },
        ':time': { S: new Date().toISOString() }
      }
    }));
  }

  console.log(`📊 Job ${jobId}: poll ${newPollCount}/${completionPolls} = ${status}`);

  return {
    jobId,
    status,
    pollCount: newPollCount,
    completionPolls
  };
}
