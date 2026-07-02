@echo off
setlocal
title Zebra SSH - Build Tools

:: 闁告帒娲﹀畷鏌ュ礆閹峰苯澹栭柡鍫墯婢у秹宕烽妸褎绐楃憸?cd /d "%~dp0"

:menu
cls
echo.
echo ========================================
echo   Zebra SSH - Build Tools
echo ========================================
echo.
echo   [1] Build (full release)
echo   [2] Clean build artifacts
echo   [3] Clean + Build
echo   [4] Exit
echo.
set /p choice=  Select option [1-4]:

if "%choice%"=="1" goto build
if "%choice%"=="2" goto clean
if "%choice%"=="3" goto clean_build
if "%choice%"=="4" goto exit_app
echo Invalid option!
pause
goto menu

:build
call :do_build
goto end_pause

:clean
call :do_clean
goto end_pause

:clean_build
call :do_clean
call :do_build
goto end_pause

:do_clean
echo.
echo Cleaning build artifacts...
if exist build rmdir /s /q build
if exist packer\target rmdir /s /q packer\target
if exist windows\flutter\ephemeral rmdir /s /q windows\flutter\ephemeral
if exist linux\flutter\ephemeral rmdir /s /q linux\flutter\ephemeral
if exist .dart_tool rmdir /s /q .dart_tool
echo Done!
goto :eof

:do_build
echo.
echo ========================================
echo   Zebra SSH - Windows Build
echo ========================================
echo.

echo [1/6] Running flutter pub get...
call flutter pub get
if errorlevel 1 goto :build_error

echo.
echo [2/6] Building Flutter Windows release...
call flutter build windows --release
if errorlevel 1 goto :build_error

echo.
echo [3/6] Building zebra-pack tool...
cd packer
cargo build --release --bin zebra-pack
if errorlevel 1 goto :pack_build_error

echo.
echo [4/6] Packing files into data.bin...
target\release\zebra-pack.exe -f ..\build\windows\x64\runner\Release -e zebra.exe -n zebra-ssh
if errorlevel 1 goto :pack_error

echo.
echo [5/6] Building self-extracting exe...
cargo build --release --bin zebra
if errorlevel 1 goto :build_packer_error
cd ..

echo.
echo [6/6] Done!
echo.
echo Output: packer\target\release\zebra.exe
dir packer\target\release\zebra.exe
goto :eof

:build_error
echo.
echo [ERROR] Flutter build failed!
cd ..
goto :eof

:pack_build_error
echo.
echo [ERROR] Packer tool build failed!
cd ..
goto :eof

:pack_error
echo.
echo [ERROR] Packing failed!
cd ..
goto :eof

:build_packer_error
echo.
echo [ERROR] Self-extracting exe build failed!
cd ..
goto :eof

:end_pause
echo.
echo Press any key to return to menu...
pause >nul
goto menu

:exit_app
exit /b 0
