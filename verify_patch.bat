@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  Verify Patch (supports both MSI mode & directory mode)
::  Simulates the full restore flow and SHA256 compares results
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "NEW_DIR=new_version"
set "PATCH_FILE=update.hdiff"
set "HPATCHZ=hpatchz.exe"
set "VERIFY_DIR=new_version_verify"
set "TEMP_DIR=temp"
set "MSI_MODE=0"

echo ============================================
echo   Patch Verification Tool
echo   Simulates restore and compares SHA256
echo ============================================
echo.

if not exist "%HPATCHZ%" goto :ERR_NO_HPATCHZ
if not exist "%PATCH_FILE%" goto :ERR_NO_PATCH
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW

:: ---- Detect MSI mode ----
if exist "new_installer.msi" (
    set "OLD_MSI_COUNT=0"
    for %%F in ("%OLD_DIR%\*.msi") do (
        set /a OLD_MSI_COUNT+=1
        set "OLD_MSI=%%~fF"
    )
    set "NEW_MSI_COUNT=0"
    for %%F in ("%NEW_DIR%\*.msi") do (
        set /a NEW_MSI_COUNT+=1
        set "NEW_MSI=%%~fF"
    )
    if "!OLD_MSI_COUNT!"=="1" if "!NEW_MSI_COUNT!"=="1" (
        set "MSI_MODE=1"
        echo [INFO] MSI mode detected. Will verify payload-level consistency.
        echo.
    )
)

if "%MSI_MODE%"=="0" goto :DIR_VERIFY

:: ============================================================
::  MSI MODE VERIFICATION
:: ============================================================

:: Step 1: Extract old MSI -> apply patch -> get "restored" payload
echo [1/4] Extracting old MSI payload...
if exist "%TEMP_DIR%\verify_old" rd /s /q "%TEMP_DIR%\verify_old"
mkdir "%TEMP_DIR%\verify_old" 2>nul
set "ABS_VERIFY_OLD=%CD%\%TEMP_DIR%\verify_old"
msiexec /a "!OLD_MSI!" /qb TARGETDIR="!ABS_VERIFY_OLD!"
if errorlevel 1 goto :ERR_MSI_EXTRACT

for /r "%TEMP_DIR%\verify_old" %%F in (*.msi) do del /f /q "%%F"

echo [2/4] Applying patch to get restored payload...
if exist "%TEMP_DIR%\verify_restored" rd /s /q "%TEMP_DIR%\verify_restored"
"%HPATCHZ%" "%TEMP_DIR%\verify_old" "%PATCH_FILE%" "%TEMP_DIR%\verify_restored"
if errorlevel 1 goto :ERR_VERIFY_PATCH

:: Step 2: Extract new MSI -> get "expected" payload
echo [3/4] Extracting new MSI payload (expected)...
if exist "%TEMP_DIR%\verify_expected" rd /s /q "%TEMP_DIR%\verify_expected"
mkdir "%TEMP_DIR%\verify_expected" 2>nul
set "ABS_VERIFY_EXPECTED=%CD%\%TEMP_DIR%\verify_expected"
msiexec /a "!NEW_MSI!" /qb TARGETDIR="!ABS_VERIFY_EXPECTED!"
if errorlevel 1 goto :ERR_MSI_EXTRACT

for /r "%TEMP_DIR%\verify_expected" %%F in (*.msi) do del /f /q "%%F"

:: Step 3: SHA256 compare via external script
echo [4/4] Comparing restored payload vs expected payload (SHA256)...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_compare_dirs.ps1" "%TEMP_DIR%\verify_restored" "%TEMP_DIR%\verify_expected"

set "VERIFY_RESULT=%ERRORLEVEL%"

:: Clean up
rd /s /q "%TEMP_DIR%\verify_old" 2>nul
rd /s /q "%TEMP_DIR%\verify_restored" 2>nul
rd /s /q "%TEMP_DIR%\verify_expected" 2>nul

if "%VERIFY_RESULT%"=="0" (
    echo.
    echo ============================================
    echo   Verification PASSED. Safe to deliver.
    echo ============================================
) else (
    echo.
    echo ============================================
    echo   Verification FAILED!
    echo   Do NOT deliver this patch.
    echo ============================================
)

popd
pause
endlocal
exit /b %VERIFY_RESULT%


:: ============================================================
::  DIRECTORY MODE VERIFICATION (original logic)
:: ============================================================
:DIR_VERIFY
echo [INFO] Directory mode verification.
echo.

if exist "%VERIFY_DIR%" rd /s /q "%VERIFY_DIR%"

echo [1/2] Restoring from patch...
"%HPATCHZ%" "%OLD_DIR%" "%PATCH_FILE%" "%VERIFY_DIR%"
if errorlevel 1 goto :ERR_VERIFY_PATCH

echo [2/2] Comparing restored vs original new_version (SHA256)...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_compare_dirs.ps1" "%VERIFY_DIR%" "%NEW_DIR%"

set "VERIFY_RESULT=%ERRORLEVEL%"

if "%VERIFY_RESULT%"=="0" (
    rd /s /q "%VERIFY_DIR%" 2>nul
    echo.
    echo ============================================
    echo   Verification PASSED. Safe to deliver.
    echo ============================================
) else (
    echo.
    echo   Verify directory kept for inspection: %VERIFY_DIR%
    echo ============================================
    echo   Verification FAILED!
    echo ============================================
)

popd
pause
endlocal
exit /b %VERIFY_RESULT%


:: ============================================================
::  ERROR HANDLERS
:: ============================================================
:ERR_NO_HPATCHZ
echo [ERROR] hpatchz.exe not found.
popd & pause & endlocal
exit /b 1

:ERR_NO_PATCH
echo [ERROR] Patch file not found: %PATCH_FILE%
echo         Run make_patch.bat first.
popd & pause & endlocal
exit /b 1

:ERR_NO_OLD
echo [ERROR] Old version directory not found: %OLD_DIR%
popd & pause & endlocal
exit /b 1

:ERR_NO_NEW
echo [ERROR] New version directory not found: %NEW_DIR%
echo         Need original new_version for verification.
popd & pause & endlocal
exit /b 1

:ERR_MSI_EXTRACT
echo [ERROR] MSI extraction failed!
rd /s /q "%TEMP_DIR%\verify_old" 2>nul
rd /s /q "%TEMP_DIR%\verify_expected" 2>nul
popd & pause & endlocal
exit /b 1

:ERR_VERIFY_PATCH
echo [ERROR] Patch restore failed during verification!
rd /s /q "%TEMP_DIR%\verify_old" 2>nul
popd & pause & endlocal
exit /b 1
