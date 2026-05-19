@echo off
setlocal EnableExtensions

:: Restore new_version from old_version + patch

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "PATCH_FILE=update.hdiff"
set "HPATCHZ=hpatchz.exe"
set "OUTPUT_DIR=new_version"

echo ============================================
echo   One-Click Restore Tool
echo   ( old_version + update.hdiff -^> new_version )
echo ============================================
echo.

if not exist "%HPATCHZ%" goto :ERR_NO_HPATCHZ
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%PATCH_FILE%" goto :ERR_NO_PATCH

if exist "%OUTPUT_DIR%\" (
    echo [WARN] new_version directory already exists: %OUTPUT_DIR%
    echo        It will be cleared and re-restored.
    echo        Press any key to continue or close the window to cancel...
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
popd & pause & endlocal
exit /b 1