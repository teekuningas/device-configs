@echo off
setlocal

REM Set the code page to UTF-8 to handle special characters if necessary
chcp 65001

REM Specify the paths of the latest backup files to sync
set "FILES_TO_SYNC=E:\Backups\Tiedostosäilö\tiedostosailo_backup.zip E:\Backups\TeeVault\teevault_backup.zip E:\Backups\Mediakirjasto\mediakirjasto_backup.zip"

REM Specify the destination user and host information
set "DEST_USER=zairex"
set "DEST_HOST=pi.miau"
set "DEST_DIR=/media/zairex/MiauExt/Backups"

REM Loop through each file and transfer it using scp
for %%F in (%FILES_TO_SYNC%) do (
    echo Transferring %%F to %DEST_USER%@%DEST_HOST%:%DEST_DIR%
    scp "%%F" %DEST_USER%@%DEST_HOST%:%DEST_DIR%
    if %errorlevel%==0 (
        echo Successfully transferred %%F
    ) else (
        echo Error transferring %%F
    )
)

endlocal