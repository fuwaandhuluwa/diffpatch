@echo off
setlocal EnableExtensions

:: Make diff patch: old_version -> new_version

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "NEW_DIR=new_version"
set "PATCH_FILE=update.hdiff"
set "HDIFFZ=hdiffz.exe"

echo ============================================
echo   Diff Patch Maker
echo   ( old_version -^> new_version )
echo ============================================
echo.

if not exist "%HDIFFZ%" (
    where hdiffz.exe >nul 2>nul
    if errorlevel 1 goto :ERR_NO_HDIFFZ
    set "HDIFFZ=hdiffz.exe"
)

if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW

echo [1/3] Checking differences between old_version and new_version (SHA256)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src=(Resolve-Path '%OLD_DIR%').Path; $dst=(Resolve-Path '%NEW_DIR%').Path;" ^
  "$a = Get-ChildItem $src -Recurse -File | ForEach-Object { [PSCustomObject]@{ Rel=$_.FullName.Substring($src.Length).TrimStart('\'); Hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | Sort-Object Rel;" ^
  "$b = Get-ChildItem $dst -Recurse -File | ForEach-Object { [PSCustomObject]@{ Rel=$_.FullName.Substring($dst.Length).TrimStart('\'); Hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | Sort-Object Rel;" ^
  "$diff = Compare-Object $a $b -Property Rel,Hash;" ^
  "if (-not $diff) { exit 2 }" ^
  "$ah = @{}; foreach ($x in $a) { $ah[$x.Rel] = $x.Hash };" ^
  "$bh = @{}; foreach ($x in $b) { $bh[$x.Rel] = $x.Hash };" ^
  "$rels = ($ah.Keys + $bh.Keys) | Sort-Object -Unique;" ^
  "$rows = foreach ($r in $rels) {" ^
  "  if (-not $ah.ContainsKey($r)) { [PSCustomObject]@{ Change='[NEW]'; File=$r } }" ^
  "  elseif (-not $bh.ContainsKey($r)) { [PSCustomObject]@{ Change='[DEL]'; File=$r } }" ^
  "  elseif ($ah[$r] -ne $bh[$r]) { [PSCustomObject]@{ Change='[MOD]'; File=$r } }" ^
  "};" ^
  "Write-Host ('       Changed files: ' + $rows.Count);" ^
  "$rows | Format-Table -AutoSize | Out-String | Write-Host;" ^
  "exit 0"

if errorlevel 2 goto :NO_CHANGE
if errorlevel 1 goto :ERR_COMPARE

if exist "%PATCH_FILE%" (
    echo [INFO] Deleting old patch file...
    del /f /q "%PATCH_FILE%"
)

echo [2/3] Creating diff patch (-m-2 max compression)...
echo       OLD: %OLD_DIR%
echo       NEW: %NEW_DIR%
echo       OUT: %PATCH_FILE%
echo.

"%HDIFFZ%" -m-2 "%OLD_DIR%" "%NEW_DIR%" "%PATCH_FILE%"
if errorlevel 1 goto :ERR_DIFF

echo.
echo [3/3] Patch created successfully!
for %%A in ("%PATCH_FILE%") do echo       Patch size: %%~zA bytes
echo.
echo ============================================
echo   Next step: run verify_patch.bat to verify
echo ============================================
popd
pause
endlocal
exit /b 0


:NO_CHANGE
echo.
echo ============================================
echo   [INFO] old_version and new_version are identical.
echo          No patch needed. No upgrade required.
echo ============================================
if exist "%PATCH_FILE%" echo [NOTE] Existing old patch file kept: %PATCH_FILE%
popd
pause
endlocal
exit /b 0


:ERR_NO_HDIFFZ
echo [ERROR] hdiffz.exe not found.
echo         Place hdiffz.exe in the same directory as this script or add to PATH.
echo         Download: https://github.com/sisong/HDiffPatch/releases
popd & pause & endlocal
exit /b 1


:ERR_NO_OLD
echo [ERROR] Old version directory not found: %OLD_DIR%
popd & pause & endlocal
exit /b 1


:ERR_NO_NEW
echo [ERROR] New version directory not found: %NEW_DIR%
popd & pause & endlocal
exit /b 1


:ERR_COMPARE
echo [ERROR] Directory comparison failed. Check if PowerShell is available.
popd & pause & endlocal
exit /b 1


:ERR_DIFF
echo.
echo [ERROR] Diff patch creation failed!
popd & pause & endlocal
exit /b 1