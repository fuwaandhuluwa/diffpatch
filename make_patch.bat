@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::  Multi-Mode Diff Patch Maker
::  Auto-detects file types in old_version / new_version:
::    - MSI files paired by sorted order -> MSI mode (extract then diff)
::    - Remaining non-MSI files -> directory mode (bulk diff)
::  All output goes to "output" directory
:: ============================================================

pushd "%~dp0" || (
    echo [ERR] cannot enter script dir
    pause
    exit /b 1
)

set "OLD_DIR=old_version"
set "NEW_DIR=new_version"
set "HDIFFZ=hdiffz.exe"
set "HPATCHZ=hpatchz.exe"
set "TEMP_DIR=temp"
set "OUT_DIR=output"
set "MSI_COUNT=0"
set "HAS_DIR_FILES=0"

echo ============================================
echo   Multi-Mode Diff Patch Maker
echo   ( old_version -^> new_version )
echo ============================================
echo.

REM ---- Check tools ----
if not exist "%HDIFFZ%" (
    where hdiffz.exe >nul 2>nul
    if errorlevel 1 goto :ERR_NO_HDIFFZ
    set "HDIFFZ=hdiffz.exe"
)

if not exist "%OLD_DIR%\" goto :ERR_NO_OLD
if not exist "%NEW_DIR%\" goto :ERR_NO_NEW

REM ---- Prepare output directory ----
if exist "%OUT_DIR%" rd /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%" 2>nul

REM ---- Prepare temp directory ----
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%" 2>nul

:: ============================================================
::  Phase 1: Process MSI pairs (paired by sorted order)
:: ============================================================
echo [Phase 1] Scanning for MSI files...
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

echo    Old MSI count: %OLD_MSI_IDX%
echo    New MSI count: %NEW_MSI_IDX%

if "%OLD_MSI_IDX%"=="0" if "%NEW_MSI_IDX%"=="0" (
    echo    No MSI files found.
    goto :PHASE2
)

if not "%OLD_MSI_IDX%"=="%NEW_MSI_IDX%" (
    echo [WARN] MSI count mismatch! old=%OLD_MSI_IDX% new=%NEW_MSI_IDX%
    echo        Will pair up to the smaller count.
)

REM Determine pair count (min of both)
set "PAIR_COUNT=%OLD_MSI_IDX%"
if %NEW_MSI_IDX% LSS %OLD_MSI_IDX% set "PAIR_COUNT=%NEW_MSI_IDX%"

if "%PAIR_COUNT%"=="0" (
    echo    No MSI pairs to process.
    goto :PHASE2
)

echo.
for /l %%I in (1,1,%PAIR_COUNT%) do (
    set "CUR_OLD_MSI=!OLD_MSI_%%I!"
    set "CUR_NEW_MSI=!NEW_MSI_%%I!"
    set "CUR_OLD_BASE=!OLD_MSI_BASE_%%I!"
    set "CUR_NEW_BASE=!NEW_MSI_BASE_%%I!"
    echo -- MSI pair %%I: !CUR_OLD_MSI! -^> !CUR_NEW_MSI!
    call :PROCESS_MSI "!CUR_OLD_MSI!" "!CUR_NEW_MSI!" "!CUR_OLD_BASE!" "!CUR_NEW_BASE!"
    if errorlevel 1 (
        echo [ERROR] Failed to process MSI pair %%I
        goto :CLEANUP_FAIL
    )
    set /a MSI_COUNT+=1
)
echo.

:PHASE2
:: ============================================================
::  Phase 2: Process remaining non-MSI files (directory diff)
:: ============================================================
echo [Phase 2] Preparing non-MSI files for directory diff...
echo.

if exist "%TEMP_DIR%\dir_old" rd /s /q "%TEMP_DIR%\dir_old"
if exist "%TEMP_DIR%\dir_new" rd /s /q "%TEMP_DIR%\dir_new"
mkdir "%TEMP_DIR%\dir_old" 2>nul
mkdir "%TEMP_DIR%\dir_new" 2>nul

REM Copy everything then remove .msi
robocopy "%OLD_DIR%" "%TEMP_DIR%\dir_old" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
robocopy "%NEW_DIR%" "%TEMP_DIR%\dir_new" /E /NFL /NDL /NJH /NJS /NC /NS >nul 2>nul
for %%F in ("%TEMP_DIR%\dir_old\*.msi") do del /f /q "%%F" 2>nul
for %%F in ("%TEMP_DIR%\dir_new\*.msi") do del /f /q "%%F" 2>nul

REM Check if there are any files left
set "DIR_NEW_COUNT=0"
set "DIR_OLD_COUNT=0"
for /r "%TEMP_DIR%\dir_old" %%F in (*) do set /a DIR_OLD_COUNT+=1
for /r "%TEMP_DIR%\dir_new" %%F in (*) do set /a DIR_NEW_COUNT+=1

if "%DIR_NEW_COUNT%"=="0" if "%DIR_OLD_COUNT%"=="0" (
    echo    No non-MSI files found, skipping directory diff.
    goto :PHASE_DONE
)

set "HAS_DIR_FILES=1"
echo    Old non-MSI files: %DIR_OLD_COUNT%
echo    New non-MSI files: %DIR_NEW_COUNT%
echo    Creating directory diff patch...
"%HDIFFZ%" -m-2 "%TEMP_DIR%\dir_old" "%TEMP_DIR%\dir_new" "%OUT_DIR%\update_dir.hdiff"
if errorlevel 1 goto :ERR_DIFF

for %%A in ("%OUT_DIR%\update_dir.hdiff") do echo    Directory patch size: %%~zA bytes
echo.

:PHASE_DONE

REM Clean up temp
rd /s /q "%TEMP_DIR%\dir_old" 2>nul
rd /s /q "%TEMP_DIR%\dir_new" 2>nul

:: ============================================================
::  Phase 3: Assemble output package
:: ============================================================
echo [Phase 3] Assembling output package...

REM Copy hpatchz.exe
if exist "%HPATCHZ%" (
    copy /y "%HPATCHZ%" "%OUT_DIR%\" >nul
    echo    Copied hpatchz.exe
) else (
    echo [WARN] hpatchz.exe not found, not included in output.
)

REM Copy restore.bat
if exist "restore.bat" (
    copy /y "restore.bat" "%OUT_DIR%\" >nul
    echo    Copied restore.bat
) else (
    echo [WARN] restore.bat not found in project root.
)

REM Create empty old_version directory
mkdir "%OUT_DIR%\old_version" 2>nul

:: ============================================================
::  Phase 4: Generate UpgradeReadme.txt
:: ============================================================
echo.
echo [Phase 4] Generating UpgradeReadme.txt...

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_gen_readme.ps1" -OutDir "%OUT_DIR%" -OldDir "%OLD_DIR%"

echo.
echo ============================================
echo   Build complete!
echo ============================================
echo.
echo   Output directory: %OUT_DIR%\
echo   Contents:
for %%F in ("%OUT_DIR%\*") do echo     %%~nxF
echo     old_version\  (empty, user fills baseline files)
echo.
echo   MSI patches : %MSI_COUNT%
echo   Dir patches : %HAS_DIR_FILES%
echo ============================================

rd /s /q "%TEMP_DIR%" 2>nul

popd
pause
endlocal
exit /b 0


:: ============================================================
::  SUBROUTINE: Process a single MSI pair
::  %1 = old MSI filename, %2 = new MSI filename
::  %3 = old MSI base name, %4 = new MSI base name
::  Naming: update_msi_<OLD>_TO_<NEW>.hdiff, new_installer_<NEW>.msi
:: ============================================================
:PROCESS_MSI
set "PMSI_OLD_NAME=%~1"
set "PMSI_NEW_NAME=%~2"
set "PMSI_OLD_BASE=%~3"
set "PMSI_NEW_BASE=%~4"

echo    [MSI] Extracting old: %PMSI_OLD_NAME%
if exist "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%" rd /s /q "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%"
mkdir "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%" 2>nul

set "ABS_OLD_MSI=%CD%\%OLD_DIR%\%PMSI_OLD_NAME%"
set "ABS_OLD_PAYLOAD=%CD%\%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%"

msiexec /a "!ABS_OLD_MSI!" /qb TARGETDIR="!ABS_OLD_PAYLOAD!"
if errorlevel 1 (
    echo    [ERROR] Failed to extract old MSI: %PMSI_OLD_NAME%
    exit /b 1
)

echo    [MSI] Extracting new: %PMSI_NEW_NAME%
if exist "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" rd /s /q "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%"
mkdir "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" 2>nul

set "ABS_NEW_MSI=%CD%\%NEW_DIR%\%PMSI_NEW_NAME%"
set "ABS_NEW_PAYLOAD=%CD%\%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%"

msiexec /a "!ABS_NEW_MSI!" /qb TARGETDIR="!ABS_NEW_PAYLOAD!"
if errorlevel 1 (
    echo    [ERROR] Failed to extract new MSI: %PMSI_NEW_NAME%
    exit /b 1
)

REM Save thin MSI from new payload
set "THIN_MSI_FOUND=0"
for %%M in ("%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%\*.msi") do (
    copy /y "%%M" "%OUT_DIR%\new_installer_%PMSI_NEW_BASE%.msi" >nul
    set "THIN_MSI_FOUND=1"
)
if "%THIN_MSI_FOUND%"=="0" (
    for /r "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" %%M in (*.msi) do (
        copy /y "%%M" "%OUT_DIR%\new_installer_%PMSI_NEW_BASE%.msi" >nul
        set "THIN_MSI_FOUND=1"
    )
)
if "%THIN_MSI_FOUND%"=="1" (
    echo    [MSI] Saved thin MSI: new_installer_%PMSI_NEW_BASE%.msi
)

REM Remove .msi from both payloads
for /r "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%" %%M in (*.msi) do del /f /q "%%M"
for /r "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" %%M in (*.msi) do del /f /q "%%M"

REM Create diff
echo    [MSI] Creating diff patch...
"%HDIFFZ%" -m-2 "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%" "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" "%OUT_DIR%\update_msi_%PMSI_OLD_BASE%_TO_%PMSI_NEW_BASE%.hdiff"
if errorlevel 1 (
    echo    [ERROR] Diff failed for MSI pair
    exit /b 1
)

for %%A in ("%OUT_DIR%\update_msi_%PMSI_OLD_BASE%_TO_%PMSI_NEW_BASE%.hdiff") do echo    [MSI] Patch size: %%~zA bytes

rd /s /q "%TEMP_DIR%\msi_old_%PMSI_OLD_BASE%" 2>nul
rd /s /q "%TEMP_DIR%\msi_new_%PMSI_OLD_BASE%" 2>nul
exit /b 0


:: ============================================================
::  ERROR HANDLERS
:: ============================================================
:ERR_NO_HDIFFZ
echo [ERROR] hdiffz.exe not found.
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

:ERR_DIFF
echo [ERROR] hdiffz diff creation failed!
rd /s /q "%TEMP_DIR%" 2>nul
popd & pause & endlocal
exit /b 1

:CLEANUP_FAIL
rd /s /q "%TEMP_DIR%" 2>nul
popd & pause & endlocal
exit /b 1
