# PowerShell Script to build Flutter APK and deploy to web distribution
# Usage: ./build-and-deploy.ps1

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Attendance System - APK Build & Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Flutter is installed
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "Error: Flutter not found. Make sure Flutter is installed and in your PATH." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 1: Clean
Write-Host "[1/4] Cleaning previous builds..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter clean failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 2: Get dependencies
Write-Host "[2/4] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter pub get failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 3: Build APK
Write-Host "[3/4] Building APK (this may take a few minutes)..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter build failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 4: Copy to web distribution
Write-Host "[4/4] Copying APK to web_distribution folder..." -ForegroundColor Yellow

# Create directory if it doesn't exist
if (-not (Test-Path "web_distribution")) {
    New-Item -ItemType Directory -Path "web_distribution" -Force | Out-Null
}

$apkSource = "build\app\outputs\flutter-apk\app-release.apk"
$apkDest = "web_distribution\app-release.apk"

if (-not (Test-Path $apkSource)) {
    Write-Host "Error: APK not found at $apkSource" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Copy-Item $apkSource -Destination $apkDest -Force

# Get file size
$fileSize = (Get-Item $apkDest).Length / 1MB
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "APK file: $apkDest" -ForegroundColor Green
Write-Host "File size: $([Math]::Round($fileSize, 2)) MB" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. To test locally, run:" -ForegroundColor Cyan
Write-Host "   cd web_distribution" -ForegroundColor White
Write-Host "   python -m http.server 8000" -ForegroundColor White
Write-Host ""
Write-Host "2. Then visit: http://localhost:8000" -ForegroundColor White
Write-Host ""
Write-Host "3. To deploy online, follow instructions in:" -ForegroundColor Cyan
Write-Host "   web_distribution\README.md" -ForegroundColor White
Write-Host ""

# Optional: Open browser
$response = Read-Host "Open website in browser? (y/n)"
if ($response -eq 'y' -or $response -eq 'Y') {
    # Start local server in background
    Write-Host "Starting local server on port 8000..." -ForegroundColor Yellow
    Push-Location "web_distribution"
    Start-Process python -ArgumentList "-m http.server 8000" -NoNewWindow
    Pop-Location
    
    # Give server time to start
    Start-Sleep -Seconds 2
    
    # Open browser
    Start-Process "http://localhost:8000"
    Write-Host "Opening browser... Press Ctrl+C to stop the server" -ForegroundColor Green
}
