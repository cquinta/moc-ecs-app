#!/bin/bash

# SETUP INICIAL


export AWS_ACCOUNT="707257249187"
export AWS_PAGER=""
export APP_NAME="linuxtips-app"
export CLUSTER_NAME="linuxtips-ecs"
export  GOROOT="/usr/local/go"

GOPATH=~/.go
PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# This script handles the CI/CD pipeline for a Go application deployment on AWS ECS
# It performs linting, testing, building Docker image and infrastructure deployment

# Exit immediately if a command exits with a non-zero status

# Set environment variables
export AWS_ACCOUNT="707257249187"
export AWS_PAGER=""
export APP_NAME="linuxtips-app"
export CLUSTER_NAME="linuxtips-ecs" 
export BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# CI Pipeline for the Application
echo "APP - CI"

cd app/

# Run golangci-lint for static code analysis
echo "APP - LINT"
# go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.1.2

# binary will be $(go env GOPATH)/bin/golangci-lint
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.1.2

# or install it into ./bin/
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s v2.1.2



./bin/golangci-lint --version

./bin/golangci-lint run ./... -E errcheck

# Run application tests
echo "APP - TEST"
go test -v ./...

# Build Application
cd ../app

# Get Git commit hash for versioning
echo "BUILD - BUMP DE VERSAO"
GIT_COMMIT_HASH=$(git rev-parse --short HEAD)
echo $GIT_COMMIT_HASH

# Login to Amazon ECR
echo "BUILD - LOGIN NO ECR"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repository if it doesn't exist
echo "BUILD - CREATE ECR IF NOT EXISTS"
export REPOSITORY_NAME="linuxtips/$APP_NAME"


# Check if repository exists
REPO_EXISTS=$(aws ecr describe-repositories --repository-names $REPOSITORY_NAME 2>&1)

if [[ $REPO_EXISTS == *"RepositoryNotFoundException"* ]]; then
  echo "Repositório $REPOSITORY_NAME não encontrado. Criando..."
  
  # Create repository
  aws ecr create-repository --repository-name $REPOSITORY_NAME
  
  if [ $? -eq 0 ]; then
    echo "Repositório $REPOSITORY_NAME criado com sucesso."
  else
    echo "Falha ao criar o repositório $REPOSITORY_NAME."
    exit 1
  fi
else
  echo "Repositório $REPOSITORY_NAME já existe."
fi


# Build and tag Docker image
echo "BUILD - DOCKER BUILD"
docker build -t app .
docker tag app:latest $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/$REPOSITORY_NAME:$GIT_COMMIT_HASH

# Push Docker image to ECR
echo "BUILD - DOCKER PUBLISH"
docker push $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/$REPOSITORY_NAME:$GIT_COMMIT_HASH

# Deploy Infrastructure with Terraform
cd ../terraform

REPOSITORY_TAG=$AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/$REPOSITORY_NAME:$GIT_COMMIT_HASH

# Initialize Terraform again
echo "DEPLOY - TERRAFORM INIT"
terraform init -backend-config=environment/dev/backend.tfvars

# Plan Terraform changes
echo "DEPLOY - TERRAFORM PLAN"
terraform plan -var-file=environment/dev/terraform.tfvars -var container_image=$REPOSITORY_TAG

# Apply Terraform changes
echo "DEPLOY - TERRAFORM APPLY"
terraform apply --auto-approve -var-file=environment/dev/terraform.tfvars -var container_image=$REPOSITORY_TAG

echo "DEPLOY - WAIT DEPLOY"

aws ecs wait services-stable --cluster $CLUSTER_NAME --services $APP_NAME