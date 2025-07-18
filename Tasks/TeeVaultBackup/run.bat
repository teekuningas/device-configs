@echo off
setlocal enabledelayedexpansion

REM Specify the folder to backup
set "FOLDER_TO_BACKUP=C:\Users\erkka\Documents\obsidian_git_vault"

REM Specify the backup filename base
set "BACKUP_FILENAME=teevault_backup"

REM Set the directory where the backups are stored
set "BACKUP_DIR=E:\Backups\TeeVault"

REM Set the max number of backup files to keep
set "MAX_BACKUPS=3"

REM Specify the full path to the 7-Zip command line tool
set "ZIP_UTILITY=C:\Program Files\7-Zip\7z.exe"

REM Change directory to the backup folder
cd /d "%BACKUP_DIR%"

REM First, check if the oldest backup exists and should be deleted
if exist "%BACKUP_FILENAME%.%MAX_BACKUPS%.zip" (
    del "%BACKUP_FILENAME%.%MAX_BACKUPS%.zip"
)

REM Rotate existing backups
for /L %%i in (%MAX_BACKUPS%-1,-1,1) do (
    set /A next=%%i+1
    if exist "%BACKUP_FILENAME%.%%i.zip" (
        move "%BACKUP_FILENAME%.%%i.zip" "%BACKUP_FILENAME%.!next!.zip"
    )
)

REM Move the base file to .1 if it exists
if exist "%BACKUP_FILENAME%.zip" (
    move "%BACKUP_FILENAME%.zip" "%BACKUP_FILENAME%.1.zip"
)

REM Create a new backup zip file from the specified folder
"%ZIP_UTILITY%" a -tzip "%BACKUP_FILENAME%.zip" "%FOLDER_TO_BACKUP%\*"

endlocal