#!/bin/bash
set -e  # Stop the script if any command fails

APP_NAME="risk-valencia"

# =============================================================================
# ENVIRONMENT SELECTION
# =============================================================================

echo ""
echo "========================================"
echo "  Risk Valencia                  "
echo "  Pipeline Deployment            "
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
ZONE=$(gcloud config get-value compute/zone)
REPO="$REGION-docker.pkg.dev/$PROJECT_ID/$APP_NAME-$ENV"


echo ""
echo "Environment : $ENV"
echo "Project     : $PROJECT_ID"
echo "Region      : $REGION"
echo "Zone        : $ZONE"
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
EOF
echo "✅ terraform.tfvars generated in envs/$ENV/terraform/01_data."

# terraform.tfvars 02_app
cat > envs/$ENV/terraform/02_app/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
zone            = "$ZONE"
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
        artifactregistry.googleapis.com \
        secretmanager.googleapis.com \
        compute.googleapis.com \
        firestore.googleapis.com\
        dataflow.googleapis.com

echo "✅ Phase 0 complete. APIs enabled in GCP."

# =============================================================================
# PHASE 1 — Terraform apply base
# =============================================================================

echo ""
echo ">>> PHASE 1: Deploying base infrastructure for environment '$ENV'..."
# Navigate to the environment folder chosen by the user
cd envs/$ENV/terraform/00_base

terraform init -upgrade

# Validate syntax (Fail Fast)
echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

echo "-> Syncing Firebase state (workaround for Identity Platform)..."

    # 1. Check if Terraform already has the resource in its state
    if ! terraform state list | grep -q "google_identity_platform_config.auth_config"; then
        # 2. If not, attempt to import it from GCP.
        # "2>/dev/null" suppresses error output.
        # "|| true" prevents the script from stopping if the import fails (e.g. on a fresh project).
        terraform import google_identity_platform_config.auth_config projects/$PROJECT_ID/config 2>/dev/null || true
    fi

terraform apply -auto-approve

# Return to the root (go up four levels)
cd ../../../..

echo ""
echo "✅ Phase 1 complete. Base infrastructure ready for environment '$ENV'."

# =============================================================================
# PHASE 2 — Docker image build and push (CI/CD)
# =============================================================================

echo ""
echo ">>> PHASE 2: Building and pushing Docker image to Artifact Registry..."

# Pre-flight check: verify Docker is running
echo "-> Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
    echo "⚠️ Docker is not running. Attempting to start Docker Desktop automatically..."
<<<<<<< Updated upstream
    
    # Typical Docker Desktop installation path on Windows (for Git Bash)
    "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
    
=======
    if [[ "$OSTYPE" == "darwin"* ]]; then
      open -a Docker &
    else
      "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
    fi
>>>>>>> Stashed changes
    echo "⏳ Waiting for the Docker engine to start (this may take 1-2 minutes)..."
    
    # Wait loop: keeps checking every 5 seconds until docker info succeeds
    while ! docker info > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo "" # Clean line break after dots
    echo "Docker has started and is ready."
else
    echo "Docker was already running."
fi

# Authenticate the local Docker client with Google Cloud
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet

# --- IMAGE VARIABLES ---
IMAGE_URL_INGESTION="$REPO/ingestion:latest"
IMAGE_URL_DATAFLOW="$REPO/dataflow:latest"
IMAGE_URL_DEMO_USERS="$REPO/firebase-seeder:latest"
IMAGE_URL_API="$REPO/api:latest"
IMAGE_URL_FRONTEND="$REPO/frontend:latest"
TEMPLATE_PATH="gs://$PROJECT_ID-$APP_NAME-dataflow-temp-$ENV/templates/flextemplate-dataflow.json"

# 1. Ingestion image
echo "-> Building INGESTION image..."
docker build --platform linux/amd64 -t $IMAGE_URL_INGESTION ./src/ingestion
docker push $IMAGE_URL_INGESTION

# 2. Dataflow image
echo "-> Building DATAFLOW image..."
docker build --platform linux/amd64 -t $IMAGE_URL_DATAFLOW ./src/dataflow
docker push $IMAGE_URL_DATAFLOW

# 3. Demo users image
echo "-> Building DEMO USERS image..."
docker build --platform linux/amd64 -t $IMAGE_URL_DEMO_USERS ./src/demo_users
docker push $IMAGE_URL_DEMO_USERS

# 4. API image
echo "-> Building API image..."
docker build --platform linux/amd64 -t $IMAGE_URL_API ./src/api
docker push $IMAGE_URL_API

# 5. FRONTEND image
echo "-> Building FRONTEND image..."
docker build --platform linux/amd64 -t $IMAGE_URL_FRONTEND ./src/frontend
docker push $IMAGE_URL_FRONTEND

echo "✅ Phase 2 complete. Docker images pushed to artifact registry."


# =============================================================================
# PHASE 3 — Terraform apply data
# =============================================================================

echo ""
echo ">>> PHASE 3: Deploying data infrastructure for environment '$ENV'..."
# Navigate to the environment folder chosen by the user
cd envs/$ENV/terraform/01_data

terraform init -upgrade

# Validate syntax (Fail Fast)
echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

terraform apply -auto-approve

# Return to the root (go up four levels)
cd ../../../..

echo ""
echo "✅ Phase 3 complete. Data infrastructure ready for environment '$ENV'."


# =============================================================================
# PHASE 4 — Dataflow Flex Template build
# =============================================================================
echo ""
echo ">>> PHASE 4: Registering Flex Template in Cloud Storage..."

gcloud dataflow flex-template build "$TEMPLATE_PATH" \
    --image "$IMAGE_URL_DATAFLOW" \
    --sdk-language "PYTHON" \
    --metadata-file "src/dataflow/metadata.json" \
    --project="$PROJECT_ID"

echo "Dataflow Flex Template registered at: $TEMPLATE_PATH"

echo ""
echo "✅ Phase 4 complete. Dataflow Flex Template registered."

# =============================================================================
# PHASE 5 — Terraform apply app
# =============================================================================

echo ""
echo ">>> PHASE 5: Deploying app infrastructure for environment '$ENV'..."
# Navigate to the environment folder chosen by the user
cd envs/$ENV/terraform/02_app

terraform init -upgrade

# Validate syntax (Fail Fast)
echo "-> Validating Terraform code..."
if ! terraform validate; then
    echo "❌ ERROR: Terraform validation failed. Check your .tf files."
    exit 1
fi
echo "✅ Terraform validated successfully."

terraform apply -auto-approve

# Return to the root (go up four levels)
cd ../../../..

echo ""
echo "✅ Phase 5 complete. App infrastructure ready for environment '$ENV'."

# =============================================================================
# PHASE 6 — Execute Firebase demo users seeder job
# =============================================================================
echo ""
echo ">>> PHASE 6: Running Firebase demo users seeder job..."
gcloud run jobs execute "firebase-demo-seeder-$ENV" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --wait
echo "✅ Phase 6 complete. Demo users created in Firebase."

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