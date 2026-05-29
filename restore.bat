@echo off
setlocal EnableExtensions DisableDelayedExpansion

:: ============================================================
::  Multi-Mode One-Click Restore Tool
::  Auto-detects and applies all .hdiff patches to restore
::  MSI patches paired by sorted order (same as make_patch)
::  Supports update_msi_*_TO_*.hdiff and update_dir.hdiff
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "HPATCHZ=hpatchz.exe"
set "OUTPUT_DIR=new_version"
set "TEMP_DIR=temp"
set "RESTORE_COUNT=0"
set "FAIL_COUNT=0"

echo ============================================
echo   Multi-Mode One-Click Restore Tool
echo ============================================
echo.

if not exist "%HPATCHZ%" goto :ERR_NO_HPATCHZ
if not exist "%OLD_DIR%\" goto :ERR_NO_OLD

REM Check at least one .hdiff exists
set "PATCH_FOUND=0"
for %%F in ("*.hdiff") do set "PATCH_FOUND=1"
if "%PATCH_FOUND%"=="0" goto :ERR_NO_PATCH

REM Show what is in old_version
echo [INFO] Files in old_version:
for %%F in ("%OLD_DIR%\*") do echo        %%~nxF
echo.

REM Ensure output dir exists (empty dir is fine)
if exist "%OUTPUT_DIR%\" (
    rd /s /q "%OUTPUT_DIR%"
)
mkdir "%OUTPUT_DIR%" 2>nul

REM Prepare temp
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%" 2>nul

:: ============================================================
::  Step 1: Process MSI patches (paired by sorted order)
:: ============================================================
echo [Step 1] Processing MSI patches...
echo.

REM Collect MSI patches sorted (use call subroutine for safety)
set "MSI_PATCH_IDX=0"
for /f "delims=" %%F in ('dir /b /on "update_msi_*_TO_*.hdiff" 2^>nul') do call :COLLECT_MSI_PATCH "%%F"

REM Collect old MSIs sorted
set "OLD_MSI_IDX=0"
for /f "delims=" %%F in ('dir /b /on "%OLD_DIR%\*.msi" 2^>nul') do call :COLLECT_OLD_MSI "%%F"

if not "%MSI_PATCH_IDX%"=="0" goto :MSI_HAVE_PATCHES
    echo    No MSI patches found, skipping.
    echo.
    goto :STEP2
:MSI_HAVE_PATCHES

if not "%OLD_MSI_IDX%"=="0" goto :MSI_HAVE_OLD
    echo    [ERROR] MSI patches found but no .msi files in old_version.
    echo            Please place the baseline MSI files in old_version.
    set /a FAIL_COUNT+=%MSI_PATCH_IDX%
    goto :STEP2
:MSI_HAVE_OLD

if "%MSI_PATCH_IDX%"=="%OLD_MSI_IDX%" goto :MSI_COUNT_OK
    echo [WARN] MSI patch count [%MSI_PATCH_IDX%] does not match old MSI count [%OLD_MSI_IDX%]
    echo        Will pair up to the smaller count.
:MSI_COUNT_OK

REM Determine pair count
set "PAIR_COUNT=%MSI_PATCH_IDX%"
if %OLD_MSI_IDX% LSS %MSI_PATCH_IDX% set "PAIR_COUNT=%OLD_MSI_IDX%"

REM Collect new_installer MSIs sorted for pairing
set "NEW_INST_IDX=0"
for /f "delims=" %%F in ('dir /b /on "new_installer_*.msi" 2^>nul') do call :COLLECT_NEW_INST "%%F"

set "CUR_IDX=0"
:MSI_LOOP
set /a CUR_IDX+=1
if %CUR_IDX% GTR %PAIR_COUNT% goto :MSI_LOOP_END

call set "CUR_PATCH=%%MSI_PATCH_%CUR_IDX%%%"
call set "CUR_OLD_MSI=%%OLD_MSI_%CUR_IDX%%%"
call set "CUR_NEW_INST=%%NEW_INST_%CUR_IDX%%%"

echo -- MSI pair %CUR_IDX%: %CUR_OLD_MSI% + %CUR_PATCH%
call :RESTORE_MSI "%CUR_OLD_MSI%" "%CUR_PATCH%" "%CUR_NEW_INST%"
goto :MSI_LOOP

:MSI_LOOP_END
echo.

:STEP2
:: ============================================================
::  Step 2: Process directory patch (update_dir.hdiff)
:: ============================================================
if exist "update_dir.hdiff" goto :DO_DIR_PATCH
    echo [Step 2] No directory patch found, skipping.
    echo.
    goto :DONE
:DO_DIR_PATCH

echo [Step 2] Processing directory patch...
echo.

REM Build old dir content (non-MSI files) into temp
if exist "%TEMP_DIR%\dir_old" rd /s /q "%TEMP_DIR%\dir_old"
mkdir "%TEMP_DIR%\dir_old" 2>nul
robocopy "%OLD_DIR%" "%TEMP_DIR%\dir_old" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
for %%M in ("%TEMP_DIR%\dir_old\*.msi") do del /f /q "%%M" 2>nul

if exist "%TEMP_DIR%\dir_new" rd /s /q "%TEMP_DIR%\dir_new"
"%HPATCHZ%" "%TEMP_DIR%\dir_old" "update_dir.hdiff" "%TEMP_DIR%\dir_new"
if errorlevel 1 goto :DIR_PATCH_FAIL
    REM Merge restored files into new_version
    robocopy "%TEMP_DIR%\dir_new" "%OUTPUT_DIR%" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
    set /a RESTORE_COUNT+=1
    echo    [OK] Directory files restored.
    goto :DIR_PATCH_DONE
:DIR_PATCH_FAIL
    echo    [ERROR] Directory patch apply failed.
    set /a FAIL_COUNT+=1
:DIR_PATCH_DONE
rd /s /q "%TEMP_DIR%\dir_old" 2>nul
rd /s /q "%TEMP_DIR%\dir_new" 2>nul
echo.

:DONE
REM Clean up temp
rd /s /q "%TEMP_DIR%" 2>nul

echo ============================================
if not "%FAIL_COUNT%"=="0" goto :DONE_WITH_ERRORS
    echo   Restore completed successfully.
    echo   Restored %RESTORE_COUNT% patches to: %OUTPUT_DIR%\
    goto :DONE_MSG_END
:DONE_WITH_ERRORS
    echo   [WARN] Restore completed with %FAIL_COUNT% errors.
    echo   Please check the output above.
:DONE_MSG_END
echo ============================================
echo.
popd
pause
endlocal
exit /b 0


:: ============================================================
::  COLLECTION SUBROUTINES
:: ============================================================
:COLLECT_MSI_PATCH
set /a MSI_PATCH_IDX+=1
set "MSI_PATCH_%MSI_PATCH_IDX%=%~1"
exit /b 0

:COLLECT_OLD_MSI
set /a OLD_MSI_IDX+=1
set "OLD_MSI_%OLD_MSI_IDX%=%~1"
exit /b 0

:COLLECT_NEW_INST
set /a NEW_INST_IDX+=1
set "NEW_INST_%NEW_INST_IDX%=%~1"
exit /b 0


:: ============================================================
::  SUBROUTINE: Restore a single MSI
::  %1 = old MSI filename, %2 = patch filename, %3 = new_installer filename
:: ============================================================
:RESTORE_MSI
set "RM_OLD_MSI=%~1"
set "RM_PATCH=%~2"
set "RM_NEW_INST=%~3"

echo    Extracting old MSI: %RM_OLD_MSI%
if exist "%TEMP_DIR%\msi_old" rd /s /q "%TEMP_DIR%\msi_old"
mkdir "%TEMP_DIR%\msi_old" 2>nul
set "ABS_OLD_MSI=%CD%\%OLD_DIR%\%RM_OLD_MSI%"
set "ABS_OLD_PAYLOAD=%CD%\%TEMP_DIR%\msi_old"
msiexec /a "%ABS_OLD_MSI%" /qb TARGETDIR="%ABS_OLD_PAYLOAD%"
if errorlevel 1 goto :MSI_EXTRACT_FAIL
goto :MSI_EXTRACT_OK
:MSI_EXTRACT_FAIL
    echo    [ERROR] MSI extraction failed: %RM_OLD_MSI%
    set /a FAIL_COUNT+=1
    goto :RESTORE_MSI_CLEANUP
:MSI_EXTRACT_OK

REM Remove .msi from payload
for /r "%TEMP_DIR%\msi_old" %%M in (*.msi) do del /f /q "%%M"

echo    Applying patch: %RM_PATCH%
if exist "%TEMP_DIR%\msi_new" rd /s /q "%TEMP_DIR%\msi_new"
"%HPATCHZ%" "%TEMP_DIR%\msi_old" "%RM_PATCH%" "%TEMP_DIR%\msi_new"
if errorlevel 1 goto :MSI_PATCH_FAIL
goto :MSI_PATCH_OK
:MSI_PATCH_FAIL
    echo    [ERROR] Patch apply failed: %RM_PATCH%
    set /a FAIL_COUNT+=1
    goto :RESTORE_MSI_CLEANUP
:MSI_PATCH_OK

REM Merge restored payload into new_version
robocopy "%TEMP_DIR%\msi_new" "%OUTPUT_DIR%" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul

REM Copy thin MSI if exists
if not defined RM_NEW_INST goto :MSI_NO_THIN
if not exist "%RM_NEW_INST%" goto :MSI_NO_THIN
    copy /y "%RM_NEW_INST%" "%OUTPUT_DIR%\" >nul
    echo    Thin MSI copied: %RM_NEW_INST%
:MSI_NO_THIN
set /a RESTORE_COUNT+=1
echo    [OK] MSI restored successfully.

:RESTORE_MSI_CLEANUP
rd /s /q "%TEMP_DIR%\msi_old" 2>nul
rd /s /q "%TEMP_DIR%\msi_new" 2>nul
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
echo         Please create old_version directory and place baseline files in it.
popd & pause & endlocal
exit /b 1

:ERR_NO_PATCH
echo [ERROR] No .hdiff patch files found in current directory.
popd & pause & endlocal
exit /b 1
