# 🐳 Docker + AWS ECR + ECS Fargate + Load Balancer Complete Deployment Guide

> **Author:** Arman Mia  
> **Last Updated:** 08 June 2026  
> **Stack:** Docker, AWS ECR, ECS Fargate, ALB, Node.js (Frontend + Backend)

---

## 📑 Table of Contents

1. [Project Structure & Starter Repos](#1-project-structure--starter-repos)
2. [AWS Account Setup & IAM User Creation](#2-aws-account-setup--iam-user-creation)
3. [AWS CLI Setup](#3-aws-cli-setup)
4. [Docker Setup](#4-docker-setup)
5. [Frontend Docker Setup](#5-frontend-docker-setup)
6. [Backend Docker Setup](#6-backend-docker-setup)
7. [ECR Repository Create & Push](#7-ecr-repository-create--push)
8. [ECS Fargate Cluster Setup](#8-ecs-fargate-cluster-setup)
9. [Task Definitions](#9-task-definitions)
10. [Application Load Balancer Setup](#10-application-load-balancer-setup)
11. [ECS Services Create](#11-ecs-services-create)
12. [Deploy Automation Script](#12-deploy-automation-script)
13. [Environment Variables & Secrets](#13-environment-variables--secrets)
14. [Troubleshooting & Logs](#14-troubleshooting--logs)
15. [Cleanup & Cost Management](#15-cleanup--cost-management)
16. [Custom Domain + HTTPS Setup](#16-custom-domain--https-setup)
17. [Quick Reference Cheat Sheet](#17-quick-reference-cheat-sheet)

---

## 1. Project Structure & Starter Repos

### 📁 Frontend Repo: `fargate-frontend`
```
fargate-frontend/
├── Dockerfile
├── .dockerignore
├── .env.production
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
└── src/
    ├── index.ts
    └── routes/
```

### 🎯 Starter Repo Create

```bash
# Frontend
git clone git@github.com:your-username/fargate-frontend.git
cd fargate-frontend
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir

# Backend
cd ..
git clone git@github.com:your-username/fargate-backend.git
cd fargate-backend
npm init -y
npm install express cors dotenv
npm install -D typescript @types/express @types/node ts-node nodemon
npx tsc --init
```

> 💡 **কেন আলাদা repo?** Frontend/backend স্বাধীনভাবে deploy করা যায়। একটা crash করলে আরেকটা unaffected থাকে।

---

## 2. AWS Account Setup & IAM User Creation

### 🔐 AWS Free Tier Account

1. Go to [aws.amazon.com](https://aws.amazon.com) → Sign Up
2. Email, Password, Account Name
3. Credit Card ($1 temp charge, refunded)
4. Phone Verify with OTP
5. Support Plan: **Basic - Free**

### 👤 IAM User Create

> ⚠️ **Never use Root User! Always IAM User!**

> 💡 **কেন IAM User?** Root user-এর unlimited power। ভুলবশত delete করলে পুরা AWS account চলে যেতে পারে! IAM user-এ specific permissions দিয়ে risk কমানো যায়।

**Console Path:**
```
AWS Console → IAM → Users → Create User
  User name: fargate-deployer
  ☑️ Provide user access to AWS Management Console

Permissions (Attach policies directly):
  ☑️ AmazonEC2ContainerRegistryFullAccess     (ECR push/pull)
  ☑️ AmazonECS_FullAccess                     (ECS manage)
  ☑️ AmazonEC2FullAccess                      (Security Groups, ALB)
  ☑️ CloudWatchLogsFullAccess                 (Logs debug)
  ☑️ IAMFullAccess                            (Role creation)
  ☑️ Route53FullAccess                        (Domain - optional)
  ☑️ AWSCertificateManagerFullAccess          (SSL - optional)

→ Create User
→ Security credentials → Create access key
→ CLI → Create
→ ⚠️ Download .csv file (KEEP SAFE!)
```

---

## 3. AWS CLI Setup

### 📦 Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip -y
unzip awscliv2.zip
sudo ./aws/install
aws --version
rm -rf aws awscliv2.zip
```

### ⚙️ Configure

```bash
aws configure
# Access Key ID: AKIAXXXXXXXXXXXXXXXX (from CSV)
# Secret Access Key: xxxxxxxxxxxxxxxxxxxxxxxx (from CSV)
# Region: us-east-1
# Output: json

aws sts get-caller-identity
```

### 📝 Set Variables

```bash
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > fargate.env <<EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
EOF
```

### 🌍 Region Guide

| Region | Code | Latency (BD) | Price |
|:---|:---|:---|:---|
| N. Virginia | `us-east-1` | ~250ms | 💰 Cheapest |
| Singapore | `ap-southeast-1` | ~80ms | 💰💰💰 |
| Mumbai | `ap-south-1` | ~60ms | 💰💰💰 |

> 💡 Practice-এর জন্য `us-east-1` use করো — Free tier benefit সবচেয়ে বেশি!

---

## 4. Docker Setup

### 🐳 Install Docker Engine

```bash
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker

docker --version
docker run hello-world
```

---

## 5. Frontend Docker Setup

### 📄 `next.config.js`

> 💡 **কেন `output: 'standalone'`?** Next.js-এর সব dependencies এক folder-এ bundle করে। Docker multi-stage build-এ শুধু এই folder copy করলেই চলে, পুরা `node_modules` copy করতে হয় না — image size কমে।

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
}
module.exports = nextConfig
```

### 📄 `src/app/health/route.ts` (Health Check Endpoint)

> 💡 **কেন `/health` endpoint?** ALB health check-এর জন্য dedicated endpoint। `/` (homepage) full HTML return করে (11KB+), `/health` ছোট JSON return করে (fast!)। ALB timeout 5-10 সেকেন্ড, `/health` দ্রুত response দিয়ে health check পাস করে।

```typescript
export async function GET() {
  return Response.json({ 
    status: 'ok', 
    service: 'frontend',
    timestamp: new Date().toISOString() 
  });
}
```

### 📄 `.env.production`

```env
NEXT_PUBLIC_BASE_URL=http://YOUR_ALB_DNS/api/v1
```

### 📄 `Dockerfile` (Next.js — Multi-stage)

```dockerfile
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
ARG NEXT_PUBLIC_BASE_URL=http://localhost:3000/api/v1
ENV NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL
RUN npm run build

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

> 💡 **কেন ARG + ENV আলাদা?** `ARG` = build-time variable (Docker build-এর সময় Next.js compile করে, তখন URL inject হয়)। `ENV` = runtime variable (container চলার সময়ও দরকার)। ARG ছাড়া ENV দিলে build-এই inject হবে না!

### 📄 `.dockerignore`

```
node_modules
.next
.git
.env
.env.local
Dockerfile
.dockerignore
npm-debug.log*
```

### 🔨 Build & Test Locally

```bash
cd fargate-frontend
docker build -t fargate-frontend:latest .
docker run -d -p 3000:3000 --name frontend-test fargate-frontend:latest
curl http://localhost:3000/health
curl http://localhost:3000
docker logs frontend-test
docker stop frontend-test && docker rm frontend-test
```

---

## 6. Backend Docker Setup

### 📄 `src/index.ts` (Express Server)

```typescript
import express, { Request, Response } from 'express';
import cors from 'cors';

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// ⚠️ ALB Health Check - REQUIRED!
app.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'ok',
    service: 'backend',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/api', (req: Request, res: Response) => {
  res.json({ message: 'Hello from Backend!', version: '1.0.0' });
});

app.listen(PORT, () => {
  console.log(`🚀 Backend running on port ${PORT}`);
});
```

> 💡 **কেন backend-এই `/health` জরুরি?** ALB জানে না container ঠিকমতো কাজ করছে কিনা। `/health` endpoint-এ hit করে HTTP 200 পেলে বুঝে container OK। না থাকলে container চললেও ALB unhealthy দেখাবে → 503 error!

### 📄 `Dockerfile` (Express + TypeScript)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

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

> 💡 **কেন `USER appuser` (non-root)?** Docker container default root user-এ চলে। হ্যাক হলে attacker root access পেয়ে যায়! `appuser` non-root user — security best practice।

### 📄 `.dockerignore`

```
node_modules
dist
.git
.env
Dockerfile
.dockerignore
```

### 🔨 Build & Test Locally

```bash
cd fargate-backend
docker build -t fargate-backend:latest .
docker run -d -p 5000:5000 --name backend-test fargate-backend:latest
curl http://localhost:5000/health
curl http://localhost:5000/api
docker stop backend-test && docker rm backend-test
```

---

## 7. ECR Repository Create & Push

### 📦 Create ECR Repositories

**Console Path:**
```
AWS Console → ECR → Repositories → Create repository
  Repository name: fargate-backend → Create
  Repository name: fargate-frontend → Create
```

**CLI:**
```bash
source fargate.env

aws ecr create-repository --repository-name fargate-backend --region $AWS_REGION
aws ecr create-repository --repository-name fargate-frontend --region $AWS_REGION

aws ecr describe-repositories --region $AWS_REGION
```

### 🔐 Login & Push Backend

```bash
source fargate.env

# Login
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build & Push Backend
cd fargate-backend
docker build -t fargate-backend:latest .
docker tag fargate-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
cd ..
```

### 🔐 Push Frontend

```bash
cd fargate-frontend
docker build -t fargate-frontend:latest .
docker tag fargate-frontend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
cd ..
```

---

## 8. ECS Fargate Cluster Setup

### 🏗️ Create ECS Cluster

**Console Path:**
```
AWS Console → ECS → Clusters → Create Cluster
  Cluster name: fargate-cluster
  Infrastructure: AWS Fargate (serverless)
→ Create
```

**CLI:**
```bash
source fargate.env

aws ecs create-cluster \
  --cluster-name fargate-cluster \
  --region $AWS_REGION \
  --capacity-providers FARGATE
```

### 🔐 Create Security Groups

**Console Path:**
```
EC2 → Security Groups → Create security group

1. ALB Security Group (alb-sg):
   Name: alb-sg
   Inbound: HTTP:80 from 0.0.0.0/0
   
2. Service Security Group (service-sg):
   Name: service-sg
   Inbound: TCP:3000 from alb-sg
   Inbound: TCP:5000 from alb-sg
```

> 💡 **কেন ২টা আলাদা Security Group?** `alb-sg` = Public-facing, internet থেকে HTTP:80 allow করে। `service-sg` = Internal, শুধু ALB থেকে traffic allow করে। Container-এ সরাসরি internet access দিলে hacker সরাসরি attack করতে পারবে!

> 💡 **কেন port 3000 + 5000?** Frontend 3000-এ চলে, Backend 5000-এ। এই ports open না করলে ALB container-এ traffic পাঠাতে পারবে না → 502 error!

**CLI:**
```bash
source fargate.env

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

# ALB Security Group
ALB_SG_ID=$(aws ec2 create-security-group --group-name alb-sg --description "ALB SG" --vpc-id $VPC_ID --region $AWS_REGION --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $AWS_REGION

# Service Security Group
SERVICE_SG_ID=$(aws ec2 create-security-group --group-name service-sg --description "Service SG" --vpc-id $VPC_ID --region $AWS_REGION --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SERVICE_SG_ID --protocol tcp --port 3000 --source-group $ALB_SG_ID --region $AWS_REGION
aws ec2 authorize-security-group-ingress --group-id $SERVICE_SG_ID --protocol tcp --port 5000 --source-group $ALB_SG_ID --region $AWS_REGION

echo "VPC_ID=$VPC_ID" >> fargate.env
echo "ALB_SG_ID=$ALB_SG_ID" >> fargate.env
echo "SERVICE_SG_ID=$SERVICE_SG_ID" >> fargate.env
```

---

## 9. Task Definitions

### 📋 Create IAM Task Execution Role

> 💡 **কেন এই role দরকার?** ECS task-এর AWS services access করতে role লাগে — ECR থেকে image pull, CloudWatch-এ logs write, Secrets Manager থেকে secret পড়া। Role ছাড়া এসব কাজ fail করবে!

**Console Path:**
```
IAM → Roles → Create Role
  Service: ECS Tasks
  Policy: AmazonECSTaskExecutionRolePolicy
  Role name: ecsTaskExecutionRole
→ Create
```

**CLI:**
```bash
aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --region $AWS_REGION

aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy --region $AWS_REGION
```

### 📄 Backend Task Definition

**Console Path:**
```
ECS → Task Definitions → Create new task definition
  Name: fargate-backend-task
  Launch type: Fargate
  CPU: 0.25 vCPU, Memory: 0.5 GB
  Task role: ecsTaskExecutionRole
  
  Container:
    Name: backend
    Image: <ECR_URI>/fargate-backend:latest
    Port: 5000
    Health check:
      Command: CMD-SHELL, curl -f http://localhost:5000/health || exit 1
      Start period: 60s
      Interval: 30s
      Retries: 3
    Environment:
      NODE_ENV=production
      PORT=5000
    Logging: awslogs, /ecs/fargate-backend
```

> 💡 **কেন `|| exit 1`?** `curl -f` fail করলে exit code 22 দেয়, কিন্তু container health check exit code 0 (success) বা 1 (failure) চায়। `|| exit 1` নিশ্চিত করে fail-এ exit 1 হয় — ECS বুঝতে পারে container unhealthy।

> 💡 **কেন startPeriod: 60?** Container start-এর প্রথম ৬০ সেকেন্ড health check হয় না। Server start হতে সময় নেয়। এই breathing time না দিলে server ready হতেই health check fail → container kill → restart loop!

**CLI:**
```bash
source fargate.env

cat > backend-task.json <<EOF
{
    "family": "fargate-backend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [{
        "name": "backend",
        "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest",
        "portMappings": [{"containerPort": 5000, "protocol": "tcp"}],
        "essential": true,
        "environment": [
            {"name": "NODE_ENV", "value": "production"},
            {"name": "PORT", "value": "5000"}
        ],
        "healthCheck": {
            "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
            "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60
        },
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/fargate-backend",
                "awslogs-region": "$AWS_REGION",
                "awslogs-stream-prefix": "backend",
                "awslogs-create-group": "true"
            }
        }
    }]
}
EOF

aws ecs register-task-definition --cli-input-json file://backend-task.json --region $AWS_REGION
```

### 📄 Frontend Task Definition

**Console Path:**
```
ECS → Task Definitions → Create new task definition
  Name: fargate-frontend-task
  CPU: 0.25 vCPU, Memory: 0.5 GB
  
  Container:
    Name: frontend
    Image: <ECR_URI>/fargate-frontend:latest
    Port: 3000
    Environment:
      NODE_ENV=production
      PORT=3000
      NEXT_PUBLIC_BASE_URL=http://ALB_DNS/api/v1 (⚠️ Update after ALB created!)
    Logging: awslogs, /ecs/fargate-frontend
```

**CLI:**
```bash
source fargate.env

cat > frontend-task.json <<EOF
{
    "family": "fargate-frontend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256",
    "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [{
        "name": "frontend",
        "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest",
        "portMappings": [{"containerPort": 3000, "protocol": "tcp"}],
        "essential": true,
        "environment": [
            {"name": "NODE_ENV", "value": "production"},
            {"name": "PORT", "value": "3000"},
            {"name": "NEXT_PUBLIC_BASE_URL", "value": "http://PLACEHOLDER/api/v1"}
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
    }]
}
EOF

aws ecs register-task-definition --cli-input-json file://frontend-task.json --region $AWS_REGION
```

> ⚠️ `NEXT_PUBLIC_BASE_URL` placeholder update হবে ALB DNS পাওয়ার পর!

---

## 10. Application Load Balancer Setup

### ⚖️ Why ALB?

> 💡 **কেন ALB?** Frontend (port 3000) + Backend (port 5000) — user-কে ২টা URL দিতে চাই না! ALB path-based routing করে `/api/*` backend-এ, বাকি frontend-এ পাঠায়। Single URL-এ পুরা app!

### Routing Flow

```
Browser → ALB (HTTP:80)
           ├── /api/auth/* → backend-tg (5000)
           ├── /api/*      → backend-tg (5000)
           └── /* (Default) → frontend-tg (3000)
```

---

### 🖥️ CONSOLE STEPS (Do This First!)

**Step 1: Create Target Groups**

```
EC2 → Target Groups → Create target group

Backend TG:
  Target type: IP addresses (⚠️ Fargate needs IP!)
  Name: backend-tg
  Port: 5000
  Health check path: /health
  Interval: 60s, Timeout: 10s
  Healthy: 2, Unhealthy: 10
  Success codes: 200
→ Create

Frontend TG:
  Target type: IP addresses
  Name: frontend-tg
  Port: 3000
  Health check path: /health
  Interval: 60s, Timeout: 10s
  Healthy: 2, Unhealthy: 10
  Success codes: 200,304 (⚠️ 304 for Next.js!)
→ Create
```

> 💡 **কেন Target Type "IP"?** Fargate serverless — কোনো EC2 instance নেই! Container-দের private IP address থাকে। ALB সরাসরি IP-তে route করে। "Instance" type EC2-এর জন্য, Fargate-এ কাজ করবে না!

> 💡 **কেন Interval 60s, Unhealthy 10?** 60s interval = প্রতি মিনিটে check, container-কে বাড়তি load দেয় না। 10 unhealthy = ১০ মিনিট পর্যন্ত unhealthy সহ্য করে। Next.js cold start হতে ৬০-৯০ সেকেন্ড লাগে। 30s + 2 threshold দিলে ১ মিনিটে fail → kill → restart loop!

> 💡 **কেন Success Codes 200,304?** Next.js cached static pages-এ HTTP 304 (Not Modified) return করে। ALB default-এ 200 ছাড়া সব fail ধরে! 304 add না করলে cached page hit হলেই health check fail → container unhealthy!

**Step 2: Create ALB**

```
EC2 → Load Balancers → Create → Application Load Balancer
  Name: fargate-alb
  Scheme: Internet-facing
  Subnets: Select 2-3 (different AZs)
  Security group: alb-sg
  Listener HTTP:80 → Default: frontend-tg
→ Create
```

**Step 3: Add /api/* Rules**

```
ALB → Listeners → HTTP:80 → Rules → Add rule

Rule 1 (Priority 5):
  IF: Path = /api/auth/*
  THEN: Forward to backend-tg

Rule 2 (Priority 10):
  IF: Path = /api/*
  THEN: Forward to backend-tg

Default: Forward to frontend-tg
```

> 💡 **কেন `/api/auth/*` আলাদা rule (Priority 5)?** Auth routes (login, register) sensitive! Priority 5 দিলে সব API call-এর আগে match করে। আলাদা rule-এ logging, rate limiting add করা যায় পরে। Priority কম (5 < 10) = আগে evaluate হবে!

---

### 💻 CLI STEPS

```bash
source fargate.env

# Get Subnets
SUBNET_1=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION)
SUBNET_2=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[1].SubnetId' --output text --region $AWS_REGION)

# Create Target Groups
BACKEND_TG_ARN=$(aws elbv2 create-target-group \
  --name backend-tg --protocol HTTP --port 5000 --vpc-id $VPC_ID --target-type ip \
  --health-check-path /health --health-check-interval-seconds 60 \
  --health-check-timeout-seconds 10 --healthy-threshold-count 2 \
  --unhealthy-threshold-count 10 --region $AWS_REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

FRONTEND_TG_ARN=$(aws elbv2 create-target-group \
  --name frontend-tg --protocol HTTP --port 3000 --vpc-id $VPC_ID --target-type ip \
  --health-check-path /health --health-check-interval-seconds 60 \
  --health-check-timeout-seconds 10 --healthy-threshold-count 2 \
  --unhealthy-threshold-count 10 --region $AWS_REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# ⚠️ ADD 304 for Next.js!
aws elbv2 modify-target-group --target-group-arn $FRONTEND_TG_ARN --matcher HttpCode=200,304 --region $AWS_REGION

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer --name fargate-alb --subnets $SUBNET_1 $SUBNET_2 \
  --security-groups $ALB_SG_ID --scheme internet-facing --type application \
  --region $AWS_REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text --region $AWS_REGION)

echo "🔗 ALB DNS: $ALB_DNS"
echo "ALB_DNS=$ALB_DNS" >> fargate.env

# Create Listener
aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$FRONTEND_TG_ARN --region $AWS_REGION

LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN \
  --query 'Listeners[0].ListenerArn' --output text --region $AWS_REGION)

# Rules
aws elbv2 create-rule --listener-arn $LISTENER_ARN --priority 5 \
  --conditions Field=path-pattern,Values='/api/auth/*' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN --region $AWS_REGION

aws elbv2 create-rule --listener-arn $LISTENER_ARN --priority 10 \
  --conditions Field=path-pattern,Values='/api/*' \
  --actions Type=forward,TargetGroupArn=$BACKEND_TG_ARN --region $AWS_REGION

echo "✅ ALB Setup Complete!"
```

---

## 11. ECS Services Create

### 🔧 Why These Settings?

| Setting | Value | Why |
|:---|:---|:---|
| Grace period | 120s | Next.js start-এ 60-90s লাগে |
| Circuit breaker | OFF | Practice-তে rollback loop এড়াতে |
| Public IP | ENABLED | Container সরাসরি debug করতে |
| Desired count | 1 | Practice-তে খরচ বাঁচাতে |

> 💡 **কেন Circuit Breaker OFF?** Production-এ ON রাখবে! Practice-তে ভুল হলে rollback করে deploy fail দেখায় — debug করা কঠিন। OFF থাকলে task fail হলেও service running থাকে, logs দেখে debug করা যায়।

> 💡 **কেন Grace Period 120s?** Container start → ECS task RUNNING → কিন্তু Next.js এখনো compile হচ্ছে! Grace period 0 থাকলে ALB সাথে সাথে health check শুরু করে → `/health` 404 → unhealthy → kill → restart → infinite loop!

---

### 🖥️ CONSOLE STEPS

**Step 1: Create Backend Service**
```
ECS → Clusters → fargate-cluster → Services → Create
  Launch type: Fargate
  Task definition: fargate-backend-task
  Service name: backend-service
  Desired tasks: 1
  
  Deployment:
    ☑️ Force new deployment
    Circuit breaker: ❌ OFF
    Grace period: 120 seconds

  Networking:
    VPC: Default
    Subnets: 2-3 select
    Security group: service-sg
    ☑️ Public IP: ENABLED

  Load balancing:
    ☑️ Use load balancing
    ALB: fargate-alb
    Container: backend:5000
    ⚠️ Target group: backend-tg (NOT frontend-tg!)

→ Create
```

> 💡 **কেন Target Group সঠিক করা জরুরি?** Backend container-এ frontend-tg attach করলে health check port 3000-এ check করবে! কিন্তু backend চলছে port 5000-এ → health check fail → container kill! (এটা তোমার সাথে হয়েছিল!)

**Step 2: Create Frontend Service**
```
Same as backend but:
  Task definition: fargate-frontend-task
  Service name: frontend-service
  Container: frontend:3000
  ⚠️ Target group: frontend-tg
→ Create
```

**Step 3: Wait & Verify**
```
Events tab → "service has reached a steady state"
Tasks tab → Health: Healthy ✅
Health tab → 1 Healthy, 0 Unhealthy ✅
```

**Step 4: Test**
```
Browser: http://ALB_DNS/register
Terminal: curl http://ALB_DNS/api/v1/health
```

---

### 💻 CLI STEPS

```bash
source fargate.env

# Create Backend Service
aws ecs create-service \
  --cluster fargate-cluster \
  --service-name backend-service \
  --task-definition fargate-backend-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --health-check-grace-period-seconds 120 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SERVICE_SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$BACKEND_TG_ARN,containerName=backend,containerPort=5000" \
  --deployment-configuration "deploymentCircuitBreaker={enable=false,rollback=false}" \
  --region $AWS_REGION

# Create Frontend Service
aws ecs create-service \
  --cluster fargate-cluster \
  --service-name frontend-service \
  --task-definition fargate-frontend-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --health-check-grace-period-seconds 120 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SERVICE_SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$FRONTEND_TG_ARN,containerName=frontend,containerPort=3000" \
  --deployment-configuration "deploymentCircuitBreaker={enable=false,rollback=false}" \
  --region $AWS_REGION

echo "✅ Services created! Wait 5 minutes..."

# Check status
aws ecs describe-services --cluster fargate-cluster \
  --services backend-service frontend-service --region $AWS_REGION \
  --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount}' --output table
```

### 🔄 Update Frontend API URL (After ALB Created)

```bash
source fargate.env

# Update task definition with real ALB DNS
cat > frontend-task.json <<EOF
{
    "family": "fargate-frontend-task",
    "networkMode": "awsvpc",
    "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
    "cpu": "256", "memory": "512",
    "requiresCompatibilities": ["FARGATE"],
    "containerDefinitions": [{
        "name": "frontend",
        "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest",
        "portMappings": [{"containerPort": 3000, "protocol": "tcp"}],
        "essential": true,
        "environment": [
            {"name": "NODE_ENV", "value": "production"},
            {"name": "PORT", "value": "3000"},
            {"name": "NEXT_PUBLIC_BASE_URL", "value": "http://$ALB_DNS/api/v1"}
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/fargate-frontend",
                "awslogs-region": "$AWS_REGION",
                "awslogs-stream-prefix": "frontend"
            }
        }
    }]
}
EOF

aws ecs register-task-definition --cli-input-json file://frontend-task.json --region $AWS_REGION
aws ecs update-service --cluster fargate-cluster --service frontend-service --force-new-deployment --region $AWS_REGION
```

---

## 12. Deploy Automation Script

```bash
cat > deploy.sh << 'SCRIPT'
#!/bin/bash
set -e
source fargate.env

echo "🚀 Building & Pushing Backend..."
cd fargate-backend
docker build -t fargate-backend:latest .
docker tag fargate-backend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-backend:latest
cd ..

echo "🚀 Building & Pushing Frontend..."
cd fargate-frontend
docker build --build-arg NEXT_PUBLIC_BASE_URL=http://$ALB_DNS/api/v1 -t fargate-frontend:latest .
docker tag fargate-frontend:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fargate-frontend:latest
cd ..

echo "🔄 Redeploying Services..."
aws ecs update-service --cluster fargate-cluster --service backend-service --force-new-deployment --region $AWS_REGION
aws ecs update-service --cluster fargate-cluster --service frontend-service --force-new-deployment --region $AWS_REGION

echo "✅ Deploy Complete! URL: http://$ALB_DNS"
SCRIPT

chmod +x deploy.sh
```

---

## 13. Environment Variables & Secrets

### 🔐 AWS Secrets Manager (Sensitive Data)

> 💡 **কেন Secrets Manager?** Database URL, JWT Secret — এগুলো Dockerfile বা task definition-এ সরাসরি লিখলে security risk! Secrets Manager encrypt করে store করে, IAM permission দিয়ে access control করা যায়।

**Console Path:**
```
AWS Secrets Manager → Store a new secret
  Secret type: Other type of secret
  Key/value pairs:
    DATABASE_URL: mongodb+srv://...
    JWT_SECRET: your-jwt-secret
    API_KEY: your-api-key
  Secret name: /fargate/backend/env
→ Store
```

**CLI:**
```bash
source fargate.env

aws secretsmanager create-secret \
  --name /fargate/backend/env \
  --secret-string '{"DATABASE_URL":"mongodb://...","JWT_SECRET":"secret123","API_KEY":"key456"}' \
  --region $AWS_REGION

SECRET_ARN=$(aws secretsmanager describe-secret --secret-id /fargate/backend/env --query ARN --output text --region $AWS_REGION)
```

**Use in Task Definition:**
```json
"secrets": [
  {"name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:secret:/fargate/backend/env:DATABASE_URL::"},
  {"name": "JWT_SECRET", "valueFrom": "arn:aws:secretsmanager:...:secret:/fargate/backend/env:JWT_SECRET::"}
]
```

---

## 14. Troubleshooting & Logs

### 🔍 View Logs

**Console:**
```
CloudWatch → Log groups → /ecs/fargate-frontend → Latest stream
CloudWatch → Log groups → /ecs/fargate-backend → Latest stream
```

**CLI:**
```bash
aws logs tail /ecs/fargate-frontend --follow --region us-east-1
aws logs tail /ecs/fargate-backend --follow --region us-east-1
```

---

### 🚨 #1: Health Check Failures (Tasks Keep Dying!)

**Symptom:** Events show "Task failed container health checks", tasks restart every 2-3 min

**Root Cause Checklist (Check ALL 5):**

1. ❌ **Health Check Path Wrong**
   - `EC2 → Target Groups → frontend-tg → Health checks`
   - Path MUST be: `/health` (NOT `/`)
   - If using `/`, add `200,304` in success codes

2. ❌ **Grace Period = 0**
   - `ECS → frontend-service → Update Service`
   - Health check grace period: **120 seconds**

3. ❌ **Circuit Breaker ON**
   - `ECS → frontend-service → Update Service`
   - Deployment circuit breaker: **OFF**

4. ❌ **Wrong Target Group**
   - `ECS → backend-service → Health tab`
   - Backend MUST use: `backend-tg` (NOT frontend-tg!)

5. ❌ **Next.js 304 Not Accepted**
   - `EC2 → Target Groups → frontend-tg → Edit`
   - Success codes: **200,304**

> 💡 **কেন বারবার fail হয়?** ৫টা কারণে হতে পারে। সবচেয়ে common: Target Group path `/health` না দিয়ে `/` দিলে Next.js পুরা HTML return করে — slow, timeout! আর grace period 0 থাকলে container ready হতেই health check fail করে!

**Full Fix (Console):**
```
1. Target Groups → frontend-tg → Edit:
   Path: /health
   Interval: 60s
   Unhealthy: 10
   Success codes: 200,304
   → Save

2. ECS → frontend-service → Update:
   Grace period: 120
   Circuit breaker: OFF
   Force new deployment: YES
   → Update

3. WAIT 5 MINUTES - Do NOT touch!
```

---

### 🚨 #2: Frontend Shows localhost:5000

**Symptom:** Network tab shows `POST http://localhost:5000/api/v1/auth/login`

**Root Cause:** Environment variable not reaching Next.js

**Fix Checklist:**
1. Check `Dockerfile` for `ENV NEXT_PUBLIC_BASE_URL=http://localhost:5000` → Change to ALB URL
2. Create `.env.production`: `NEXT_PUBLIC_BASE_URL=http://ALB_DNS/api/v1`
3. Update Task Definition environment variable
4. Rebuild + Push + Force deploy

---

### 🚨 #3: Backend Uses Wrong Target Group

**Symptom:** Events show "deregistered 1 targets in target-group frontend-tg" for backend!

**Fix:**
```
ECS → backend-service → Update Service
→ Load balancing: REMOVE → ADD new (backend:5000 → backend-tg)
→ Force new deployment
→ Update
```

---

### 🛟 Quick Debug

```bash
# Service events
aws ecs describe-services --cluster fargate-cluster --services frontend-service \
  --query 'services[0].events[:5]' --output table --region us-east-1

# Target health
aws elbv2 describe-target-health --target-group-arn $FRONTEND_TG_ARN --region us-east-1

# Direct container test
TASK_ARN=$(aws ecs list-tasks --cluster fargate-cluster --service-name frontend-service \
  --query 'taskArns[0]' --output text --region us-east-1)
ENI_ID=$(aws ecs describe-tasks --cluster fargate-cluster --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text --region us-east-1)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text --region us-east-1)
curl -I http://$PUBLIC_IP:3000/health
```

### Common Issues Table

| Problem | Cause | Solution |
|:---|:---|:---|
| 503 Service Unavailable | No healthy targets | Wait 5 min for health check |
| 502 Bad Gateway | Backend not running | Check backend logs |
| Task PENDING | Capacity or IAM | Check service events |
| localhost:5000 in browser | Wrong env variable | Fix NEXT_PUBLIC_BASE_URL |
| Health check fails | Wrong path/port | Check target group settings |

---

## 15. Cleanup & Cost Management

### 💰 Monthly Cost Estimate

| Resource | Spec | Cost/Month |
|:---|:---|:---|
| Fargate vCPU | 0.25 × 2 tasks | ~$14.50 |
| Fargate Memory | 0.5 GB × 2 | ~$3.96 |
| ALB | 1 | ~$16.20 |
| ECR Storage | ~200 MB | ~$0.02 |
| **Total** | | **~$34.77/month** |

> 💡 Practice শেষে delete করলে খরচ $0!

---

### 💡 Cost-Saving

```bash
# Scale to 0 (keep infrastructure)
aws ecs update-service --cluster fargate-cluster --service backend-service --desired-count 0 --region $AWS_REGION
aws ecs update-service --cluster fargate-cluster --service frontend-service --desired-count 0 --region $AWS_REGION

# Scale back to 1
aws ecs update-service --cluster fargate-cluster --service backend-service --desired-count 1 --region $AWS_REGION
aws ecs update-service --cluster fargate-cluster --service frontend-service --desired-count 1 --region $AWS_REGION
```

---

### 🗑️ Complete Cleanup

```bash
# 1. Scale to 0
aws ecs update-service --cluster fargate-cluster --service backend-service --desired-count 0 --region $AWS_REGION
aws ecs update-service --cluster fargate-cluster --service frontend-service --desired-count 0 --region $AWS_REGION
sleep 30

# 2. Delete services
aws ecs delete-service --cluster fargate-cluster --service backend-service --force --region $AWS_REGION
aws ecs delete-service --cluster fargate-cluster --service frontend-service --force --region $AWS_REGION

# 3. Delete cluster
aws ecs delete-cluster --cluster fargate-cluster --region $AWS_REGION

# 4. Delete ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --names fargate-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text --region $AWS_REGION)
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION
sleep 30

# 5. Delete target groups
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --names backend-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION) --region $AWS_REGION
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --names frontend-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION) --region $AWS_REGION

# 6. Delete ECR repos
aws ecr delete-repository --repository-name fargate-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name fargate-frontend --force --region $AWS_REGION

# 7. Delete security groups
aws ec2 delete-security-group --group-name service-sg --region $AWS_REGION
aws ec2 delete-security-group --group-name alb-sg --region $AWS_REGION

# 8. Delete logs
aws logs delete-log-group --log-group-name /ecs/fargate-backend --region $AWS_REGION
aws logs delete-log-group --log-group-name /ecs/fargate-frontend --region $AWS_REGION

echo "✅ Cleanup Complete!"
```

---

## 16. Custom Domain + HTTPS Setup

### 🌍 Why Custom Domain?
- Professional: `https://yourdomain.com` vs `http://fargate-alb-...`
- HTTPS security 🔒
- Auto HTTP→HTTPS redirect

---

### Step 1: Purchase Domain

**AWS Route 53:** `Route 53 → Registered domains → Register domain` ($12-15/year)

**OR Namecheap/GoDaddy** (cheaper)

---

### Step 2: Create Hosted Zone

```
Route 53 → Hosted zones → Create hosted zone
  Domain: yourdomain.com
  Type: Public
→ Create
```

---

### Step 3: Point Domain to ALB

```
Hosted zone → Create record
  Name: (empty)
  Type: A
  ☑️ Alias
  Route to: Alias to ALB → fargate-alb
→ Create

Also add www: same settings
```

---

### Step 4: SSL Certificate (FREE!)

```
ACM → Request certificate
  Domains: yourdomain.com, *.yourdomain.com
  Validation: DNS
→ Request → Create records in Route 53
→ Wait 5-10 min
```

---

### Step 5: Add HTTPS Listener

```
EC2 → ALB → fargate-alb → Listeners → Add
  Protocol: HTTPS:443
  Certificate: yourdomain.com
  Default: frontend-tg
→ Add

Then add /api/* rule for HTTPS too
```

---

### Step 6: HTTP→HTTPS Redirect

```
HTTP:80 listener → Edit default rule
  Action: Redirect → HTTPS:443 → 301
```

---

### 🧪 Test

```bash
curl -I https://yourdomain.com  # 200 OK
curl -I http://yourdomain.com   # 301 Redirect
```

### 💰 Cost

| Item | Cost |
|:---|:---|
| .com domain/year | $12-15 |
| Hosted zone/month | $0.50 |
| SSL Certificate | **FREE** |
| DNS queries | ~$0.50 |

---

## 17. Quick Reference Cheat Sheet

### 🎯 Deploy Order (DO NOT SKIP!)

```
1. Code → 2. Dockerfile → 3. ECR Push → 4. Security Groups
→ 5. Target Groups (CORRECT path!) → 6. ALB → 7. ALB Rules
→ 8. Task Definitions → 9. ECS Services (grace period 120!)
→ 10. WAIT 5 MIN → 11. Test → 12. Domain (optional)
```

---

### ⚠️ Critical Settings (MUST CHECK!)

| Setting | CORRECT Value | Where | Why? |
|:---|:---|:---|:---|
| Health check path | `/health` | Target Group | Fast JSON response |
| Health interval | **60s** | Target Group | Container breathing time |
| Unhealthy threshold | **10** | Target Group | 10 min tolerance |
| Success codes | **200,304** | Target Group | Next.js 304 support |
| Grace period | **120s** | ECS Service | Next.js slow start |
| Circuit breaker | **OFF** | ECS Service | Practice-তে rollback এড়াতে |
| Target type | **IP** | Target Group | Fargate no EC2 |
| Backend TG | **backend-tg** | ECS Service | Port 5000 match |
| Frontend TG | **frontend-tg** | ECS Service | Port 3000 match |

---

### ❌ Common Mistakes & Why Wrong

| Mistake | Why Wrong |
|:---|:---|
| Health check path `/` | Slow HTML response, timeout |
| Target type "Instance" | Fargate-এ instance নেই |
| Grace period 0 | Container start-এই fail |
| Circuit breaker ON | Practice-তে rollback loop |
| Backend → frontend-tg | Wrong port health check |
| Dockerfile hardcoded localhost | Production-এ কাজ করে না |
| Rapid updates | Task restart-এ 5 min লাগে |

---

### 🔧 Emergency Fix Commands

```bash
# Check events
aws ecs describe-services --cluster fargate-cluster --services frontend-service \
  --query 'services[0].events[:5]' --region us-east-1

# Check target health
aws elbv2 describe-target-health --target-group-arn $FRONTEND_TG_ARN --region us-east-1

# View logs
aws logs tail /ecs/fargate-frontend --follow --region us-east-1

# Last resort: restart
aws ecs update-service --cluster fargate-cluster --service frontend-service \
  --desired-count 0 --region us-east-1
sleep 30
aws ecs update-service --cluster fargate-cluster --service frontend-service \
  --desired-count 1 --region us-east-1
```

---

### 🧪 Test URLs

```
Frontend:  http://ALB_DNS/
Health:    http://ALB_DNS/health
Backend:   http://ALB_DNS/api/v1/health
Register:  http://ALB_DNS/register
Login:     http://ALB_DNS/login
Domain:    https://yourdomain.com
```

---

## 📊 Complete Architecture

```
                            🌐 INTERNET
                                │
                                ▼
                      ┌──────────────────┐
                      │   Route 53 (DNS) │ (Optional)
                      └────────┬─────────┘
                               │
                               ▼
                      ┌──────────────────┐
                      │  ALB (HTTP/HTTPS)│
                      │  fargate-alb     │
                      └────┬────────┬────┘
                           │        │
               /* ─────────┘        └──────── /api/*
                           │                    │
                           ▼                    ▼
                  ┌──────────────┐    ┌──────────────┐
                  │ frontend-tg  │    │ backend-tg   │
                  │ Port 3000    │    │ Port 5000    │
                  └──────┬───────┘    └──────┬───────┘
                         │                   │
                         ▼                   ▼
                  ┌──────────────┐    ┌──────────────┐
                  │ Fargate      │    │ Fargate      │
                  │ Frontend     │    │ Backend      │
                  │ 0.25 vCPU    │    │ 0.25 vCPU    │
                  │ 0.5 GB RAM   │    │ 0.5 GB RAM   │
                  └──────────────┘    └──────────────┘
                         │                   │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │       ECR         │
                         │  Container Images │
                         └───────────────────┘
```

---

## 🎓 What You Learned

| Concept | Hands-on |
|:---|:---|
| Docker | Multi-stage builds, health checks |
| ECR | Private registry, push/pull |
| ECS Fargate | Serverless containers |
| ALB | Path-based routing, health checks |
| Security Groups | Network security |
| IAM | Roles, policies |
| CloudWatch | Centralized logging |
| Secrets Manager | Secure env variables |
| Route 53 + ACM | Custom domain + SSL |

---

> 💡 **Pro Tips:**
> - Target Group path `/health` + Grace period 120s = 90% problems solved!
> - সব variable note করে রাখো
> - Practice শেষে cleanup করবে
> - `docker logs` locally test করে নাও

---

**© 2026 Arman Mia. All rights reserved.**  
**Happy Learning! 🚀**


