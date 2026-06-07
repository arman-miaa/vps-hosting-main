# 🐳 Docker + AWS ECR + ECS Fargate + Load Balancer Complete Deployment Guide

> **Author:** Arman Mia  
> **Last Updated:** 07 June 2026  
> **Stack:** Docker, AWS ECR, ECS Fargate, ALB, Node.js (Frontend + Backend)

---

## 📑 Table of Contents

1. [Project Structure & Starter Repos](#1-project-structure--starter-repos)
2. [AWS Account Setup & IAM User Creation](#2-aws-account-setup--iam-user-creation)
3. [AWS CLI Setup on VPS/Local](#3-aws-cli-setup-on-vpslocal)
4. [Docker Setup on VPS/Local](#4-docker-setup-on-vpslocal)
5. [Frontend Docker Setup](#5-frontend-docker-setup)
6. [Backend Docker Setup](#6-backend-docker-setup)
7. [ECR Repository Create & Push](#7-ecr-repository-create--push)
8. [ECS Fargate Cluster Setup](#8-ecs-fargate-cluster-setup)
9. [Task Definition (Backend + Frontend)](#9-task-definition-backend--frontend)
10. [Application Load Balancer Setup](#10-application-load-balancer-setup)
11. [ECS Services Create (Frontend + Backend)](#11-ecs-services-create-frontend--backend)
12. [Full Deploy Automation Scripts](#12-full-deploy-automation-scripts)
13. [Environment Variables & Secrets](#13-environment-variables--secrets)
14. [Troubleshooting & Logs](#14-troubleshooting--logs)
15. [Cleanup & Cost Management](#15-cleanup--cost-management)

---

## 1. Project Structure & Starter Repos

### 📁 Frontend Repo: `fargate-frontend`
```
fargate-frontend/
├── Dockerfile
├── .dockerignore
├── package.json
├── next.config.js
├── src/
│   ├── app/
│   │   ├── page.tsx
│   │   └── health/
│   │       └── route.ts
│   └── ...
└── public/
```

### 📁 Backend Repo: `fargate-backend`
```
fargate-backend/
├── Dockerfile
├── .dockerignore
├── package.json
├── tsconfig.json
├── prisma/
│   └── schema.prisma
└── src/
    ├── index.ts
    └── routes/
```

### 🎯 Starter Repo Create

```bash
# GitHub এ 2টা আলাদা repo বানাও:
# 1. fargate-frontend (Next.js)
# 2. fargate-backend (Express)

# Frontend clone & setup
git clone git@github.com:your-username/fargate-frontend.git
cd fargate-frontend

# Basic Next.js app create
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir
# সব প্রশ্নে Yes/Enter চাপো

# Backend clone & setup
cd ..
git clone git@github.com:your-username/fargate-backend.git
cd fargate-backend

# Basic Express + TypeScript setup
npm init -y
npm install express cors dotenv
npm install -D typescript @types/express @types/node ts-node nodemon
npx tsc --init
```

---

## 2. AWS Account Setup & IAM User Creation

### 🔐 AWS Free Tier Account Create

1. **AWS Website:** [aws.amazon.com](https://aws.amazon.com)
2. **Sign Up:** Email, Password, AWS Account Name দাও
3. **Contact Info:** Personal/Business select করো
4. **Credit Card:** $1 temporary charge হবে, পরে refund
5. **Identity Verify:** Phone number দাও, OTP দিবে
6. **Support Plan:** **Basic Support - Free** select করো

### 👤 IAM User Create

> ⚠️ **Root User দিয়ে কাজ করবে না — সবসময় IAM User use করো!**

```
AWS Console → IAM → Users → Create User
  User name: fargate-deployer
  ☑️ Provide user access to AWS Management Console (Optional)

Permissions:
  Select: Attach policies directly
  ☑️ AmazonEC2ContainerRegistryFullAccess
  ☑️ AmazonECS_FullAccess
  ☑️ AmazonEC2FullAccess (Security Groups + ALB এর জন্য)

→ Create User
→ Security credentials ট্যাবে যাও
→ Access keys section → Create access key
→ Use case: Command Line Interface (CLI)
→ ☑️ Confirmation checkbox
→ Next → Create access key
→ ⚠️ Download .csv file (এই file safe রাখো, share করবে না!)
```

### 🔑 Credentials File Format

```
User name,Password,Access key ID,Secret access key,Console login link
fargate-deployer,,AKIAXXXXXXXXXXXXXXXX,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx,https://123456789012.signin.aws.amazon.com/console
```

---

## 3. AWS CLI Setup on VPS/Local

### 📦 Install AWS CLI v2

```bash
# Download AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip & Install
sudo apt install unzip -y
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
# Expected: aws-cli/2.x.x

# Cleanup
rm -rf aws awscliv2.zip
```

### ⚙️ Configure AWS CLI

```bash
aws configure

# Input prompts:
AWS Access Key ID [None]: AKIAXXXXXXXXXXXXXXXX              # CSV file থেকে
AWS Secret Access Key [None]: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # CSV file থেকে
Default region name [None]: us-east-1                         # N. Virginia
Default output format [None]: json

# Verify
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/fargate-deployer"
}
```

### 📝 Important Variables Set

```bash
# পুরো project-এ এই variable বারবার লাগবে, এখনই set করে রাখো
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Region: $AWS_REGION"
echo "Account ID: $AWS_ACCOUNT_ID"

# একটা .env file বানিয়ে রাখো (পরেও কাজে দিবে)
cat > fargate.env <<EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
EOF

echo "✅ fargate.env file created"
```

### 🌍 Region Selection Guide

| Region | Code | Latency (BD) | Price |
|:---|:---|:---|:---|
| N. Virginia | `us-east-1` | ~250ms | 💰 সবচেয়ে সস্তা |
| Ohio | `us-east-2` | ~260ms | 💰💰 |
| Singapore | `ap-southeast-1` | ~80ms | 💰💰💰 |
| Mumbai | `ap-south-1` | ~60ms | 💰💰💰 |
| Tokyo | `ap-northeast-1` | ~120ms | 💰💰💰💰 |

> 💡 **Recommendation:** Practice-এর জন্য `us-east-1` use করো — Free tier benefit সবচেয়ে বেশি!

---

## 4. Docker Setup on VPS/Local

### 🐳 Install Docker Engine

```bash
# Docker Official GPG key add
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group (sudo ছাড়া docker চালাতে)
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker compose version

# Test Docker
docker run hello-world
# Expected: "Hello from Docker! This message shows that your installation appears to be working correctly."
```

### 🔧 Docker Compose (already included with docker-compose-plugin)

```bash
# Check version
docker compose version
# Expected: Docker Compose version v2.x.x
```

---

## 5. Frontend Docker Setup

### 📄 `next.config.js`

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',  // ⚠️ Docker multi-stage build-এর জন্য এটা জরুরি!
}

module.exports = nextConfig
```

### 📄 `src/app/health/route.ts` (Health Check Endpoint)

```typescript
// ALB Health Check এর জন্য dedicated route
export async function GET() {
  return Response.json({ 
    status: 'ok', 
    service: 'frontend',
    timestamp: new Date().toISOString() 
  });
}
```

### 📄 `Dockerfile` (Next.js — Multi-stage build)

```dockerfile
# fargate-frontend/Dockerfile

# ===== Stage 1: Dependencies =====
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile

# ===== Stage 2: Build =====
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
RUN npm install -g pnpm && pnpm build

# ===== Stage 3: Production =====
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
```

### 📄 `.dockerignore` (Frontend)

```
node_modules
.next
.git
.gitignore
README.md
.env
.env.local
.env*.local
Dockerfile
.dockerignore
npm-debug.log*
```

### 🔨 Build & Test Locally

```bash
cd fargate-frontend

# Docker image build
docker build -t fargate-frontend:latest .

# Run container locally for testing
docker run -d -p 3000:3000 --name frontend-test fargate-frontend:latest

# Test endpoints
curl http://localhost:3000
curl http://localhost:3000/health

# Check logs (if any issue)
docker logs frontend-test

# Stop & remove test container
docker stop frontend-test && docker rm frontend-test
```

---

## 6. Backend Docker Setup

### 📄 `src/index.ts` (Basic Express Server)

```typescript
import express, { Request, Response } from 'express';
import cors from 'cors';

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// ⚠️ ALB Health Check এর জন্য এই route জরুরি!
app.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'ok',
    service: 'backend',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// API routes
app.get('/api', (req: Request, res: Response) => {
  res.json({ 
    message: 'Hello from Backend!', 
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`🚀 Backend running on port ${PORT}`);
});
```

### 📄 `package.json` Scripts

```json
{
  "name": "fargate-backend",
  "version": "1.0.0",
  "scripts": {
    "dev": "nodemon src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  }
}
```

### 📄 `Dockerfile` (Express + TypeScript — Multi-stage)

```dockerfile
# fargate-backend/Dockerfile

# ===== Stage 1: Build =====
FROM node:20-alpine AS builder
WORKDIR /app

RUN npm install -g pnpm

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

# ===== Stage 2: Production =====
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 appuser

COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

USER appuser
EXPOSE 5000

CMD ["node", "dist/index.js"]
```

### 📄 `.dockerignore` (Backend)

```
node_modules
dist
.git
.gitignore
README.md
.env
Dockerfile
.dockerignore
npm-debug.log*
```

### 🔨 Build & Test Locally

```bash
cd fargate-backend

# Docker image build
docker build -t fargate-backend:latest .

# Run container locally for testing
docker run -d -p 5000:5000 --name backend-test fargate-backend:latest

# Test endpoints
curl http://localhost:5000/health
curl http://localhost:5000/api

# Check logs (if any issue)
docker logs backend-test

# Stop & remove test container
docker stop backend-test && docker rm backend-test
```

---

## 7. ECR Repository Create & Push

### 📦 Create ECR Repositories

```bash
# Load variables (if not already set)
source fargate.env

# Create Backend ECR repository
aws ecr create-repository \
    --repository-name fargate-backend \
    --region $AWS_REGION \
    --image-tag-mutability MUTABLE \
    --image-scanning-configuration scanOnPush=true

# Create Frontend ECR repository
aws ecr create-repository \
    --repository-name fargate-frontend \
    --region $AWS_REGION \
    --image-tag-mutability MUTABLE \
    --image-scanning-configuration scanOnPush=true

# Verify repositories
aws ecr describe-repositories --region $AWS_REGION --query 'repositories[*].{Name:repositoryName,URI:repositoryUri}' --output table
```

**Expected output:**
```
----------------------------------------------
|        DescribeRepositories               |
+-----------------+--------------------------+
|      Name       |          URI             |
+-----------------+--------------------------+
| fargate-backend | 123456789012.dkr.ecr...  |
| fargate-frontend| 123456789012.dkr.ecr...  |
+-----------------+--------------------------+
```

> 📝 **Repository URI format:** `$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/repo-name`

### 🔐 Login to ECR

```bash
# Docker login to ECR
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Expected: Login Succeeded
```

### 🏷️ Build, Tag & Push Backend

```bash
cd fargate-backend

# Build image
docker build -t fargate-backend:latest .

# Tag with ECR URI
docker tag fargate-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
docker tag fargate-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:v1

# Push images
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:v1

# Verify pushed images
aws ecr list-images --repository-name fargate-backend --region $AWS_REGION

cd ..
```

### 🏷️ Build, Tag & Push Frontend

```bash
cd fargate-frontend

# Build image
docker build -t fargate-frontend:latest .

# Tag with ECR URI
docker tag fargate-frontend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
docker tag fargate-frontend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:v1

# Push images
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:v1

# Verify pushed images
aws ecr list-images --repository-name fargate-frontend --region $AWS_REGION

cd ..
```

---

## 8. ECS Fargate Cluster Setup

### 🏗️ Create ECS Cluster

```bash
source fargate.env

aws ecs create-cluster \
    --cluster-name fargate-cluster \
    --region $AWS_REGION \
    --capacity-providers FARGATE FARGATE_SPOT \
    --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1,base=1

echo "✅ ECS Cluster 'fargate-cluster' created"
```

> **Console path:** `AWS Console → ECS → Clusters → Create Cluster → Fargate ✓ → Create`

### 🔐 Create Security Groups

```bash
source fargate.env

# Get default VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region $AWS_REGION)
echo "VPC ID: $VPC_ID"

# ====== ALB Security Group (Public facing) ======
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name fargate-alb-sg \
    --description "ALB Security Group - Allow HTTP/HTTPS from Internet" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)
echo "ALB SG ID: $ALB_SG_ID"

# ALB Rules: Allow HTTP & HTTPS from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

echo "✅ ALB Security Group configured"

# ====== Fargate Service Security Group (Internal) ======
SERVICE_SG_ID=$(aws ec2 create-security-group \
    --group-name fargate-service-sg \
    --description "Fargate Services - Accept traffic only from ALB" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)
echo "Service SG ID: $SERVICE_SG_ID"

# Service Rules: Only allow traffic from ALB (frontend port 3000, backend port 5000)
aws ec2 authorize-security-group-ingress \
    --group-id $SERVICE_SG_ID \
    --protocol tcp \
    --port 3000 \
    --source-group $ALB_SG_ID \
    --region $AWS_REGION

aws ec2 authorize-security-group-ingress \
    --group-id $SERVICE_SG_ID \
    --protocol tcp \
    --port 5000 \
    --source-group $ALB_SG_ID \
    --region $AWS_REGION

echo "✅ Service Security Group configured"

# Save variables to env file for later use
cat >> fargate.env <<EOF
VPC_ID=$VPC_ID
ALB_SG_ID=$ALB_SG_ID
SERVICE_SG_ID=$SERVICE_SG_ID
EOF

echo "✅ Security Group IDs saved to fargate.env"
```

---

## 9. Task Definition (Backend + Frontend)

### 📋 Create IAM Task Execution Role

```bash
source fargate.env

# Create role
aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }' \
    --region $AWS_REGION

# Attach required policies
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
    --region $AWS_REGION

# If using Secrets Manager (Section 13), also attach:
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
    --region $AWS_REGION

echo "✅ IAM Role 'ecsTaskExecutionRole' created"

# Save Role ARN
ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole"
echo "ROLE_ARN=$ROLE_ARN" >> fargate.env
```

> **Console path:** `IAM → Roles → Create Role → AWS Service → ECS Task → AmazonECSTaskExecutionRolePolicy → Role Name: ecsTaskExecutionRole`

### 📄 Create Backend Task Definition File

```bash
cat > backend-task-definition.json <<EOF
{
    "family": "fargate-backend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [
        {
            "name": "backend",
            "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest",
            "portMappings": [
                {
                    "name": "backend-5000-tcp",
                    "containerPort": 5000,
                    "hostPort": 5000,
                    "protocol": "tcp",
                    "appProtocol": "http"
                }
            ],
            "essential": true,
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "5000"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/fargate-backend",
                    "awslogs-region": "$AWS_REGION",
                    "awslogs-stream-prefix": "backend",
                    "awslogs-create-group": "true"
                }
            },
            "healthCheck": {
                "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            }
        }
    ]
}
EOF

echo "✅ backend-task-definition.json created"
```

### 📄 Create Frontend Task Definition File

```bash
cat > frontend-task-definition.json <<EOF
{
    "family": "fargate-frontend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [
        {
            "name": "frontend",
            "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest",
            "portMappings": [
                {
                    "name": "frontend-3000-tcp",
                    "containerPort": 3000,
                    "hostPort": 3000,
                    "protocol": "tcp",
                    "appProtocol": "http"
                }
            ],
            "essential": true,
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "3000"
                },
                {
                    "name": "NEXT_PUBLIC_API_URL",
                    "value": "/api"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/fargate-frontend",
                    "awslogs-region": "$AWS_REGION",
                    "awslogs-stream-prefix": "frontend",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF

echo "✅ frontend-task-definition.json created"
```

> ⚠️ **Important:** `NEXT_PUBLIC_API_URL` এখন `/api` দিয়েছি। পরে ALB DNS পাওয়ার পর update করে দিবো (Section 11 দেখো)।

### 📝 Register Task Definitions

```bash
source fargate.env

# Register Backend task definition
aws ecs register-task-definition \
    --cli-input-json file://backend-task-definition.json \
    --region $AWS_REGION

# Register Frontend task definition
aws ecs register-task-definition \
    --cli-input-json file://frontend-task-definition.json \
    --region $AWS_REGION

# Verify registered task definitions
aws ecs list-task-definitions --region $AWS_REGION
```

---

## 10. Application Load Balancer Setup

### ⚖️ ALB Routing Flow

```
User Request (Browser)
    │
    ▼
Application Load Balancer (HTTP:80)
    │
    ├── Path: /api/* ──────► Backend Target Group (Port 5000)
    │                              │
    │                              └──► Fargate Backend Container
    │
    └── Path: /* (Default) ─► Frontend Target Group (Port 3000)
                                   │
                                   └──► Fargate Frontend Container
```

### Step 1: Get Subnet IDs

```bash
source fargate.env

SUBNET_1=$(aws ec2 describe-subnets \
    --filters Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' \
    --output text \
    --region $AWS_REGION)

SUBNET_2=$(aws ec2 describe-subnets \
    --filters Name=default-for-az,Values=true \
    --query 'Subnets[1].SubnetId' \
    --output text \
    --region $AWS_REGION)

echo "Subnet 1: $SUBNET_1"
echo "Subnet 2: $SUBNET_2"

# Save to env file
echo "SUBNET_1=$SUBNET_1" >> fargate.env
echo "SUBNET_2=$SUBNET_2" >> fargate.env
```

### Step 2: Create Application Load Balancer

```bash
source fargate.env

ALB_ARN=$(aws elbv2 create-load-balancer \
    --name fargate-alb \
    --subnets $SUBNET_1 $SUBNET_2 \
    --security-groups $ALB_SG_ID \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

echo "ALB ARN: $ALB_ARN"

# Get ALB DNS Name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text \
    --region $AWS_REGION)

echo "=============================================="
echo "🔗 ALB DNS Name: $ALB_DNS"
echo "=============================================="

# Save to env file
echo "ALB_ARN=$ALB_ARN" >> fargate.env
echo "ALB_DNS=$ALB_DNS" >> fargate.env
```

**Sample ALB DNS:** `fargate-alb-1234567890.us-east-1.elb.amazonaws.com`

### Step 3: Create Target Groups

```bash
source fargate.env

# Backend Target Group
BACKEND_TG_ARN=$(aws elbv2 create-target-group \
    --name backend-tg \
    --protocol HTTP \
    --port 5000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Backend TG ARN: $BACKEND_TG_ARN"

# Frontend Target Group
FRONTEND_TG_ARN=$(aws elbv2 create-target-group \
    --name frontend-tg \
    --protocol HTTP \
    --port 3000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Frontend TG ARN: $FRONTEND_TG_ARN"

# Save to env file
echo "BACKEND_TG_ARN=$BACKEND_TG_ARN" >> fargate.env
echo "FRONTEND_TG_ARN=$FRONTEND_TG_ARN" >> fargate.env
```

### Step 4: Create Listener & Routing Rules

```bash
source fargate.env

# Create default listener → forwards to Frontend
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$FRONTEND_TG_ARN \
    --region $AWS_REGION

echo "✅ ALB Listener created (default → Frontend)"

# Get Listener ARN
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --query 'Listeners[0].ListenerArn' \
    --output text \
    --region $AWS_REGION)

echo "LISTENER_ARN=$LISTENER_ARN" >> fargate.env

# Create routing rule: /api/* → Backend Target Group
aws elbv2 create-rule \
    --listener-arn $LISTENER_ARN \
    --priority 10 \
    --conditions Field=path-pattern,Values='/api/*' \
    --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN \
    --region $AWS_REGION

echo "✅ Routing rule created: /api/* → Backend"
```

---

## 11. ECS Services Create (Frontend + Backend)

### 🔧 Create Backend Service

```bash
source fargate.env

aws ecs create-service \
    --cluster fargate-cluster \
    --service-name backend-service \
    --task-definition fargate-backend-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SERVICE_SG_ID],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$BACKEND_TG_ARN,containerName=backend,containerPort=5000" \
    --region $AWS_REGION

echo "✅ Backend service created"
```

### 🎨 Create Frontend Service

```bash
source fargate.env

aws ecs create-service \
    --cluster fargate-cluster \
    --service-name frontend-service \
    --task-definition fargate-frontend-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SERVICE_SG_ID],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$FRONTEND_TG_ARN,containerName=frontend,containerPort=3000" \
    --region $AWS_REGION

echo "✅ Frontend service created"
```

### 🔍 Check Service Status

```bash
source fargate.env

# Check both services status
aws ecs describe-services \
    --cluster fargate-cluster \
    --services backend-service frontend-service \
    --region $AWS_REGION \
    --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' \
    --output table
```

**Expected output (after 2-5 minutes):**
```
-------------------------------------------------
|              DescribeServices                 |
+------------------+--------+---------+---------+
|       Name       |Status  |Running  |Desired  |
+------------------+--------+---------+---------+
| backend-service  | ACTIVE |  1      |  1      |
| frontend-service | ACTIVE |  1      |  1      |
+------------------+--------+---------+---------+
```

### 🧪 Test Your Deployed Application

```bash
source fargate.env

echo "=============================================="
echo "🔗 Frontend URL: http://$ALB_DNS"
echo "🔗 Backend API:  http://$ALB_DNS/api"
echo "🔗 Health Check: http://$ALB_DNS/health"
echo "=============================================="

# Test backend health
echo "Testing backend health..."
curl -s http://$ALB_DNS/api/health | python3 -m json.tool 2>/dev/null || curl -s http://$ALB_DNS/api/health

# Test backend API
echo -e "\nTesting backend API..."
curl -s http://$ALB_DNS/api | python3 -m json.tool 2>/dev/null || curl -s http://$ALB_DNS/api

# Test frontend
echo -e "\nTesting frontend..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://$ALB_DNS/
```

### 🔄 Update Frontend API URL (After getting ALB DNS)

```bash
source fargate.env

# Now update the frontend task definition with actual ALB DNS
cat > frontend-task-definition.json <<EOF
{
    "family": "fargate-frontend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [
        {
            "name": "frontend",
            "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest",
            "portMappings": [
                {
                    "name": "frontend-3000-tcp",
                    "containerPort": 3000,
                    "hostPort": 3000,
                    "protocol": "tcp",
                    "appProtocol": "http"
                }
            ],
            "essential": true,
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "3000"
                },
                {
                    "name": "NEXT_PUBLIC_API_URL",
                    "value": "http://$ALB_DNS/api"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/fargate-frontend",
                    "awslogs-region": "$AWS_REGION",
                    "awslogs-stream-prefix": "frontend",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF

# Register updated task definition
aws ecs register-task-definition \
    --cli-input-json file://frontend-task-definition.json \
    --region $AWS_REGION

# Update service with new task definition
aws ecs update-service \
    --cluster fargate-cluster \
    --service frontend-service \
    --task-definition fargate-frontend-task \
    --force-new-deployment \
    --region $AWS_REGION

echo "✅ Frontend API URL updated to: http://$ALB_DNS/api"
```

---

## 12. Full Deploy Automation Scripts

### 🚀 `fargate-deploy.sh` — One-Command Deploy

```bash
cat > fargate-deploy.sh <<'SCRIPT'
#!/bin/bash
# ============================================
# Fargate Full Deploy Script
# Usage: ./fargate-deploy.sh
# ============================================

set -euo pipefail

# Load environment variables
if [ -f fargate.env ]; then
    source fargate.env
else
    echo "❌ fargate.env file not found!"
    echo "Run: source fargate.env first, or set variables manually"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}🚀 Starting Fargate Deployment${NC}"
echo -e "${YELLOW}=========================================${NC}"

# ===== Step 1: ECR Login =====
echo -e "${GREEN}[1/7] Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com || {
    echo -e "${RED}❌ ECR login failed${NC}"
    exit 1
}

# ===== Step 2: Build & Push Backend =====
echo -e "${GREEN}[2/7] Building & Pushing Backend Image...${NC}"
cd fargate-backend
docker build -t fargate-backend:latest .
docker tag fargate-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
cd ..
echo -e "${GREEN}✅ Backend image pushed${NC}"

# ===== Step 3: Build & Push Frontend =====
echo -e "${GREEN}[3/7] Building & Pushing Frontend Image...${NC}"
cd fargate-frontend
docker build -t fargate-frontend:latest .
docker tag fargate-frontend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
cd ..
echo -e "${GREEN}✅ Frontend image pushed${NC}"

# ===== Step 4: Update Backend Task Definition =====
echo -e "${GREEN}[4/7] Updating Backend Task Definition...${NC}"
# Replace variables in task definition JSON
envsubst < backend-task-definition.json > /tmp/backend-task-definition.json
aws ecs register-task-definition \
    --cli-input-json file:///tmp/backend-task-definition.json \
    --region $AWS_REGION > /dev/null
echo -e "${GREEN}✅ Backend task definition updated${NC}"

# ===== Step 5: Update Frontend Task Definition =====
echo -e "${GREEN}[5/7] Updating Frontend Task Definition...${NC}"
envsubst < frontend-task-definition.json > /tmp/frontend-task-definition.json
aws ecs register-task-definition \
    --cli-input-json file:///tmp/frontend-task-definition.json \
    --region $AWS_REGION > /dev/null
echo -e "${GREEN}✅ Frontend task definition updated${NC}"

# ===== Step 6: Redeploy Services =====
echo -e "${GREEN}[6/7] Redeploying ECS Services...${NC}"
aws ecs update-service \
    --cluster fargate-cluster \
    --service backend-service \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null

aws ecs update-service \
    --cluster fargate-cluster \
    --service frontend-service \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null
echo -e "${GREEN}✅ Services redeploy triggered${NC}"

# ===== Step 7: Wait & Verify =====
echo -e "${GREEN}[7/7] Waiting for deployment to stabilize (this may take 2-5 minutes)...${NC}"
aws ecs wait services-stable \
    --cluster fargate-cluster \
    --services backend-service frontend-service \
    --region $AWS_REGION

# Show results
echo -e "${YELLOW}=========================================${NC}"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e "${GREEN}🔗 Frontend: http://$ALB_DNS${NC}"
echo -e "${GREEN}🔗 Backend:  http://$ALB_DNS/api/health${NC}"
echo -e "${GREEN}🔗 API:      http://$ALB_DNS/api${NC}"
echo -e "${YELLOW}=========================================${NC}"

# Quick health check
echo -e "\n${GREEN}Running quick health check...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/api/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Backend health check passed (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${RED}⚠️  Backend health check returned HTTP $HTTP_CODE${NC}"
    echo -e "${YELLOW}Check logs: aws logs get-log-events --log-group-name /ecs/fargate-backend${NC}"
fi
SCRIPT

chmod +x fargate-deploy.sh
echo "✅ fargate-deploy.sh created and executable"
```

### 📦 Install `envsubst` (if not available)

```bash
# envsubst is part of gettext package
sudo apt install -y gettext
```

### 🏃‍♂️ Run Deploy Script

```bash
# সব variable ঠিকমতো set আছে কিনা চেক করো
source fargate.env
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "ALB DNS: $ALB_DNS"

# Full deploy!
./fargate-deploy.sh
```

---

## 13. Environment Variables & Secrets

### 🔐 AWS Secrets Manager (For Sensitive Data)

```bash
source fargate.env

# Create a secret with multiple key-value pairs
aws secretsmanager create-secret \
    --name /fargate/backend/env \
    --description "Backend environment variables" \
    --secret-string '{
        "DATABASE_URL": "mongodb://user:password@host:27017/database",
        "JWT_SECRET": "your-super-secret-jwt-key-change-this",
        "API_KEY": "your-api-key-here",
        "ENCRYPTION_KEY": "your-32-char-encryption-key"
    }' \
    --region $AWS_REGION

echo "✅ Secret created: /fargate/backend/env"

# Get Secret ARN
SECRET_ARN=$(aws secretsmanager describe-secret \
    --secret-id /fargate/backend/env \
    --query 'ARN' \
    --output text \
    --region $AWS_REGION)

echo "Secret ARN: $SECRET_ARN"
echo "SECRET_ARN=$SECRET_ARN" >> fargate.env
```

### 📝 Update Backend Task Definition with Secrets

```bash
source fargate.env

cat > backend-task-definition-with-secrets.json <<EOF
{
    "family": "fargate-backend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [
        {
            "name": "backend",
            "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest",
            "portMappings": [
                {
                    "name": "backend-5000-tcp",
                    "containerPort": 5000,
                    "hostPort": 5000,
                    "protocol": "tcp",
                    "appProtocol": "http"
                }
            ],
            "essential": true,
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "5000"
                }
            ],
            "secrets": [
                {
                    "name": "DATABASE_URL",
                    "valueFrom": "$SECRET_ARN:DATABASE_URL::"
                },
                {
                    "name": "JWT_SECRET",
                    "valueFrom": "$SECRET_ARN:JWT_SECRET::"
                },
                {
                    "name": "API_KEY",
                    "valueFrom": "$SECRET_ARN:API_KEY::"
                },
                {
                    "name": "ENCRYPTION_KEY",
                    "valueFrom": "$SECRET_ARN:ENCRYPTION_KEY::"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/fargate-backend",
                    "awslogs-region": "$AWS_REGION",
                    "awslogs-stream-prefix": "backend",
                    "awslogs-create-group": "true"
                }
            },
            "healthCheck": {
                "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            }
        }
    ]
}
EOF

echo "✅ backend-task-definition-with-secrets.json created"
```

### 🔄 Update Secret Values

```bash
# Update existing secret
aws secretsmanager put-secret-value \
    --secret-id /fargate/backend/env \
    --secret-string '{
        "DATABASE_URL": "mongodb://newuser:newpassword@newhost:27017/newdb",
        "JWT_SECRET": "new-jwt-secret",
        "API_KEY": "new-api-key",
        "ENCRYPTION_KEY": "new-encryption-key"
    }' \
    --region $AWS_REGION

echo "✅ Secret values updated"

# Force redeploy to pick up new secret values
aws ecs update-service \
    --cluster fargate-cluster \
    --service backend-service \
    --force-new-deployment \
    --region $AWS_REGION
```

---

## 14. Troubleshooting & Logs

### 📋 View CloudWatch Logs

```bash
source fargate.env

# Function to get latest logs
get_logs() {
    local SERVICE=$1
    local LOG_GROUP="/ecs/fargate-$SERVICE"
    
    # Get latest log stream
    STREAM=$(aws logs describe-log-streams \
        --log-group-name $LOG_GROUP \
        --order-by LastEventTime \
        --descending \
        --limit 1 \
        --query 'logStreams[0].logStreamName' \
        --output text \
        --region $AWS_REGION)
    
    echo "=============================================="
    echo "📋 Latest logs for: $SERVICE"
    echo "📋 Log Stream: $STREAM"
    echo "=============================================="
    
    # Get log events
    aws logs get-log-events \
        --log-group-name $LOG_GROUP \
        --log-stream-name "$STREAM" \
        --limit 20 \
        --region $AWS_REGION \
        --query 'events[*].{Time:timestamp,Message:message}' \
        --output table
}

# View backend logs
get_logs backend

# View frontend logs
get_logs frontend
```

### 🔍 Quick Debug Commands

```bash
source fargate.env

# 1. View ECS service events (last 10)
echo "=== Service Events (Backend) ==="
aws ecs describe-services \
    --cluster fargate-cluster \
    --services backend-service \
    --region $AWS_REGION \
    --query 'services[0].events[0:10]' \
    --output table

# 2. Check stopped tasks
echo -e "\n=== Stopped Tasks ==="
TASK_ARNS=$(aws ecs list-tasks \
    --cluster fargate-cluster \
    --desired-status STOPPED \
    --query 'taskArns' \
    --output text \
    --region $AWS_REGION)

if [ -n "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
    for TASK_ARN in $TASK_ARNS; do
        echo "Task: $TASK_ARN"
        aws ecs describe-tasks \
            --cluster fargate-cluster \
            --tasks $TASK_ARN \
            --region $AWS_REGION \
            --query 'tasks[0].{Reason:stoppedReason,ExitCode:containers[0].exitCode,LastStatus:lastStatus}' \
            --output table
    done
else
    echo "No stopped tasks found"
fi

# 3. Check running tasks resource usage
echo -e "\n=== Running Tasks ==="
aws ecs list-tasks \
    --cluster fargate-cluster \
    --desired-status RUNNING \
    --region $AWS_REGION \
    --query 'taskArns' \
    --output table
```

### 🛟 Common Issues & Solutions

| Problem | Likely Cause | Solution |
|:---|:---|:---|
| **Task stuck in PENDING** | No available capacity or IAM issue | Check service events: `aws ecs describe-services...` |
| **Container exits immediately** | Application crash or wrong port | View CloudWatch logs, test locally first |
| **Target Group shows unhealthy** | Health check path wrong or app not running | Curl health endpoint: `curl http://$ALB_DNS/api/health` |
| **ALB returns 503** | No healthy targets | Wait 2-5 minutes for first health check to pass |
| **ALB returns 502 Bad Gateway** | Backend container not running or port mismatch | Check if container is running, verify port 5000 |
| **Frontend can't reach Backend API** | Wrong `NEXT_PUBLIC_API_URL` | Update env var with correct ALB DNS |
| **ECR login fails** | Wrong credentials or expired token | Run `aws configure list` to verify |
| **Docker push fails with "denied"** | Wrong account ID or repo doesn't exist | `aws ecr describe-repositories` to verify |
| **"Out of memory" error** | Task definition has too little memory | Update task definition: `"memory": "1024"` |
| **Service creation fails** | Security group or subnet issue | Check VPC, subnets, security groups exist |

### 🩺 Health Check Debug

```bash
# Test health endpoint directly (if task has public IP)
# First, get task's public IP
TASK_ARN=$(aws ecs list-tasks \
    --cluster fargate-cluster \
    --service-name backend-service \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text \
    --region $AWS_REGION)

ENI_ID=$(aws ecs describe-tasks \
    --cluster fargate-cluster \
    --tasks $TASK_ARN \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text \
    --region $AWS_REGION)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
    --network-interface-ids $ENI_ID \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text \
    --region $AWS_REGION)

echo "Task Public IP: $PUBLIC_IP"
curl -v http://$PUBLIC_IP:5000/health
```

---

## 15. Cleanup & Cost Management

### 💰 AWS Fargate Pricing Breakdown

| Resource | Specification | Cost per Hour | Cost per Day | Cost per Month |
|:---|:---|:---|:---|:---|
| **vCPU** | 0.25 vCPU × 2 tasks | $0.0202 | $0.48 | ~$14.50 |
| **Memory** | 0.5 GB × 2 tasks | $0.0055 | $0.13 | ~$3.96 |
| **ALB** | 1 ALB | $0.0225 | $0.54 | ~$16.20 |
| **ECR Storage** | ~200 MB | — | — | ~$0.02 |
| **Data Transfer** | < 1 GB | — | — | ~$0.09 |
| **CloudWatch Logs** | ~100 MB | — | — | Free tier |
| **Total Estimate** | | **~$0.048/hour** | **~$1.15/day** | **~$34.77/month** |

> ⚠️ **Important:** এটা approximate cost. Actual cost কয়েক ডলার কম-বেশি হতে পারে।  
> 💡 **Practice শেষে সব delete করলে খরচ = $0!**

### 💡 Cost-Saving During Practice

```bash
source fargate.env

# ==== Services বন্ধ করো (infrastructure রেখে) ====
aws ecs update-service \
    --cluster fargate-cluster \
    --service backend-service \
    --desired-count 0 \
    --region $AWS_REGION

aws ecs update-service \
    --cluster fargate-cluster \
    --service frontend-service \
    --desired-count 0 \
    --region $AWS_REGION

echo "✅ Services scaled to 0 (ALB still running, minimal cost)"

# ==== আবার চালু করো ====
aws ecs update-service \
    --cluster fargate-cluster \
    --service backend-service \
    --desired-count 1 \
    --region $AWS_REGION

aws ecs update-service \
    --cluster fargate-cluster \
    --service frontend-service \
    --desired-count 1 \
    --region $AWS_REGION

echo "✅ Services scaled back to 1"
```

### 🗑️ Complete Cleanup Script

```bash
cat > cleanup-fargate.sh <<'SCRIPT'
#!/bin/bash
# ============================================
# Fargate Complete Cleanup Script
# Usage: ./cleanup-fargate.sh
# ⚠️ WARNING: This deletes ALL resources!
# ============================================

set -euo pipefail

if [ -f fargate.env ]; then
    source fargate.env
else
    echo "❌ fargate.env not found. Using default region us-east-1"
    AWS_REGION="us-east-1"
fi

CLUSTER="fargate-cluster"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}⚠️  WARNING: This will delete ALL Fargate resources!${NC}"
echo -e "${RED}   This action cannot be undone.${NC}"
echo ""
read -p "Are you sure? Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${YELLOW}🧹 Starting cleanup...${NC}"

# 1. Scale services to 0
echo -e "${GREEN}[1/8] Scaling services to 0...${NC}"
aws ecs update-service --cluster $CLUSTER --service backend-service --desired-count 0 --region $AWS_REGION 2>/dev/null || true
aws ecs update-service --cluster $CLUSTER --service frontend-service --desired-count 0 --region $AWS_REGION 2>/dev/null || true
echo "Waiting 20 seconds for tasks to stop..."
sleep 20

# 2. Delete ECS Services
echo -e "${GREEN}[2/8] Deleting ECS services...${NC}"
aws ecs delete-service --cluster $CLUSTER --service backend-service --force --region $AWS_REGION 2>/dev/null || true
aws ecs delete-service --cluster $CLUSTER --service frontend-service --force --region $AWS_REGION 2>/dev/null || true
echo "Waiting 15 seconds..."
sleep 15

# 3. Delete ECS Cluster
echo -e "${GREEN}[3/8] Deleting ECS cluster...${NC}"
aws ecs delete-cluster --cluster $CLUSTER --region $AWS_REGION 2>/dev/null || true

# 4. Delete ALB Listeners
echo -e "${GREEN}[4/8] Deleting ALB resources...${NC}"
ALB_ARN=$(aws elbv2 describe-load-balancers --names fargate-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
    # Delete listeners first
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[*].ListenerArn' --output text --region $AWS_REGION 2>/dev/null || echo "")
    for LISTENER in $LISTENERS; do
        if [ "$LISTENER" != "None" ] && [ -n "$LISTENER" ]; then
            aws elbv2 delete-listener --listener-arn $LISTENER --region $AWS_REGION 2>/dev/null || true
        fi
    done
    sleep 5
    
    # Delete ALB
    aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION 2>/dev/null || true
    echo "Waiting 20 seconds for ALB deletion..."
    sleep 20
fi

# 5. Delete Target Groups
echo -e "${GREEN}[5/8] Deleting Target Groups...${NC}"
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --names backend-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null || echo "skip") --region $AWS_REGION 2>/dev/null || true
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --names frontend-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null || echo "skip") --region $AWS_REGION 2>/dev/null || true

# 6. Delete ECR Repositories
echo -e "${GREEN}[6/8] Deleting ECR repositories...${NC}"
aws ecr delete-repository --repository-name fargate-backend --force --region $AWS_REGION 2>/dev/null || true
aws ecr delete-repository --repository-name fargate-frontend --force --region $AWS_REGION 2>/dev/null || true

# 7. Delete Security Groups
echo -e "${GREEN}[7/8] Deleting Security Groups...${NC}"
echo "Waiting 45 seconds for dependencies to clear..."
sleep 45
aws ec2 delete-security-group --group-name fargate-service-sg --region $AWS_REGION 2>/dev/null || true
aws ec2 delete-security-group --group-name fargate-alb-sg --region $AWS_REGION 2>/dev/null || true

# 8. Delete CloudWatch Log Groups
echo -e "${GREEN}[8/8] Deleting CloudWatch Log Groups...${NC}"
aws logs delete-log-group --log-group-name /ecs/fargate-backend --region $AWS_REGION 2>/dev/null || true
aws logs delete-log-group --log-group-name /ecs/fargate-frontend --region $AWS_REGION 2>/dev/null || true

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo -e "${GREEN}   All resources have been deleted.${NC}"
echo -e "${GREEN}   No further charges will incur.${NC}"
echo -e "${GREEN}=========================================${NC}"
SCRIPT

chmod +x cleanup-fargate.sh
echo "✅ cleanup-fargate.sh created and executable"
```

### 🏃‍♂️ Run Cleanup

```bash
# সম্পূর্ণ cleanup
./cleanup-fargate.sh

# Confirmation message এ টাইপ করবে: DELETE
```

### 📊 Set Budget Alert (Recommended)

```
AWS Console → Billing and Cost Management → Budgets → Create Budget
  Budget type: Cost budget
  Period: Monthly
  Budget amount: $10.00
  Alert threshold: 80% ($8.00)
  Email: your-email@example.com
```

---

## 📊 Complete Architecture Diagram

```
                            🌐 INTERNET
                                │
                                ▼
                      ┌──────────────────┐
                      │   Route 53       │ (Optional - for custom domain)
                      │   DNS            │
                      └────────┬─────────┘
                               │
                               ▼
                      ┌──────────────────┐
                      │  ALB (HTTP:80)   │
                      │  fargate-alb     │
                      │  Security Group  │
                      │  (Public Access) │
                      └────┬────────┬────┘
                           │        │
               /* ─────────┘        └──────── /api/*
                           │                    │
                           ▼                    ▼
                  ┌──────────────┐    ┌──────────────┐
                  │ Frontend TG  │    │ Backend TG   │
                  │ Port 3000    │    │ Port 5000    │
                  │ Health: /health   │ Health: /health │
                  └──────┬───────┘    └──────┬───────┘
                         │                   │
                         ▼                   ▼
                  ┌──────────────┐    ┌──────────────┐
                  │ Fargate      │    │ Fargate      │
                  │ Frontend     │    │ Backend      │
                  │ 0.25 vCPU    │    │ 0.25 vCPU    │
                  │ 0.5 GB RAM   │    │ 0.5 GB RAM   │
                  │ Next.js      │    │ Express+TS   │
                  └──────┬───────┘    └──────┬───────┘
                         │                   │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │     ECR           │
                         │  Container Images  │
                         │  fargate-backend   │
                         │  fargate-frontend  │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │   CloudWatch      │
                         │   Logs & Metrics  │
                         │   /ecs/fargate-*  │
                         └───────────────────┘
                                   │
                         ┌─────────▼─────────┐
                         │  Secrets Manager  │
                         │  /fargate/backend/env │
                         │  (DB URL, JWT,   │
                         │   API Keys etc.) │
                         └───────────────────┘
```

---

## 🎯 Complete Practice Workflow

| Step | Section | What You Do | Time |
|:---|:---|:---|:---|
| 1 | 1 | GitHub এ 2টা repo বানিয়ে clone করো | 5 min |
| 2 | 2 | AWS account + IAM User create করো | 10 min |
| 3 | 3 | AWS CLI install + configure করো | 5 min |
| 4 | 4 | Docker install + verify করো | 5 min |
| 5 | 5 | Frontend Dockerfile লিখে test করো | 10 min |
| 6 | 6 | Backend Dockerfile লিখে test করো | 10 min |
| 7 | 7 | ECR repos create করে image push করো | 10 min |
| 8 | 8 | ECS cluster + Security Groups create | 5 min |
| 9 | 9 | Task Definitions create + register | 10 min |
| 10 | 10 | ALB + Target Groups + Routing setup | 10 min |
| 11 | 11 | ECS Services create + test করো | 10 min |
| 12 | 12 | Deploy script বানাও (optional) | 5 min |
| 13 | 13 | Secrets Manager setup (optional) | 5 min |
| 14 | 14 | Troubleshooting — ভুল হলে debug | Varies |
| 15 | 15 | Cleanup — সব delete করে দাও | 5 min |
| **Total** | | | **~80-100 min** |

---

## 📝 All Commands Quick Reference

```bash
# ===== Essential Commands =====

# Load environment
source fargate.env

# Check AWS identity
aws sts get-caller-identity

# List ECR repos
aws ecr describe-repositories --region $AWS_REGION

# List ECS clusters
aws ecs list-clusters --region $AWS_REGION

# Check services status
aws ecs describe-services --cluster fargate-cluster --services backend-service frontend-service --region $AWS_REGION --query 'services[*].{Name:serviceName,Status:status,Running:runningCount}'

# View running tasks
aws ecs list-tasks --cluster fargate-cluster --desired-status RUNNING --region $AWS_REGION

# Get ALB DNS
aws elbv2 describe-load-balancers --names fargate-alb --query 'LoadBalancers[0].DNSName' --output text --region $AWS_REGION

# Scale service down
aws ecs update-service --cluster fargate-cluster --service backend-service --desired-count 0 --region $AWS_REGION

# Scale service up
aws ecs update-service --cluster fargate-cluster --service backend-service --desired-count 1 --region $AWS_REGION

# Force redeploy
aws ecs update-service --cluster fargate-cluster --service backend-service --force-new-deployment --region $AWS_REGION
```

---

## 🎓 What You Learned

| Concept | Hands-on Experience |
|:---|:---|
| **Docker** | Multi-stage builds, .dockerignore, health checks |
| **ECR** | Private container registry, image scanning |
| **ECS Fargate** | Serverless containers, task definitions, services |
| **ALB** | Layer 7 load balancing, path-based routing |
| **Security Groups** | Network security, least privilege access |
| **IAM** | Roles, policies, task execution roles |
| **CloudWatch** | Centralized logging, log groups & streams |
| **Secrets Manager** | Secure environment variable management |
| **Infrastructure as Code** | AWS CLI scripting, automation |
| **Cost Management** | Fargate pricing, cleanup strategies |

---

> 💡 **Pro Tips:**
> - প্রথমবার সব ঠিকমতো না হলে `cleanup-fargate.sh` চালিয়ে আবার শুরু করো
> - সব variable (`AWS_ACCOUNT_ID`, `ALB_DNS`, SG IDs) একটা notepad-এ note করে রাখো
> - প্রতিটা section শেষে verify করে নাও — পরে troubleshoot করা কঠিন হবে
> - Practice শেষে cleanup করতে ভুলবে না! নাহলে credit card-এ চার্জ আসবে
> - `docker logs` locally test করে নাও — Fargate-তে deploy করার আগেই বাগ ধরা পড়বে

---

**© 2026 Arman Mia. All rights reserved.**  
**Happy Learning! 🚀**