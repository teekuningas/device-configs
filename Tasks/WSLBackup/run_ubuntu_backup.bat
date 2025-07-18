chcp 65001

@echo off
setlocal enabledelayedexpansion

REM Specify the folder to backup
set "WSL_TO_BACKUP=UbuntuWSL"

REM Specify the backup filename base
set "BACKUP_FILENAME=ubuntu_backup"

REM Set the directory where the backups are stored
set "BACKUP_DIR=E:\Backups\WSL\UbuntuWSL"

REM Set the max number of backup files to keep
set "MAX_BACKUPS=1"

REM Ask user for permission to continue
echo This script will backup the WSL distribution "%WSL_TO_BACKUP%".
echo Press any key to continue.
pause >nul

REM Change directory to the backup folder
cd /d "%BACKUP_DIR%"

REM First, check if the oldest backup exists and should be deleted
if exist "%BACKUP_FILENAME%.%MAX_BACKUPS%.tar" (
    del "%BACKUP_FILENAME%.%MAX_BACKUPS%.tar"
)

REM Rotate existing backups
for /L %%i in (%MAX_BACKUPS%-1,-1,1) do (
    set /A next=%%i+1
    if exist "%BACKUP_FILENAME%.%%i.tar" (
        move "%BACKUP_FILENAME%.%%i.tar" "%BACKUP_FILENAME%.!next!.tar"
    )
)

REM Move the base file to .1 if it exists
if exist "%BACKUP_FILENAME%.tar" (
    move "%BACKUP_FILENAME%.tar" "%BACKUP_FILENAME%.1.tar"
)

REM Terminate the WSL
echo Terminating WSL..
wsl --terminate %WSL_TO_BACKUP%

REM Use WSL to export the distribution into a tarball.
echo Exporting..
wsl --export "%WSL_TO_BACKUP%" "%BACKUP_FILENAME%.tar"

endlocal