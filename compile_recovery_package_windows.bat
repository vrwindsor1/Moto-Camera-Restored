@echo off
REM ==============================================================================
REM Moto Camera Restored -- Universal Recovery Package Compiler (Windows Launcher)
REM Modular Multi-Generation Motorola Camera Recovery Package Compiler
REM ==============================================================================

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%compile_recovery_package_windows.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] Could not find: %PS_SCRIPT%
    pause
    exit /b 1
)

where powershell >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] PowerShell is required to run the universal compiler on Windows.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Compilation process encountered an issue.
    pause
    exit /b %ERRORLEVEL%
)

if "%~1"=="" (
    echo.
    echo Press any key to exit...
    pause >nul
)

exit /b 0
