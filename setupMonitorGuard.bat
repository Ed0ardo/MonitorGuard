@echo off
setlocal enabledelayedexpansion

:: Check for admin rights (optional for user folder, but safe)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=%APPDATA%\MonitorGuard"
set "SCRIPT_URL=https://raw.githubusercontent.com/Ed0ardo/MonitorGuard/refs/heads/main/MonitorGuard.bat"
set "LOCAL_PATH=%INSTALL_DIR%\MonitorGuard.bat"
set "STARTMENU_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\MonitorGuard"
set "SHORTCUT_PATH=%STARTMENU_FOLDER%\MonitorGuard.lnk"

echo Creating directories...
if not exist "%INSTALL_DIR%\" mkdir "%INSTALL_DIR%"
if not exist "%STARTMENU_FOLDER%\" mkdir "%STARTMENU_FOLDER%"
if %errorlevel% neq 0 (
    echo Failed to create directories.
    pause
    exit /b 1
)

echo Downloading MonitorGuard.bat...
if not exist "%LOCAL_PATH%" (
    powershell -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_PATH%'"
    if %errorlevel% neq 0 (
        echo Download failed. Check internet or URL.
        pause
        exit /b 1
    )
) else (
    echo File already exists.
)

echo Creating Start Menu shortcut...
if exist "%SHORTCUT_PATH%" del "%SHORTCUT_PATH%"
powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%SHORTCUT_PATH%'); $Shortcut.TargetPath = '%LOCAL_PATH%'; $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; $Shortcut.Save()"

echo Installation complete! Find "MonitorGuard" in Start Menu (Win key → All Apps).
pause
