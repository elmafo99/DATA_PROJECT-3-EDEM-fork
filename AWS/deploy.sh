#!/bin/bash
set -e  # Stop the script if any command fails

APP_NAME="store"
ENV="prod"
REGION="eu-north-1"
TF_DIR="envs/$ENV/$REGION"

# =============================================================================
# CONFIGURATION — derived from active AWS/gcloud CLI sessions
# =============================================================================

echo ""
echo "========================================"
echo "  Store - GCP -> AWS Migration Deploy"
echo "========================================"
echo ""

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
GCP_PROJECT_ID=$(gcloud config get-value project)

echo "AWS Account  : $AWS_ACCOUNT_ID"
echo "AWS Identity : $CALLER_ARN"
echo "GCP Project  : $GCP_PROJECT_ID"
echo "Region       : $REGION"
echo ""
read -p "Continue with the deployment to this account/project? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cancelled."
  exit 1
fi

# =============================================================================
# GENERATE terraform.tfvars
# =============================================================================

cat > "$TF_DIR/terraform.tfvars" <<EOF
app_name       = "$APP_NAME"
environment    = "$ENV"
aws_account_id = "$AWS_ACCOUNT_ID"
gcp_project_id = "$GCP_PROJECT_ID"
EOF
echo "Generated $TF_DIR/terraform.tfvars"

# =============================================================================
# PHASE 1 — Network, IAM, ECR, RDS, ECS (frontend service deferred)
# =============================================================================
#
# NOTE: this requires the S3 state bucket + DynamoDB lock table to already
# exist (see comments in $TF_DIR/backend.tf for the bootstrap commands).

echo ""
echo ">>> PHASE 1: Deploying network, database, and ECS (without frontend)..."
cd "$TF_DIR"

terraform init -upgrade

echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi

terraform apply -auto-approve \
  -target=module.network \
  -target=module.ecr \
  -target=module.database \
  -target=module.compute \
  -var "deploy_frontend=false"

ECR_API=$(terraform output -json ecr_repository_urls | python3 -c "import sys,json; print(json.load(sys.stdin)['api'])")
ECR_FRONTEND=$(terraform output -json ecr_repository_urls | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])")
ECR_DBINIT=$(terraform output -json ecr_repository_urls | python3 -c "import sys,json; print(json.load(sys.stdin)['db-init'])")
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)

cd ../../..

echo ""
echo "Phase 1 complete."

# =============================================================================
# PHASE 2 — Build and push API + db-init images
# =============================================================================

echo ""
echo ">>> PHASE 2: Building and pushing API and db-init images..."

if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running. Start Docker Desktop and re-run."
    exit 1
fi

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

echo "-> Building API image (with embedded product images)..."
cp -r images server/
docker build --platform linux/amd64 -f server/DOCKERFILE -t "$ECR_API:latest" server
rm -rf server/images
docker push "$ECR_API:latest"

echo "-> Building db-init image..."
cp init-db/01-schema.sql db-init/schema.sql
docker build --platform linux/amd64 -f db-init/Dockerfile -t "$ECR_DBINIT:latest" db-init
rm db-init/schema.sql
docker push "$ECR_DBINIT:latest"

echo ""
echo "Phase 2 complete."

# =============================================================================
# PHASE 3 — Re-apply so the API service picks up the pushed image, then
# capture its public URL
# =============================================================================

echo ""
echo ">>> PHASE 3: Rolling out API service and capturing its URL..."
cd "$TF_DIR"

terraform apply -auto-approve \
  -target=module.compute \
  -var "deploy_frontend=false"

API_URL=$(terraform output -raw api_url)
echo "API URL: $API_URL"

cd ../../..

echo ""
echo "Phase 3 complete."

# =============================================================================
# PHASE 3.5 — Run the db-init one-off task (creates tables and loads seed data)
# =============================================================================

echo ""
echo ">>> PHASE 3.5: Running db-init task against RDS..."
cd "$TF_DIR"

TASK_DEF_ARN=$(terraform output -raw db_init_task_definition_arn)
SUBNET_A=$(terraform output -json db_init_subnet_ids | python3 -c "import sys,json; print(json.load(sys.stdin)[0])")
SECURITY_GROUP=$(terraform output -raw db_init_security_group_id)

cd ../../..

DB_INIT_TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER_NAME" \
  --launch-type FARGATE \
  --task-definition "$TASK_DEF_ARN" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --region "$REGION" \
  --query 'tasks[0].taskArn' --output text)

echo "-> Waiting for db-init task to finish ($DB_INIT_TASK_ARN)..."
aws ecs wait tasks-stopped --cluster "$CLUSTER_NAME" --tasks "$DB_INIT_TASK_ARN" --region "$REGION"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$DB_INIT_TASK_ARN" --region "$REGION" \
  --query 'tasks[0].containers[0].exitCode' --output text)

if [ "$EXIT_CODE" != "0" ]; then
  echo "ERROR: db-init task exited with code $EXIT_CODE. Check CloudWatch Logs (/ecs/${APP_NAME}-${ENV}-db-init)."
  exit 1
fi

echo ""
echo "Phase 3.5 complete. Database initialized."

# =============================================================================
# PHASE 4 — Build and push frontend image with the API URL baked in
# =============================================================================

echo ""
echo ">>> PHASE 4: Building and pushing frontend image (VITE_API_URL=$API_URL)..."

docker build --platform linux/amd64 --build-arg "VITE_API_URL=$API_URL" -f frontend/DOCKERFILE -t "$ECR_FRONTEND:latest" frontend
docker push "$ECR_FRONTEND:latest"

echo ""
echo "Phase 4 complete."

# =============================================================================
# PHASE 5 — Final apply: bring up the frontend service
# =============================================================================

echo ""
echo ">>> PHASE 5: Deploying frontend service..."
cd "$TF_DIR"

terraform apply -auto-approve

FRONTEND_URL=$(terraform output -raw frontend_url)

cd ../../..

echo ""
echo "========================================"
echo "  Deployment complete!"
echo "  API:      $API_URL"
echo "  Frontend: $FRONTEND_URL"
echo "========================================"

# =============================================================================
# ONE-OFF — migration-sub image (":subscription" tag)
# =============================================================================
#
# Not part of the regular deploy flow: this image is only needed once, to run
# the "store-prod-migration-sub" task that creates the logical replication
# subscription from GCP Cloud SQL into RDS (see AWS/README.md). Rebuild it
# only if the image/tag is ever lost:
#
#   ECR_DBINIT=$(cd envs/prod/eu-north-1 && terraform output -json ecr_repository_urls | python3 -c "import sys,json; print(json.load(sys.stdin)['db-init'])")
#   aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin "${ECR_DBINIT%/*}"
#   docker build --platform linux/amd64 -f db-init/subscription/Dockerfile -t "$ECR_DBINIT:subscription" db-init/subscription
#   docker push "$ECR_DBINIT:subscription"
#
# Then run it via:
#   aws ecs run-task --cluster store-prod-cluster --launch-type FARGATE \
#     --task-definition store-prod-migration-sub \
#     --network-configuration "awsvpcConfiguration={subnets=[<private-subnet>],securityGroups=[<ecs-tasks-sg>],assignPublicIp=DISABLED}"
