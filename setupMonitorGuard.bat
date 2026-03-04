@echo off
setlocal enabledelayedexpansion

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=%APPDATA%\MonitorGuard"
set "SCRIPT_URL=https://raw.githubusercontent.com/Ed0ardo/MonitorGuard/refs/heads/main/MonitorGuard.bat"
set "ICON_URL=https://raw.githubusercontent.com/Ed0ardo/MonitorGuard/refs/heads/main/monitorGuard.ico"
set "LOCAL_PATH=%INSTALL_DIR%\MonitorGuard.bat"
set "ICON_PATH=%INSTALL_DIR%\MonitorGuard.ico"
set "EXE_PATH=%INSTALL_DIR%\MonitorGuard.exe"
set "STARTMENU_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\MonitorGuard"
set "SHORTCUT_PATH=%STARTMENU_FOLDER%\MonitorGuard.lnk"
set "DESKTOP_PATH=%USERPROFILE%\Desktop\MonitorGuard.lnk"

cls
echo ============================================================
echo          MonitorGuard Installer - Setup Wizard
echo ============================================================
echo.
echo  This wizard will install MonitorGuard on your system.
echo  Please answer the following questions to customize
echo  your installation.
echo.
echo ============================================================
echo.
pause

:: --- Step 1: Start Menu ---
cls
echo ============================================================
echo   STEP 1 of 3 - Start Menu
echo ============================================================
echo.
echo  Would you like to add MonitorGuard to the Start Menu?
echo.
echo  Note: After installation, you can pin it to your Favorites
echo  manually by right-clicking it in All Apps ^> Pin to Start.
echo.
set "ADD_STARTMENU="
:ask_startmenu
set /p "ADD_STARTMENU=  Add to Start Menu? [Y/N]: "
if /i "!ADD_STARTMENU!"=="Y" goto step2
if /i "!ADD_STARTMENU!"=="N" goto step2
echo  Please enter Y or N.
goto ask_startmenu

:: --- Step 2: Desktop ---
:step2
cls
echo ============================================================
echo   STEP 2 of 3 - Desktop Shortcut
echo ============================================================
echo.
echo  Would you like to add a MonitorGuard shortcut
echo  to your Desktop?
echo.
set "ADD_DESKTOP="
:ask_desktop
set /p "ADD_DESKTOP=  Add to Desktop? [Y/N]: "
if /i "!ADD_DESKTOP!"=="Y" goto step3
if /i "!ADD_DESKTOP!"=="N" goto step3
echo  Please enter Y or N.
goto ask_desktop

:: --- Step 3: Taskbar ---
:step3
cls
echo ============================================================
echo   STEP 3 of 3 - Taskbar
echo ============================================================
echo.
echo  Would you like to pin MonitorGuard to the Taskbar?
echo.
echo  Note: A launcher .exe will be created so that Windows
echo  allows you to pin it. Brief manual steps will be shown
echo  at the end of installation.
echo.
set "ADD_TASKBAR="
:ask_taskbar
set /p "ADD_TASKBAR=  Pin to Taskbar? [Y/N]: "
if /i "!ADD_TASKBAR!"=="Y" goto confirm
if /i "!ADD_TASKBAR!"=="N" goto confirm
echo  Please enter Y or N.
goto ask_taskbar

:: --- Summary ---
:confirm
cls
echo ============================================================
echo   Installation Summary
echo ============================================================
echo.
echo  Install directory : %INSTALL_DIR%
echo.
if /i "!ADD_STARTMENU!"=="Y" (
    echo  [x] Add to Start Menu
) else (
    echo  [ ] Add to Start Menu
)
if /i "!ADD_DESKTOP!"=="Y" (
    echo  [x] Add Desktop shortcut
) else (
    echo  [ ] Add Desktop shortcut
)
if /i "!ADD_TASKBAR!"=="Y" (
    echo  [x] Pin to Taskbar ^(manual steps will be shown^)
) else (
    echo  [ ] Pin to Taskbar
)
echo.
echo ============================================================
echo.
set "CONFIRM="
:ask_confirm
set /p "CONFIRM=  Proceed with installation? [Y/N]: "
if /i "!CONFIRM!"=="Y" goto install
if /i "!CONFIRM!"=="N" (
    echo.
    echo  Installation cancelled.
    pause
    exit /b 0
)
echo  Please enter Y or N.
goto ask_confirm

:: --- Installation ---
:install
cls
echo ============================================================
echo   Installing MonitorGuard...
echo ============================================================
echo.

echo  [1/5] Creating directories...
if not exist "%INSTALL_DIR%\" mkdir "%INSTALL_DIR%"
if not exist "%STARTMENU_FOLDER%\" mkdir "%STARTMENU_FOLDER%"
if %errorlevel% neq 0 (
    echo  ERROR: Failed to create directories.
    pause
    exit /b 1
)
echo        Done.

echo  [2/5] Downloading MonitorGuard.bat...
if not exist "%LOCAL_PATH%" (
    powershell -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_PATH%'"
    if %errorlevel% neq 0 (
        echo  ERROR: Download failed. Check your internet connection or URL.
        pause
        exit /b 1
    )
) else (
    echo        File already exists, skipping download.
)
echo        Done.

echo  [3/5] Downloading icon...
if not exist "%ICON_PATH%" (
    powershell -Command "Invoke-WebRequest -Uri '%ICON_URL%' -OutFile '%ICON_PATH%'"
    if %errorlevel% neq 0 (
        echo        WARNING: Icon download failed. Shortcuts will use default icon.
        set "ICON_PATH="
    ) else (
        echo        Done.
    )
) else (
    echo        Icon already exists, skipping download.
)

echo  [4/5] Creating launcher executable...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$src = 'using System; using System.Diagnostics; using System.Reflection;' +" ^
    "'public class Launcher {' +" ^
    "'    public static void Main() {' +" ^
    "'        string dir = System.IO.Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);' +" ^
    "'        string bat = System.IO.Path.Combine(dir, \"MonitorGuard.bat\");' +" ^
    "'        ProcessStartInfo p = new ProcessStartInfo();' +" ^
    "'        p.FileName = \"cmd.exe\";' +" ^
    "'        p.Arguments = \"/c \\\"\" + bat + \"\\\"\";' +" ^
    "'        p.UseShellExecute = true;' +" ^
    "'        Process.Start(p);' +" ^
    "'    }' +" ^
    "'}' ;" ^
    "Add-Type -TypeDefinition $src -OutputAssembly '%EXE_PATH%' -OutputType ConsoleApplication -ReferencedAssemblies 'System.dll';"
if %errorlevel% neq 0 (
    echo  ERROR: Failed to create launcher executable.
    pause
    exit /b 1
)

:: Wait for exe to be fully written to disk before proceeding
:wait_exe
if not exist "%EXE_PATH%" (
    timeout /t 1 /nobreak >nul
    goto wait_exe
)
echo        Done.

echo  [5/5] Creating shortcuts...

set "PS_ICON="
if defined ICON_PATH (
    set "PS_ICON=$Shortcut.IconLocation = '%ICON_PATH%';"
)

if /i "!ADD_STARTMENU!"=="Y" (
    if exist "%SHORTCUT_PATH%" del "%SHORTCUT_PATH%"
    powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%SHORTCUT_PATH%'); $Shortcut.TargetPath = '%EXE_PATH%'; $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; !PS_ICON! $Shortcut.Save()"
    echo        Start Menu shortcut created.
)

if /i "!ADD_DESKTOP!"=="Y" (
    if exist "%DESKTOP_PATH%" del "%DESKTOP_PATH%"
    powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%DESKTOP_PATH%'); $Shortcut.TargetPath = '%EXE_PATH%'; $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; !PS_ICON! $Shortcut.Save()"
    echo        Desktop shortcut created.
)

echo        Done.
echo.

:: --- Completion ---
cls
echo ============================================================
echo   Installation Complete!
echo ============================================================
echo.
echo  MonitorGuard has been installed to:
echo  %INSTALL_DIR%
echo.

if /i "!ADD_STARTMENU!"=="Y" (
    echo  START MENU
    echo  - MonitorGuard is now listed under All Apps.
    echo  - To pin it to Start favorites, right-click it
    echo    in All Apps and select "Pin to Start".
    echo.
)

if /i "!ADD_DESKTOP!"=="Y" (
    echo  DESKTOP
    echo  - A shortcut has been placed on your Desktop.
    echo.
)

if /i "!ADD_TASKBAR!"=="Y" (
    echo  TASKBAR - Manual steps required:
    echo  -------------------------------------------------------
    echo  1. Press the Windows key and type "MonitorGuard"
    echo  2. Right-click MonitorGuard in the search results
    echo  3. Select "Pin to taskbar"
    echo  -------------------------------------------------------
    echo.
)

echo ============================================================
echo.
pause