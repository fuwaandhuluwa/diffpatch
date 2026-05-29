@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  Multi-Mode Patch Verification Tool
::  Reads patches from output/ directory, simulates restore,
::  and SHA256-compares results against original new_version
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "NEW_DIR=new_version"
set "HPATCHZ=hpatchz.exe"
set "TEMP_DIR=temp"
set "OUT_DIR=output"
set "PASS_COUNT=0"
set "FAIL_COUNT=0"
set "TOTAL=0"

echo ============================================
echo   Multi-Mode Patch Verification Tool
echo   Simulates restore and compares SHA256
echo ============================================
echo.

if not exist "%HPATCHZ%" goto :ERR_NO_HPATCHZ
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW
if not exist "%OUT_DIR%\" goto :ERR_NO_OUTPUT

REM Check at least one .hdiff exists in output
set "ANY_PATCH=0"
for %%F in ("%OUT_DIR%\*.hdiff") do set "ANY_PATCH=1"
if "%ANY_PATCH%"=="0" goto :ERR_NO_PATCH

REM Prepare temp
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%" 2>nul

:: ============================================================
::  Phase 1: Verify MSI patches (update_msi_*.hdiff)
:: ============================================================
echo [Phase 1] Verifying MSI patches...
echo.

REM Collect old MSIs sorted
set "OLD_MSI_IDX=0"
for /f "delims=" %%F in ('dir /b /on "%OLD_DIR%\*.msi" 2^>nul') do (
    set /a OLD_MSI_IDX+=1
    set "OLD_MSI_!OLD_MSI_IDX!=%%F"
    set "OLD_MSI_BASE_!OLD_MSI_IDX!=%%~nF"
)

REM Collect new MSIs sorted
set "NEW_MSI_IDX=0"
for /f "delims=" %%F in ('dir /b /on "%NEW_DIR%\*.msi" 2^>nul') do (
    set /a NEW_MSI_IDX+=1
    set "NEW_MSI_!NEW_MSI_IDX!=%%F"
    set "NEW_MSI_BASE_!NEW_MSI_IDX!=%%~nF"
)

REM Determine pair count
set "PAIR_COUNT=%OLD_MSI_IDX%"
if %NEW_MSI_IDX% LSS %OLD_MSI_IDX% set "PAIR_COUNT=%NEW_MSI_IDX%"

if "%PAIR_COUNT%"=="0" (
    echo    No MSI files to verify.
    goto :PHASE2
)

for /l %%I in (1,1,%PAIR_COUNT%) do (
    set "CUR_OLD_MSI=!OLD_MSI_%%I!"
    set "CUR_NEW_MSI=!NEW_MSI_%%I!"
    set "CUR_OLD_BASE=!OLD_MSI_BASE_%%I!"
    set "CUR_NEW_BASE=!NEW_MSI_BASE_%%I!"
    if exist "%OUT_DIR%\update_msi_!CUR_OLD_BASE!_TO_!CUR_NEW_BASE!.hdiff" (
        set /a TOTAL+=1
        echo -- Verifying MSI pair %%I: !CUR_OLD_MSI! -^> !CUR_NEW_MSI!
        call :VERIFY_MSI "!CUR_OLD_MSI!" "!CUR_NEW_MSI!" "!CUR_OLD_BASE!" "!CUR_NEW_BASE!"
    )
)
echo.

:PHASE2
:: ============================================================
::  Phase 2: Verify directory patch (update_dir.hdiff)
:: ============================================================
if not exist "%OUT_DIR%\update_dir.hdiff" (
    echo [Phase 2] No directory patch found, skipping.
    echo.
    goto :SUMMARY
)

echo [Phase 2] Verifying directory patch...
echo.
set /a TOTAL+=1

REM Build expected: copy new_version, remove .msi
if exist "%TEMP_DIR%\dir_expected" rd /s /q "%TEMP_DIR%\dir_expected"
mkdir "%TEMP_DIR%\dir_expected" 2>nul
robocopy "%NEW_DIR%" "%TEMP_DIR%\dir_expected" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
for %%F in ("%TEMP_DIR%\dir_expected\*.msi") do del /f /q "%%F" 2>nul

REM Build old base: copy old_version, remove .msi
if exist "%TEMP_DIR%\dir_old" rd /s /q "%TEMP_DIR%\dir_old"
mkdir "%TEMP_DIR%\dir_old" 2>nul
robocopy "%OLD_DIR%" "%TEMP_DIR%\dir_old" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
for %%F in ("%TEMP_DIR%\dir_old\*.msi") do del /f /q "%%F" 2>nul

REM Apply patch
echo    Applying directory patch...
if exist "%TEMP_DIR%\dir_restored" rd /s /q "%TEMP_DIR%\dir_restored"
"%HPATCHZ%" "%TEMP_DIR%\dir_old" "%OUT_DIR%\update_dir.hdiff" "%TEMP_DIR%\dir_restored"
if errorlevel 1 (
    echo    [FAIL] Directory patch apply failed!
    set /a FAIL_COUNT+=1
    goto :DIR_CLEANUP
)

echo    Comparing restored vs expected (SHA256)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_compare_dirs.ps1" "%TEMP_DIR%\dir_restored" "%TEMP_DIR%\dir_expected"
if errorlevel 1 (
    echo    [FAIL] Directory patch verification failed!
    set /a FAIL_COUNT+=1
) else (
    echo    [PASS] Directory patch verified.
    set /a PASS_COUNT+=1
)

:DIR_CLEANUP
rd /s /q "%TEMP_DIR%\dir_old" 2>nul
rd /s /q "%TEMP_DIR%\dir_expected" 2>nul
rd /s /q "%TEMP_DIR%\dir_restored" 2>nul
echo.

:SUMMARY
:: ============================================================
::  Summary
:: ============================================================
rd /s /q "%TEMP_DIR%" 2>nul

echo ============================================
if "%FAIL_COUNT%"=="0" (
    echo   Verification PASSED  [%PASS_COUNT%/%TOTAL% patches verified]
    echo   Safe to deliver.
) else (
    echo   Verification FAILED  [%FAIL_COUNT%/%TOTAL% patches failed]
    echo   Do NOT deliver this patch.
)
echo ============================================

set "EXIT_CODE=0"
if not "%FAIL_COUNT%"=="0" set "EXIT_CODE=1"

popd
pause
endlocal & exit /b %EXIT_CODE%


:: ============================================================
::  SUBROUTINE: Verify a single MSI patch
::  %1 = old MSI filename, %2 = new MSI filename
::  %3 = old base name, %4 = new base name
:: ============================================================
:VERIFY_MSI
set "VMSI_OLD=%~1"
set "VMSI_NEW=%~2"
set "VMSI_OLD_BASE=%~3"
set "VMSI_NEW_BASE=%~4"

REM Extract old MSI payload
echo    Extracting old MSI: %VMSI_OLD%
if exist "%TEMP_DIR%\v_msi_old" rd /s /q "%TEMP_DIR%\v_msi_old"
mkdir "%TEMP_DIR%\v_msi_old" 2>nul
set "ABS_V_OLD=%CD%\%OLD_DIR%\%VMSI_OLD%"
set "ABS_V_OLD_PAY=%CD%\%TEMP_DIR%\v_msi_old"
msiexec /a "!ABS_V_OLD!" /qb TARGETDIR="!ABS_V_OLD_PAY!"
if errorlevel 1 (
    echo    [FAIL] Old MSI extraction failed: %VMSI_OLD%
    set /a FAIL_COUNT+=1
    goto :VERIFY_MSI_CLEANUP
)
for /r "%TEMP_DIR%\v_msi_old" %%M in (*.msi) do del /f /q "%%M"

REM Apply patch to get restored payload
echo    Applying patch: update_msi_%VMSI_OLD_BASE%_TO_%VMSI_NEW_BASE%.hdiff
if exist "%TEMP_DIR%\v_msi_restored" rd /s /q "%TEMP_DIR%\v_msi_restored"
"%HPATCHZ%" "%TEMP_DIR%\v_msi_old" "%OUT_DIR%\update_msi_%VMSI_OLD_BASE%_TO_%VMSI_NEW_BASE%.hdiff" "%TEMP_DIR%\v_msi_restored"
if errorlevel 1 (
    echo    [FAIL] Patch apply failed: update_msi_%VMSI_OLD_BASE%_TO_%VMSI_NEW_BASE%.hdiff
    set /a FAIL_COUNT+=1
    goto :VERIFY_MSI_CLEANUP
)

REM Extract new MSI payload (expected)
echo    Extracting new MSI: %VMSI_NEW%
if exist "%TEMP_DIR%\v_msi_expected" rd /s /q "%TEMP_DIR%\v_msi_expected"
mkdir "%TEMP_DIR%\v_msi_expected" 2>nul
set "ABS_V_NEW=%CD%\%NEW_DIR%\%VMSI_NEW%"
set "ABS_V_NEW_PAY=%CD%\%TEMP_DIR%\v_msi_expected"
msiexec /a "!ABS_V_NEW!" /qb TARGETDIR="!ABS_V_NEW_PAY!"
if errorlevel 1 (
    echo    [FAIL] New MSI extraction failed: %VMSI_NEW%
    set /a FAIL_COUNT+=1
    goto :VERIFY_MSI_CLEANUP
)
for /r "%TEMP_DIR%\v_msi_expected" %%M in (*.msi) do del /f /q "%%M"

REM SHA256 compare
echo    Comparing restored vs expected (SHA256)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_compare_dirs.ps1" "%TEMP_DIR%\v_msi_restored" "%TEMP_DIR%\v_msi_expected"
if errorlevel 1 (
    echo    [FAIL] MSI patch verification failed: %VMSI_OLD_BASE% -^> %VMSI_NEW_BASE%
    set /a FAIL_COUNT+=1
) else (
    echo    [PASS] MSI patch verified: %VMSI_OLD_BASE% -^> %VMSI_NEW_BASE%
    set /a PASS_COUNT+=1
)

:VERIFY_MSI_CLEANUP
rd /s /q "%TEMP_DIR%\v_msi_old" 2>nul
rd /s /q "%TEMP_DIR%\v_msi_restored" 2>nul
rd /s /q "%TEMP_DIR%\v_msi_expected" 2>nul
exit /b 0


:: ============================================================
::  ERROR HANDLERS
:: ============================================================
:ERR_NO_HPATCHZ
echo [ERROR] hpatchz.exe not found.
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

:ERR_NO_OUTPUT
echo [ERROR] Output directory not found: %OUT_DIR%
echo         Run make_patch.bat first.
popd & pause & endlocal
exit /b 1

:ERR_NO_PATCH
echo [ERROR] No .hdiff patch files found in %OUT_DIR%
echo         Run make_patch.bat first.
popd & pause & endlocal
exit /b 1
