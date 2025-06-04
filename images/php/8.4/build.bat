@echo off
setlocal enabledelayedexpansion

echo Building Docker image for Laravel PHP 8.4...

REM Get current timestamp in GMT+7 (Indonesia Western Time)
REM First get UTC time, then add 7 hours
for /f "tokens=1-6 delims=/ : " %%a in ('echo %date% %time%') do (
    set "day=%%a"
    set "month=%%b" 
    set "year=%%c"
    set "hour=%%d"
    set "minute=%%e"
    set "second=%%f"
)

REM Clean up the values and pad with zeros if needed
set "day=0%day%"
set "day=%day:~-2%"
set "month=0%month%"
set "month=%month:~-2%"
set "hour=0%hour%"
set "hour=%hour:~-2%"
set "minute=0%minute%"
set "minute=%minute:~-2%"
set "second=0%second%"
set "second=%second:~-2%"

REM Add 7 hours for GMT+7
set /a "gmt7_hour=%hour% + 7"
if %gmt7_hour% geq 24 (
    set /a "gmt7_hour=%gmt7_hour% - 24"
    set /a "day=%day% + 1"
    REM Note: This is a simplified version. For production use, consider proper date handling for month/year rollovers
)

set "gmt7_hour=0%gmt7_hour%"
set "gmt7_hour=%gmt7_hour:~-2%"

REM Create timestamp in YYYYMMDDHHmmss format
set "timestamp=%year%%month%%day%%gmt7_hour%%minute%%second%"

REM Create the image tag
set "image_tag=juniyadi/php:laravel-php8.4-%timestamp%"

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
