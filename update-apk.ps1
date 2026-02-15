# Build and copy APK to web distribution
Write-Host "Building APK..." -ForegroundColor Green
flutter build apk

Write-Host "Copying APK to web_distribution..." -ForegroundColor Green
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" -Destination "web_distribution\app-release.apk" -Force

Write-Host "Done! APK updated at web_distribution/app-release.apk" -ForegroundColor Green
