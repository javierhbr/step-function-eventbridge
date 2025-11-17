#!/bin/bash
set -e

echo "🔧 Setting up Local PoC Environment (TypeScript)"
echo "================================================="

# Check prerequisites
echo ""
echo "Checking prerequisites..."

if ! command -v node &> /dev/null; then
  echo "❌ Node.js is not installed. Please install Node.js 18+ first."
  exit 1
fi

if ! command -v npm &> /dev/null; then
  echo "❌ npm is not installed. Please install npm first."
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "❌ Docker is not installed. Please install Docker first."
  exit 1
fi

echo "✅ All prerequisites met"

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
