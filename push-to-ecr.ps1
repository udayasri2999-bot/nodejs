# push-to-ecr.ps1
# Run this AFTER terraform apply to build and push your Docker image to ECR
# Usage: .\push-to-ecr.ps1

$AWS_REGION   = "ap-southeast-2"
$ACCOUNT_ID   = "558262519792"
$REPO_NAME    = "nodejs-app"
$ECR_URL      = "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
$IMAGE_URI    = "$ECR_URL/$REPO_NAME:latest"

Write-Host "=== Logging into ECR ===" -ForegroundColor Cyan
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

if ($LASTEXITCODE -ne 0) {
    Write-Host "ECR login failed. Make sure Docker is running and AWS CLI is configured." -ForegroundColor Red
    exit 1
}

Write-Host "=== Building Docker image ===" -ForegroundColor Cyan
docker build -t $REPO_NAME .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build failed." -ForegroundColor Red
    exit 1
}

Write-Host "=== Tagging image ===" -ForegroundColor Cyan
docker tag "$REPO_NAME:latest" $IMAGE_URI

Write-Host "=== Pushing to ECR ===" -ForegroundColor Cyan
docker push $IMAGE_URI

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker push failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== SUCCESS ===" -ForegroundColor Green
Write-Host "Image pushed: $IMAGE_URI" -ForegroundColor Green
Write-Host ""
Write-Host "Your app will automatically pull this image on the EC2 instance." -ForegroundColor Yellow
