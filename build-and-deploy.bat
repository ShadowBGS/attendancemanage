@echo off
REM Script to build Flutter APK and copy to web distribution folder
REM Usage: Run this from the project root directory

echo.
echo ========================================
echo  Attendance System - APK Build & Deploy
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo Error: Flutter not found. Make sure Flutter is installed and in your PATH.
    pause
    exit /b 1
)

REM Clean previous builds
echo [1/4] Cleaning previous builds...
flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo Error: Flutter clean failed.
    pause
    exit /b 1
)

REM Get dependencies
echo [2/4] Getting dependencies...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo Error: Flutter pub get failed.
    pause
    exit /b 1
)

REM Build APK
echo [3/4] Building APK...
flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo Error: Flutter build failed.
    pause
    exit /b 1
)

REM Copy APK to web distribution folder
echo [4/4] Copying APK to web_distribution folder...
if not exist "web_distribution" (
    mkdir web_distribution
)

copy "build\app\outputs\flutter-apk\app-release.apk" "web_distribution\app-release.apk" /Y
if %ERRORLEVEL% NEQ 0 (
    echo Error: Copy failed.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  Build Complete!
echo ========================================
echo.
echo APK file: web_distribution\app-release.apk
echo.
echo Next steps:
echo 1. To test locally, run: python -m http.server 8000
echo 2. Then visit: http://localhost:8000
echo 3. To deploy, follow instructions in web_distribution\README.md
echo.
pause
