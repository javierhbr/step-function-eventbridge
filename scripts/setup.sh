#!/bin/bash
set -e

echo "🔧 Setting up Local PoC Environment (TypeScript)"
echo "================================================="

# Check prerequisites
echo ""
echo "Checking prerequisites..."

MISSING_PREREQS=0

if ! command -v node &> /dev/null; then
  echo "❌ Node.js is not installed (required: 18+)"
  MISSING_PREREQS=1
else
  echo "✅ Node.js found: $(node --version)"
fi

if ! command -v npm &> /dev/null; then
  echo "❌ npm is not installed"
  MISSING_PREREQS=1
else
  echo "✅ npm found: $(npm --version)"
fi

if ! command -v docker &> /dev/null; then
  echo "❌ Docker is not installed"
  MISSING_PREREQS=1
else
  echo "✅ Docker found: $(docker --version | head -1)"
fi

if ! command -v aws &> /dev/null; then
  echo "❌ AWS CLI is not installed"
  echo "   Install: brew install awscli"
  echo "   Or: pip install awscli-local"
  MISSING_PREREQS=1
else
  echo "✅ AWS CLI found: $(aws --version | head -1)"
fi

if [ $MISSING_PREREQS -eq 1 ]; then
  echo ""
  echo "Please install missing prerequisites and run setup again."
  exit 1
fi

echo ""
echo "✅ All prerequisites met!"

# Create directories if they don't exist
echo ""
echo "Creating directory structure..."
mkdir -p lambdas/{create-job,poller,simulated-api}/src
mkdir -p state-machine
mkdir -p localstack
mkdir -p scripts
mkdir -p volume

echo "✅ Directory structure created"

# Install dependencies for each Lambda
echo ""
echo "Installing Lambda dependencies..."

for lambda in create-job poller simulated-api; do
  echo ""
  echo "  Installing dependencies for $lambda..."
  cd "lambdas/$lambda"

  if [ ! -f "package.json" ]; then
    echo "    ⚠️  package.json not found for $lambda"
    cd ../..
    continue
  fi

  npm install
  echo "    ✅ Dependencies installed for $lambda"
  cd ../..
done

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Start LocalStack: docker-compose up -d"
echo "2. Deploy resources: ./scripts/deploy-local.sh"
echo "3. Run tests: ./scripts/test-local.sh"
