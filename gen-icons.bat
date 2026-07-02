@echo off
setlocal
title Icon Generator

if "%~1"=="" (
    echo.
    echo Usage: gen-icons.bat ^<svg-file^>
    echo Example: gen-icons.bat assets\icons\icon.svg
    echo.
    pause
    exit /b 1
)

if not exist "%~1" (
    echo.
    echo Error: SVG file not found: %~1
    echo.
    pause
    exit /b 1
)

:: Build icon-gen if not exists
if not exist "packer\target\release\icon-gen.exe" (
    echo Building icon-gen...
    cd packer
    cargo build --release --bin icon-gen
    cd ..
)

echo.
echo Generating icons from: %~1
echo.
packer\target\release\icon-gen.exe "%~1"
echo.
pause