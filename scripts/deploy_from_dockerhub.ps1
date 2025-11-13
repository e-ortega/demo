<#
deploy_from_dockerhub.ps1
Creates resource group, App Service plan, two webapps (API + client) using Docker Hub images.
Edit the USER CONFIG section below before running.
#>

[CmdletBinding()]
param()

# ---------------- USER CONFIG - EDIT THESE ----------------
$DockerUser = "eortega1793"                    # <-- set your Docker Hub username
$DockerApiRepo = "$DockerUser/demo-api:latest"
$DockerClientRepo = "$DockerUser/demo-client:latest"

$RG = "demo-rg-docker"
$Location = "canadaeast"                                 # change if you prefer a different region
$Plan = "demo-plan"
$ApiName = "demo-api-app"
$ClientName = "demo-client-app"

# If Docker Hub repos are private, set these (or set env var DOCKERHUB_PASS)
$DockerHubUser = $DockerUser
$DockerHubPass = $env:DOCKERHUB_PASS                      # optional; read from env for security
# ---------------------------------------------------------

function Run-Command {
    param([string]$Cmd)
    Write-Host "`n+ $Cmd" -ForegroundColor Cyan
    iex $Cmd
}

Write-Host "Starting deployment using Docker Hub images..." -ForegroundColor Green
Write-Host "Resource group: $RG"
Write-Host "Region: $Location"
Write-Host "Plan: $Plan (Linux)"
Write-Host "API image: $DockerApiRepo"
Write-Host "Client image: $DockerClientRepo"

# 1) Ensure logged in to Azure
try {
    az account show *>$null
}
catch {
    Write-Error "You are not logged into Azure CLI. Run: az login"
    exit 1
}

# 2) Create resource group
Run-Command "az group create --name `"$RG`" --location `"$Location`" | ConvertFrom-Json"

# 3) Create App Service Plan (try F1 then fallback to B1)
Write-Host "`nCreating App Service Plan (Linux). Trying F1, fallback to B1 if unavailable..." -ForegroundColor Yellow
try {
    Run-Command "az appservice plan create --name `"$Plan`" --resource-group `"$RG`" --sku F1 --is-linux | ConvertFrom-Json"
    Write-Host "Plan created with F1 (Free) SKU." -ForegroundColor Green
}
catch {
    Write-Host "F1 unavailable or failed. Creating B1..." -ForegroundColor Yellow
    Run-Command "az appservice plan create --name `"$Plan`" --resource-group `"$RG`" --sku B1 --is-linux | ConvertFrom-Json"
}

# Show plan info
Run-Command "az appservice plan show --name `"$Plan`" --resource-group `"$RG`" --query '{name:name,sku:sku,kind:kind,location:location}' -o json | ConvertFrom-Json"

# 4) Optional: build & push local images - commented out
<# 
Write-Host "Optional: building & pushing local images to Docker Hub..."
docker build -f Reactivities/API/Dockerfile -t "$DockerUser/demo-api:latest" Reactivities/API
docker push "$DockerUser/demo-api:latest"
docker build -f Reactivities/client/Dockerfile -t "$DockerUser/demo-client:latest" Reactivities/client
docker push "$DockerUser/demo-client:latest"
#>

# 5) Create Web App for API (public or private)
Write-Host "`nCreating Web App for API..." -ForegroundColor Yellow
if (-not [string]::IsNullOrEmpty($DockerHubPass)) {
    Run-Command "az webapp create --resource-group `"$RG`" --plan `"$Plan`" --name `"$ApiName`" --deployment-container-image-name `"$DockerApiRepo`" --docker-registry-server-user `"$DockerHubUser`" --docker-registry-server-password `"$DockerHubPass`" --docker-registry-server-url `"docker.io`" | ConvertFrom-Json"
}
else {
    Run-Command "az webapp create --resource-group `"$RG`" --plan `"$Plan`" --name `"$ApiName`" --deployment-container-image-name `"$DockerApiRepo`" | ConvertFrom-Json"
}

# 6) Create Web App for Client
Write-Host "`nCreating Web App for Client..." -ForegroundColor Yellow
if (-not [string]::IsNullOrEmpty($DockerHubPass)) {
    Run-Command "az webapp create --resource-group `"$RG`" --plan `"$Plan`" --name `"$ClientName`" --deployment-container-image-name `"$DockerClientRepo`" --docker-registry-server-user `"$DockerHubUser`" --docker-registry-server-password `"$DockerHubPass`" --docker-registry-server-url `"docker.io`" | ConvertFrom-Json"
}
else {
    Run-Command "az webapp create --resource-group `"$RG`" --plan `"$Plan`" --name `"$ClientName`" --deployment-container-image-name `"$DockerClientRepo`" | ConvertFrom-Json"
}

# 7) Configure app settings (example: set client API base URL)
$apiUrl = (az webapp show -g $RG -n $ApiName --query defaultHostName -o tsv)
$clientUrl = (az webapp show -g $RG -n $ClientName --query defaultHostName -o tsv)
$ApiFullUrl = "https://$apiUrl"
$ClientFullUrl = "https://$clientUrl"

Write-Host "`nAPI URL will be: $ApiFullUrl"
Write-Host "Client URL will be: $ClientFullUrl"

# Example runtime setting for client (if your SPA reads env at runtime)
Run-Command "az webapp config appsettings set -g `"$RG`" -n `"$ClientName`" --settings VITE_API_BASE_URL=`"$ApiFullUrl`""

# 8) Enable container logs
Run-Command "az webapp log config --name `"$ApiName`" --resource-group `"$RG`" --docker-container-logging filesystem"
Run-Command "az webapp log config --name `"$ClientName`" --resource-group `"$RG`" --docker-container-logging filesystem"

Write-Host "`nTo tail logs run in separate shells:"
Write-Host "az webapp log tail --name $ApiName --resource-group $RG"
Write-Host "az webapp log tail --name $ClientName --resource-group $RG"

# 9) Restart apps to ensure fresh pull
Run-Command "az webapp restart --name `"$ApiName`" --resource-group `"$RG`""
Run-Command "az webapp restart --name `"$ClientName`" --resource-group `"$RG`""

# 10) Final info
Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
Write-Host "API:  $ApiFullUrl"
Write-Host "Client: $ClientFullUrl"
Write-Host ""
Write-Host "If the containers fail to start, run the log tail commands above to see stdout/stderr."

exit 0
