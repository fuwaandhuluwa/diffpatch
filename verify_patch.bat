@echo off
setlocal EnableExtensions

:: Verify diff patch correctness

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

echo ============================================
echo   Patch Verification Tool
echo ============================================
echo.

if not exist "%HPATCHZ%" (
    where hpatchz.exe >nul 2>nul
    if errorlevel 1 goto :ERR_NO_HPATCHZ
    set "HPATCHZ=hpatchz.exe"
)

if not exist "%PATCH_FILE%" goto :ERR_NO_PATCH
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW

:: cleanup leftover dir or file
if exist "%VERIFY_DIR%\" (
    echo [INFO] Cleaning up leftover verify dir: %VERIFY_DIR% ...
    rd /s /q "%VERIFY_DIR%" 2>nul
) else if exist "%VERIFY_DIR%" (
    echo [INFO] Removing leftover file: %VERIFY_DIR% ...
    del /f /q "%VERIFY_DIR%" 2>nul
)
if exist "%VERIFY_DIR%" goto :ERR_CLEANUP

echo [1/2] Restoring %VERIFY_DIR% from patch...
echo       (output dir is created automatically by the script)
"%HPATCHZ%" "%OLD_DIR%" "%PATCH_FILE%" "%VERIFY_DIR%"
if errorlevel 1 goto :ERR_PATCH

echo.
echo [2/2] Comparing SHA256 of %VERIFY_DIR% vs %NEW_DIR% ...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src=(Resolve-Path '%NEW_DIR%').Path; $dst=(Resolve-Path '%VERIFY_DIR%').Path;" ^
  "$a = Get-ChildItem $src -Recurse -File | ForEach-Object { [PSCustomObject]@{ Rel=$_.FullName.Substring($src.Length).TrimStart('\'); Hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | Sort-Object Rel;" ^
  "$b = Get-ChildItem $dst -Recurse -File | ForEach-Object { [PSCustomObject]@{ Rel=$_.FullName.Substring($dst.Length).TrimStart('\'); Hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | Sort-Object Rel;" ^
  "$a | Format-Table -AutoSize | Out-String | Write-Host;" ^
  "$diff = Compare-Object $a $b -Property Rel,Hash;" ^
  "if ($diff) { Write-Host '[FAIL] File differences detected:' -ForegroundColor Red; $diff | Format-Table | Out-String | Write-Host; exit 1 }" ^
  "else { Write-Host '[OK] All files SHA256 match' -ForegroundColor Green; exit 0 }"

if errorlevel 1 goto :VERIFY_FAIL
echo.
echo ============================================
echo   [OK] Patch verification passed!
echo   Deliverables:
echo     - old_version\
echo     - hpatchz.exe
echo     - update.hdiff
echo     - restore.bat
echo ============================================
rd /s /q "%VERIFY_DIR%" 2>nul
popd
pause
endlocal
exit /b 0


:VERIFY_FAIL
echo.
echo ============================================
echo   [FAIL] Verification failed. Diff dir kept: %VERIFY_DIR%
echo ============================================
popd & pause & endlocal
exit /b 1


:ERR_NO_HPATCHZ
echo [ERROR] hpatchz.exe not found. Place it in the script directory or add to PATH.
popd & pause & endlocal
exit /b 1


:ERR_NO_PATCH
echo [ERROR] Patch file %PATCH_FILE% not found. Run make_patch.bat first.
popd & pause & endlocal
exit /b 1


:ERR_NO_OLD
echo [ERROR] Old version directory not found: %OLD_DIR%
popd & pause & endlocal
exit /b 1


:ERR_NO_NEW
echo [ERROR] New version directory not found: %NEW_DIR%. Cannot compare.
popd & pause & endlocal
exit /b 1


:ERR_CLEANUP
echo [ERROR] Cannot delete "%VERIFY_DIR%"
echo         Close any program that may be using this path and try again.
popd & pause & endlocal
exit /b 1


:ERR_PATCH
echo.
echo [ERROR] hpatchz restore failed. Check if old_version / update.hdiff match.
popd & pause & endlocal
exit /b 1