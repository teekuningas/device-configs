@echo off
setlocal enabledelayedexpansion

REM -----------------------------------------------------------------------------
REM 1) UTF-8 output
REM -----------------------------------------------------------------------------
chcp 65001 >nul

REM -----------------------------------------------------------------------------
REM 2) Remote server details
REM -----------------------------------------------------------------------------
set "REMOTE_USER=zairex"
set "REMOTE_HOST=miaucloud-nixos"
set "REMOTE_PATH=/var/backups/data_backup.tar.gz"

REM -----------------------------------------------------------------------------
REM 3) Local backup settings
REM -----------------------------------------------------------------------------
set "BACKUP_DIR=E:\Backups\Miaucloud"
set "BACKUP_FILENAME=data_backup.tar.gz"
set "MAX_BACKUPS=3"

REM -----------------------------------------------------------------------------
REM 4) Prepare the directory
REM -----------------------------------------------------------------------------
if not exist "%BACKUP_DIR%" (
    echo Creating backup directory "%BACKUP_DIR%"
    mkdir "%BACKUP_DIR%"
)

cd /d "%BACKUP_DIR%"

REM -----------------------------------------------------------------------------
REM 5) Delete the oldest backup (.3)
REM -----------------------------------------------------------------------------
if exist "%BACKUP_FILENAME%.%MAX_BACKUPS%" (
    echo Deleting oldest backup "%BACKUP_FILENAME%.%MAX_BACKUPS%"
    del "%BACKUP_FILENAME%.%MAX_BACKUPS%"
)

REM -----------------------------------------------------------------------------
REM 6) Rotate .2→.3, .1→.2
REM    We need a literal “2” for the start, so calculate it:
REM -----------------------------------------------------------------------------
set /A "START=%MAX_BACKUPS% - 1"

for /L %%i in (%START%,-1,1) do (
    set /A "next=%%i+1"
    if exist "%BACKUP_FILENAME%.%%i" (
        echo Renaming "%BACKUP_FILENAME%.%%i" to "%BACKUP_FILENAME%.!next!"
        move "%BACKUP_FILENAME%.%%i" "%BACKUP_FILENAME%.!next!"
    )
)

REM -----------------------------------------------------------------------------
REM 7) Rotate current .tar.gz → .tar.gz.1
REM -----------------------------------------------------------------------------
if exist "%BACKUP_FILENAME%" (
    echo Renaming current "%BACKUP_FILENAME%" to "%BACKUP_FILENAME%.1"
    move "%BACKUP_FILENAME%" "%BACKUP_FILENAME%.1"
)

REM -----------------------------------------------------------------------------
REM 8) Fetch the new one via SCP
REM -----------------------------------------------------------------------------
echo.
echo Fetching "%REMOTE_PATH%" from %REMOTE_USER%@%REMOTE_HOST%
scp "%REMOTE_USER%@%REMOTE_HOST%:%REMOTE_PATH%" "%BACKUP_FILENAME%"
if errorlevel 1 (
    echo.
    echo ERROR: Failed to fetch remote backup!
    exit /b 1
) else (
    echo.
    echo Success: Remote backup saved as "%BACKUP_FILENAME%"
)

endlocal
```