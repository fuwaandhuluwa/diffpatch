@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  Diff Patch Maker (supports both MSI mode & directory mode)
::  old_version -> new_version
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "NEW_DIR=new_version"
set "PATCH_FILE=update.hdiff"
set "HDIFFZ=hdiffz.exe"
set "TEMP_DIR=temp"
set "MSI_MODE=0"
set "OLD_MSI="
set "NEW_MSI="

echo ============================================
echo   Diff Patch Maker
echo   ( old_version -^> new_version )
echo ============================================
echo.

:: ---- Check hdiffz ----
if not exist "%HDIFFZ%" (
    where hdiffz.exe >nul 2>nul
    if errorlevel 1 goto :ERR_NO_HDIFFZ
    set "HDIFFZ=hdiffz.exe"
)

if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW

:: ---- Detect MSI mode ----
:: Check if old_version contains exactly one .msi file
set "OLD_MSI_COUNT=0"
for %%F in ("%OLD_DIR%\*.msi") do (
    set /a OLD_MSI_COUNT+=1
    set "OLD_MSI=%%~fF"
    set "OLD_MSI_NAME=%%~nxF"
)
set "NEW_MSI_COUNT=0"
for %%F in ("%NEW_DIR%\*.msi") do (
    set /a NEW_MSI_COUNT+=1
    set "NEW_MSI=%%~fF"
    set "NEW_MSI_NAME=%%~nxF"
)

if "%OLD_MSI_COUNT%"=="1" if "%NEW_MSI_COUNT%"=="1" (
    set "MSI_MODE=1"
    echo [INFO] MSI mode detected!
    echo        Old MSI: %OLD_MSI_NAME%
    echo        New MSI: %NEW_MSI_NAME%
    echo.
)

if "%MSI_MODE%"=="0" goto :DIR_MODE

:: ============================================================
::  MSI MODE
:: ============================================================

echo [1/5] Extracting old MSI via admin install...
if exist "%TEMP_DIR%\old_payload" rd /s /q "%TEMP_DIR%\old_payload"
mkdir "%TEMP_DIR%\old_payload" 2>nul

set "ABS_OLD_MSI=%OLD_MSI%"
set "ABS_OLD_PAYLOAD=%CD%\%TEMP_DIR%\old_payload"

msiexec /a "!ABS_OLD_MSI!" /qb TARGETDIR="!ABS_OLD_PAYLOAD!"
if errorlevel 1 goto :ERR_MSI_EXTRACT

echo [2/5] Extracting new MSI via admin install...
if exist "%TEMP_DIR%\new_payload" rd /s /q "%TEMP_DIR%\new_payload"
mkdir "%TEMP_DIR%\new_payload" 2>nul

set "ABS_NEW_MSI=%NEW_MSI%"
set "ABS_NEW_PAYLOAD=%CD%\%TEMP_DIR%\new_payload"

msiexec /a "!ABS_NEW_MSI!" /qb TARGETDIR="!ABS_NEW_PAYLOAD!"
if errorlevel 1 goto :ERR_MSI_EXTRACT

:: Remove the thin MSI from payload dirs (they must not participate in diff)
:: But save the new thin MSI for delivery
echo [3/5] Preparing payload directories...

:: Find and save the thin MSI from new_payload
set "NEW_THIN_MSI="
for %%F in ("%TEMP_DIR%\new_payload\*.msi") do (
    set "NEW_THIN_MSI=%%~fF"
    set "NEW_THIN_MSI_NAME=%%~nxF"
)
if not defined NEW_THIN_MSI (
    echo [WARN] No thin MSI found in new_payload, searching subdirectories...
    for /r "%TEMP_DIR%\new_payload" %%F in (*.msi) do (
        set "NEW_THIN_MSI=%%~fF"
        set "NEW_THIN_MSI_NAME=%%~nxF"
    )
)
if not defined NEW_THIN_MSI goto :ERR_NO_THIN_MSI

:: Copy thin MSI to root for delivery
copy /y "!NEW_THIN_MSI!" "new_installer.msi" >nul
echo        Saved new thin MSI: new_installer.msi

:: Delete all .msi files from both payload dirs (they vary and must not be diffed)
for /r "%TEMP_DIR%\old_payload" %%F in (*.msi) do del /f /q "%%F"
for /r "%TEMP_DIR%\new_payload" %%F in (*.msi) do del /f /q "%%F"

:: Show payload sizes
echo.
powershell -NoProfile -Command ^
  "$old = (Get-ChildItem '%TEMP_DIR%\old_payload' -Recurse -File | Measure-Object -Property Length -Sum).Sum;" ^
  "$new = (Get-ChildItem '%TEMP_DIR%\new_payload' -Recurse -File | Measure-Object -Property Length -Sum).Sum;" ^
  "Write-Host ('       Old payload: {0:N2} MB' -f ($old/1MB));" ^
  "Write-Host ('       New payload: {0:N2} MB' -f ($new/1MB))"
echo.

:: SHA256 compare payloads
echo [4/5] Checking differences between payloads (SHA256)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src=(Resolve-Path '%TEMP_DIR%\old_payload').Path; $dst=(Resolve-Path '%TEMP_DIR%\new_payload').Path;" ^
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

if errorlevel 2 goto :MSI_NO_CHANGE
if errorlevel 1 goto :ERR_COMPARE

if exist "%PATCH_FILE%" (
    echo [INFO] Deleting old patch file...
    del /f /q "%PATCH_FILE%"
)

echo [5/5] Creating diff patch on payloads (-m-2 max compression)...
echo       OLD: %TEMP_DIR%\old_payload
echo       NEW: %TEMP_DIR%\new_payload
echo       OUT: %PATCH_FILE%
echo.

"%HDIFFZ%" -m-2 "%TEMP_DIR%\old_payload" "%TEMP_DIR%\new_payload" "%PATCH_FILE%"
if errorlevel 1 goto :ERR_DIFF

echo.
echo ============================================
echo   [MSI MODE] Patch created successfully!
echo ============================================

:: Show size comparison
powershell -NoProfile -Command ^
  "$oldMsi = (Get-Item '%OLD_MSI%').Length;" ^
  "$newMsi = (Get-Item '%NEW_MSI%').Length;" ^
  "$patch  = (Get-Item '%PATCH_FILE%').Length;" ^
  "$thin   = (Get-Item 'new_installer.msi').Length;" ^
  "$total  = $patch + $thin;" ^
  "Write-Host '';" ^
  "Write-Host ('  Old MSI size:        {0:N2} MB' -f ($oldMsi/1MB));" ^
  "Write-Host ('  New MSI size:        {0:N2} MB' -f ($newMsi/1MB));" ^
  "Write-Host ('  Patch size:          {0:N2} MB' -f ($patch/1MB));" ^
  "Write-Host ('  Thin MSI size:       {0:N2} MB' -f ($thin/1MB));" ^
  "Write-Host ('  Total delivery:      {0:N2} MB' -f ($total/1MB));" ^
  "Write-Host ('  Compression ratio:   {0:P1}' -f ($total/$newMsi));" ^
  "Write-Host ''"

echo   Delivery package contents:
echo     - old_version\%OLD_MSI_NAME%  (baseline, required)
echo     - update.hdiff                (payload diff)
echo     - new_installer.msi           (thin MSI for install)
echo     - hpatchz.exe
echo     - restore.bat
echo ============================================
echo.
echo   Next step: run verify_patch.bat to verify
echo ============================================

:: Clean up temp
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
rd /s /q "%TEMP_DIR%\new_payload" 2>nul

popd
pause
endlocal
exit /b 0


:MSI_NO_CHANGE
echo.
echo ============================================
echo   [INFO] Old and new MSI payloads are identical.
echo          No patch needed. No upgrade required.
echo ============================================
if exist "%PATCH_FILE%" echo [NOTE] Existing old patch file kept: %PATCH_FILE%
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
rd /s /q "%TEMP_DIR%\new_payload" 2>nul
popd
pause
endlocal
exit /b 0


:: ============================================================
::  DIRECTORY MODE (original logic)
:: ============================================================
:DIR_MODE
echo [INFO] Directory mode (no single MSI detected).
echo.

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

if errorlevel 2 goto :DIR_NO_CHANGE
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


:DIR_NO_CHANGE
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


:: ============================================================
::  ERROR HANDLERS
:: ============================================================
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

:ERR_MSI_EXTRACT
echo.
echo [ERROR] MSI admin install extraction failed!
echo         Check if the MSI file is valid and not corrupted.
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
rd /s /q "%TEMP_DIR%\new_payload" 2>nul
popd & pause & endlocal
exit /b 1

:ERR_NO_THIN_MSI
echo.
echo [ERROR] Could not find thin MSI in extracted payload.
echo         The MSI structure may not be supported.
rd /s /q "%TEMP_DIR%\old_payload" 2>nul
rd /s /q "%TEMP_DIR%\new_payload" 2>nul
popd & pause & endlocal
exit /b 1
