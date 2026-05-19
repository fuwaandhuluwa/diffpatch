@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  One-Click Restore Tool (supports both MSI mode & directory mode)
::  old_version + update.hdiff -> new_version
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "PATCH_FILE=update.hdiff"
set "HPATCHZ=hpatchz.exe"
set "OUTPUT_DIR=new_version"
set "TEMP_DIR=temp"
set "MSI_MODE=0"

echo ============================================
echo   One-Click Restore Tool
echo   ( old_version + update.hdiff -^> new_version )
echo ============================================
echo.

if not exist "%HPATCHZ%" goto :ERR_NO_HPATCHZ
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%PATCH_FILE%" goto :ERR_NO_PATCH

:: ---- Detect MSI mode ----
if exist "new_installer.msi" (
    set "OLD_MSI_COUNT=0"
    for %%F in ("%OLD_DIR%\*.msi") do (
        set /a OLD_MSI_COUNT+=1
        set "OLD_MSI=%%~fF"
        set "OLD_MSI_NAME=%%~nxF"
    )
    if "!OLD_MSI_COUNT!"=="1" (
        set "MSI_MODE=1"
        echo [INFO] MSI mode detected!
        echo        Old MSI: !OLD_MSI_NAME!
        echo        Thin new MSI: new_installer.msi
        echo.
    )
)

if "%MSI_MODE%"=="0" goto :DIR_MODE

:: ============================================================
::  MSI MODE
:: ============================================================

echo [1/3] Extracting old MSI via admin install...
if exist "%TEMP_DIR%\old_payload" rd /s /q "%TEMP_DIR%\old_payload"
mkdir "%TEMP_DIR%\old_payload" 2>nul

set "ABS_OLD_PAYLOAD=%CD%\%TEMP_DIR%\old_payload"

msiexec /a "!OLD_MSI!" /qb TARGETDIR="!ABS_OLD_PAYLOAD!"
if errorlevel 1 goto :ERR_MSI_EXTRACT

:: Delete .msi files from old_payload (they were not part of the diff)
for /r "%TEMP_DIR%\old_payload" %%F in (*.msi) do del /f /q "%%F"

echo [2/3] Applying patch to restore new payload...
if exist "%TEMP_DIR%\new_payload" rd /s /q "%TEMP_DIR%\new_payload"

"%HPATCHZ%" "%TEMP_DIR%\old_payload" "%PATCH_FILE%" "%TEMP_DIR%\new_payload"
if errorlevel 1 goto :ERR_RESTORE

:: Clean up old_payload
rd /s /q "%TEMP_DIR%\old_payload" 2>nul

echo [3/3] Preparing installable directory...

:: Create output directory with payload + thin MSI
if exist "%OUTPUT_DIR%" (
    echo [WARN] %OUTPUT_DIR% already exists. It will be cleared.
    echo        Press any key to continue restore SW 
    pause >nul
    rd /s /q "%OUTPUT_DIR%"
)

:: Move payload to output dir
move "%TEMP_DIR%\new_payload" "%OUTPUT_DIR%" >nul

:: Copy thin MSI into the output directory
copy /y "new_installer.msi" "%OUTPUT_DIR%\" >nul

echo.
echo ============================================
echo   [MSI MODE] Restore completed successfully!
echo ============================================
echo.
echo   Restored to: %OUTPUT_DIR%\
echo.
echo   To install, run:
echo     msiexec /i "%OUTPUT_DIR%\new_installer.msi" /passive
echo.
echo   Or double-click the MSI file in the restored directory.
echo ============================================

popd
pause
endlocal
exit /b 0


:: ============================================================
::  DIRECTORY MODE (original logic)
:: ============================================================
:DIR_MODE
echo [INFO] Directory mode (no MSI detected).
echo.

if exist "%OUTPUT_DIR%\" (
    echo [WARN] new_version directory already exists: %OUTPUT_DIR%
    echo        It will be cleared and re-restored.
    echo        Press any key to continue restore SW 
    pause >nul
    rd /s /q "%OUTPUT_DIR%"
)

echo [1/2] Restoring new_version from diff patch...
echo       OLD: %OLD_DIR%
echo       PATCH: %PATCH_FILE%
echo       OUT: %OUTPUT_DIR%
echo.

"%HPATCHZ%" "%OLD_DIR%" "%PATCH_FILE%" "%OUTPUT_DIR%"
if errorlevel 1 goto :ERR_RESTORE

echo.
echo [2/2] Restore completed successfully!
echo.
echo ============================================
echo   new_version restored to: %OUTPUT_DIR%
echo   Enter the directory to perform manual installation steps.
echo ============================================
echo.
popd
pause
endlocal
exit /b 0


:: ============================================================
::  ERROR HANDLERS
:: ============================================================
:ERR_NO_HPATCHZ
echo [ERROR] hpatchz.exe not found.
echo         Ensure hpatchz.exe is in the same directory as this script.
popd & pause & endlocal
exit /b 1

:ERR_NO_OLD
echo [ERROR] Old version directory not found: %OLD_DIR%
popd & pause & endlocal
exit /b 1

:ERR_NO_PATCH
echo [ERROR] Patch file not found: %PATCH_FILE%
popd & pause & endlocal
exit /b 1

:ERR_RESTORE
echo.
echo [ERROR] Restore failed! Check if files are intact or contact support.
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
popd & pause & endlocal
exit /b 1

:ERR_MSI_EXTRACT
echo.
echo [ERROR] MSI admin install extraction failed!
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
popd & pause & endlocal
exit /b 1
