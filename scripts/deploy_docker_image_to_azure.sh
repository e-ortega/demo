#!/usr/bin/env bash
set -euo pipefail

# deploy_from_dockerhub.sh
# Usage: edit variables below, then run: ./deploy_from_dockerhub.sh

####### USER CONFIG - EDIT THESE ########
DOCKER_USER="eortega1793"           # <-- set your Docker Hub username
DOCKER_API_REPO="${DOCKER_USER}/demo-api:latest"
DOCKER_CLIENT_REPO="${DOCKER_USER}/demo-client:latest"

RG="demo-rg-docker"
LOCATION="canadaeast"                      # change if you prefer different region
PLAN="demo-plan"
API_NAME="demo-api-app"
CLIENT_NAME="demo-client-app"

# If your Docker Hub repos are private, set these (or export env vars DOCKERHUB_USER/DOCKERHUB_PASS)
# Leave empty to assume public repos:
DOCKERHUB_USER="${DOCKER_USER}"
DOCKERHUB_PASS="${DOCKER_HUB_PASSWORD:-}"

##########################################

# Helper: print and run
run() {
echo -e "\n+ $*"
"$@"
}

echo "Starting deployment using Docker Hub images..."
echo "Resource group: $RG"
echo "Region: $LOCATION"
echo "Plan: $PLAN (Linux)"
echo "API image: $DOCKER_API_REPO"
echo "Client image: $DOCKER_CLIENT_REPO"

# 1) Ensure logged in to Azure
if ! az account show &>/dev/null; then
echo "You are not logged into Azure CLI. Run: az login"
exit 1
fi

# 2) Create resource group
run az group create --name "$RG" --location "$LOCATION"

# 3) Create App Service Plan (try F1 then fallback to B1)
echo "Creating App Service Plan (Linux). Trying F1, fallback to B1 if unavailable..."
if az appservice plan create --name "$PLAN" --resource-group "$RG" --sku F1 --is-linux 2>/dev/null; then
echo "Plan created with F1 (Free) SKU."
else
echo "F1 unavailable or failed. Creating B1..."
run az appservice plan create --name "$PLAN" --resource-group "$RG" --sku B1 --is-linux
fi

# Show plan info
run az appservice plan show --name "$PLAN" --resource-group "$RG" --query "{name:name,sku:sku,kind:kind,location:location}" -o json

# 4) (Optional) Push local images to Docker Hub (uncomment if you need to push)
# echo "Optional: building & pushing local images to Docker Hub..."
# docker build -f Reactivities/API/Dockerfile -t "${DOCKER_USER}/demo-api:latest" Reactivities/API
# docker push "${DOCKER_USER}/demo-api:latest"
# docker build -f Reactivities/client/Dockerfile -t "${DOCKER_USER}/demo-client:latest" Reactivities/client
# docker push "${DOCKER_USER}/demo-client:latest"

# 5) Create Web App for API (public image)
echo "Creating Web App for API..."
if [[ -n "${DOCKERHUB_PASS:-}" ]]; then
# private image: create with credentials
run az webapp create \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --name "$API_NAME" \
    --deployment-container-image-name "$DOCKER_API_REPO" \
    --docker-registry-server-user "$DOCKERHUB_USER" \
    --docker-registry-server-password "$DOCKERHUB_PASS" \
    --docker-registry-server-url "docker.io"
else
# public image
run az webapp create \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --name "$API_NAME" \
    --deployment-container-image-name "$DOCKER_API_REPO"
fi

# 6) Create Web App for Client (public image)
echo "Creating Web App for Client..."
if [[ -n "${DOCKERHUB_PASS:-}" ]]; then
run az webapp create \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --name "$CLIENT_NAME" \
    --deployment-container-image-name "$DOCKER_CLIENT_REPO" \
    --docker-registry-server-user "$DOCKERHUB_USER" \
    --docker-registry-server-password "$DOCKERHUB_PASS" \
    --docker-registry-server-url "docker.io"
else
run az webapp create \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --name "$CLIENT_NAME" \
    --deployment-container-image-name "$DOCKER_CLIENT_REPO"
fi

# 7) Configure app settings (example: set client API base URL)
API_URL="https://$(az webapp show -g "$RG" -n "$API_NAME" --query defaultHostName -o tsv)"
CLIENT_URL="https://$(az webapp show -g "$RG" -n "$CLIENT_NAME" --query defaultHostName -o tsv)"

echo "API URL will be: $API_URL"
echo "Client URL will be: $CLIENT_URL"

# Example env var for client build (if your client reads it at runtime, otherwise rebuild)
run az webapp config appsettings set -g "$RG" -n "$CLIENT_NAME" --settings VITE_API_BASE_URL="$API_URL"

# 8) Enable container logs and show tail command suggestions
run az webapp log config --name "$API_NAME" --resource-group "$RG" --docker-container-logging filesystem
run az webapp log config --name "$CLIENT_NAME" --resource-group "$RG" --docker-container-logging filesystem

echo
echo "To tail logs run in separate terminals:"
echo "az webapp log tail --name $API_NAME --resource-group $RG"
echo "az webapp log tail --name $CLIENT_NAME --resource-group $RG"
echo

# 9) Restart apps (ensure fresh pull)
run az webapp restart --name "$API_NAME" --resource-group "$RG"
run az webapp restart --name "$CLIENT_NAME" --resource-group "$RG"

# 10) Final info
echo
echo "=== Deployment complete ==="
echo "API:  $API_URL"
echo "Client: $CLIENT_URL"
echo
echo "If the containers fail to start, run the log tail commands above to see stdout/stderr."

exit 0
