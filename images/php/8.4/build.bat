@echo off
setlocal enabledelayedexpansion

echo Building Docker image for Laravel PHP 8.4...

for /f "tokens=2 delims==" %%I in ('"wmic os get localdatetime /value"') do set datetime=%%I
set datetime=%datetime:~2,2%%datetime:~4,2%%datetime:~6,2%%datetime:~8,2%%datetime:~10,2%

REM Create the image tag
set "image_tag=juniyadi/php:laravel-php8.4-%datetime%"

echo Building image with tag: %image_tag%
echo.

REM Build the Docker image
docker build -t %image_tag% .

REM Push to Docker Hub
echo Pushing image to Docker Hub
echo Image tag: %image_tag%
echo.
docker push %image_tag%

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo Build completed successfully!
    echo Image tagged as: %image_tag%
    echo ========================================
    echo.
    echo You can now run:
    echo   docker run -d -p 80:80 %image_tag%
    echo.
) else (
    echo.
    echo ========================================
    echo Build failed! Please check the errors above.
    echo ========================================
)

pause
