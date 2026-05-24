#!/bin/bash
set -e  # Stop the script if any command fails

APP_NAME="tienda-de-ropa"

# =============================================================================
# ENVIRONMENT SELECTION
# =============================================================================

echo ""
echo "========================================"
echo "  Tienda de Ropa                 "
echo "  Deployment                     "
echo "========================================"
echo ""
read -p "Which environment do you want to deploy? (e.g. dev, prod): " ENV

# Validate that the user has entered a value
if [ -z "$ENV" ]; then
  echo "Error: You must specify an environment."
  exit 1
fi

# Validate that the environment folder exists
if [ ! -d "envs/$ENV" ]; then
  echo "Error: Environment 'envs/$ENV' does not exist. Create the folder first."
  exit 1
fi

# =============================================================================
# CONFIGURATION — read from the active gcloud profile
# =============================================================================

PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)
REPO="$REGION-docker.pkg.dev/$PROJECT_ID/$APP_NAME-$ENV"

echo ""
echo "Environment : $ENV"
echo "Project     : $PROJECT_ID"
echo "Region      : $REGION"
echo ""
read -p "Continue with the deployment in this project and region? (yes/no): " CONFIRM

# Validate user confirmation
if [ "$CONFIRM" != "yes" ]; then
  echo "Cancelled."
  exit 1
fi

# =============================================================================
# GENERATE terraform.tfvars dynamically for the chosen environment
# =============================================================================

# terraform.tfvars 00_base
cat > envs/$ENV/terraform/00_base/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
environment     = "$ENV"
app_name        = "$APP_NAME"
EOF
echo "✅ terraform.tfvars generated in envs/$ENV/terraform/00_base."

# terraform.tfvars 01_data
cat > envs/$ENV/terraform/01_data/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
app_name        = "$APP_NAME"
environment     = "$ENV"
EOF
echo "✅ terraform.tfvars generated in envs/$ENV/terraform/01_data."

# terraform.tfvars 02_app — cors_origins se añade después de desplegar la API (Phase 4)
cat > envs/$ENV/terraform/02_app/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
environment     = "$ENV"
app_name        = "$APP_NAME"
EOF
echo "✅ terraform.tfvars generated in envs/$ENV/terraform/02_app."

# =============================================================================
# PHASE 0 — Enable required GCP APIs (idempotent)
# =============================================================================

echo ""
echo ">>> PHASE 0: Enabling GCP APIs..."
gcloud services enable \
        iam.googleapis.com \
        cloudresourcemanager.googleapis.com \
        artifactregistry.googleapis.com \
        secretmanager.googleapis.com \
        run.googleapis.com \
        sqladmin.googleapis.com \
        sql-component.googleapis.com

echo "✅ Phase 0 complete. APIs enabled in GCP."

# =============================================================================
# PHASE 1 — Terraform apply base
# =============================================================================

echo ""
echo ">>> PHASE 1: Deploying base infrastructure for environment '$ENV'..."
cd envs/$ENV/terraform/00_base

terraform init -upgrade

echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

terraform apply -auto-approve

cd ../../../..

echo ""
echo "✅ Phase 1 complete. Base infrastructure ready for environment '$ENV'."

# =============================================================================
# PHASE 2 — Build and push API Docker image
# =============================================================================

echo ""
echo ">>> PHASE 2: Building and pushing API Docker image to Artifact Registry..."

# Pre-flight check: verify Docker is running
echo "-> Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
    echo "⚠️ Docker is not running. Attempting to start Docker Desktop automatically..."
    "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
    echo "⏳ Waiting for the Docker engine to start (this may take 1-2 minutes)..."
    while ! docker info > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo ""
    echo "Docker has started and is ready."
else
    echo "Docker was already running."
fi

# Authenticate the local Docker client with Google Cloud
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet

IMAGE_URL_API="$REPO/api:latest"
IMAGE_URL_FRONTEND="$REPO/frontend:latest"
IMAGE_URL_DBJOB="$REPO/db-init:latest"

echo "-> Building API image..."
cd ..
cp -r images server/
docker build --platform linux/amd64 -t $IMAGE_URL_API server
rm -rf server/images
docker push $IMAGE_URL_API

echo "-> Building db-init image..."
cp init-db/01-schema.sql db-init/schema.sql
docker build --platform linux/amd64 -t $IMAGE_URL_DBJOB db-init
rm db-init/schema.sql
docker push $IMAGE_URL_DBJOB

cd GCP

echo "✅ Phase 2 complete. API and db-init images pushed to Artifact Registry."

# =============================================================================
# PHASE 3 — Terraform apply data
# =============================================================================

echo ""
echo ">>> PHASE 3: Deploying data infrastructure for environment '$ENV'..."
cd envs/$ENV/terraform/01_data

terraform init -upgrade

echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

terraform apply -auto-approve

cd ../../../..

echo ""
echo "✅ Phase 3 complete. Data infrastructure ready for environment '$ENV'."

# =============================================================================
# PHASE 4 — Deploy API Cloud Run, capture URL
# =============================================================================

echo ""
echo ">>> PHASE 4: Deploying API Cloud Run service for environment '$ENV'..."
cd envs/$ENV/terraform/02_app

terraform init -upgrade

echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

terraform apply -auto-approve -target=module.api_service -target=module.db_init_job

API_URL=$(terraform output -raw api_service_url)
echo "API URL: $API_URL"

cd ../../../..

echo ""
echo "✅ Phase 4 complete. API service deployed at $API_URL"

# Derive FRONTEND_URL from API_URL — same project hash, different service name.
# Cloud Run v2 URLs follow {service-name}-{hash}.{region}.run.app, so replacing
# the service name gives the exact frontend URL without any separate lookup.
FRONTEND_URL="${API_URL/$APP_NAME-api-$ENV/$APP_NAME-frontend-$ENV}"
echo "Frontend URL (computed): $FRONTEND_URL"

# Update 02_app tfvars with the correct CORS_ORIGINS now that we know both URLs.
cat > envs/$ENV/terraform/02_app/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
environment     = "$ENV"
app_name        = "$APP_NAME"
cors_origins    = "$FRONTEND_URL"
EOF
echo "✅ terraform.tfvars updated in envs/$ENV/terraform/02_app with cors_origins."

# =============================================================================
# PHASE 4.5 — Execute DB init job (creates tables and loads seed data)
# =============================================================================

echo ""
echo ">>> PHASE 4.5: Running DB init job to create tables and seed data..."
gcloud run jobs execute "${APP_NAME}-db-init-${ENV}" \
  --wait \
  --region "$REGION" \
  --project "$PROJECT_ID"

echo "✅ Phase 4.5 complete. Database initialized."

# =============================================================================
# PHASE 5 — Build and push Frontend Docker image with API URL
# =============================================================================

echo ""
echo ">>> PHASE 5: Building and pushing Frontend Docker image..."

echo "-> Building FRONTEND image with VITE_API_URL=$API_URL..."
cd ..
docker build --platform linux/amd64 --build-arg "VITE_API_URL=$API_URL" -t $IMAGE_URL_FRONTEND frontend
docker push $IMAGE_URL_FRONTEND
cd GCP

echo "✅ Phase 5 complete. Frontend image pushed to Artifact Registry."

# =============================================================================
# PHASE 6 — Terraform apply app (full — adds frontend)
# =============================================================================

echo ""
echo ">>> PHASE 6: Deploying frontend Cloud Run service for environment '$ENV'..."
cd envs/$ENV/terraform/02_app

terraform apply -auto-approve

FRONTEND_URL=$(terraform output -raw frontend_service_url)

cd ../../../..

echo ""
echo "✅ Phase 6 complete. App infrastructure ready for environment '$ENV'."
echo ""
echo "========================================"
echo "  Deployment complete!"
echo "  API:      $API_URL"
echo "  Frontend: $FRONTEND_URL"
echo "========================================"

# =============================================================================
# OPTIONAL DESTROY — Only available in the dev environment
# =============================================================================

if [ "$ENV" = "dev" ]; then
  echo ""
  read -p "Do you want to run terraform destroy for the dev environment? (destroy/no): " DESTROY
  if [ "$DESTROY" = "destroy" ]; then
    echo ""
    echo ">>> Running terraform destroy for environment 'dev'..."
    cd envs/dev/terraform/02_app
    terraform destroy -auto-approve
    cd ../../../..
    cd envs/dev/terraform/01_data
    terraform destroy -auto-approve
    cd ../../../..
    cd envs/dev/terraform/00_base
    terraform destroy -auto-approve
    cd ../../../..

    echo ""
    echo "Destroy complete."
  else
    echo "Destroy cancelled."
  fi
fi
