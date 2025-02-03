#!/bin/zsh
# backsync.sh

# Tool for restoring corrupt backup files by reading corrupt_files.txt, 
# replacing the dir, and copying the files from known good backup
# back to primary location.
# Recommend running check_corrupt_files.sh after running this script.

CORRUPT_FILES_LOG="./corrupt_files.txt"
LOG_FILE="./backsync_log.txt"
PRIMARY_DIR=""
BACKUP_DIR=""

DRY_RUN_FLAG=0
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --primary-dir) PRIMARY_DIR="$2"; shift ;;
    --backup-dir) BACKUP_DIR="$2"; shift ;;
    --dry-run) DRY_RUN_FLAG=1 ;;
    --help)
      echo "Usage: $0 --primary-dir <directory> --backup-dir <directory> [--dry-run] [--help]"
      echo "  --primary-dir  Primary directory where files will be restored to."
      echo "  --backup-dir   Backup directory where files will be restored from."
      echo "  --dry-run      Show what files will be restored without actually restoring them."
      echo "  --help         Display this help message."
      exit 0
      ;;
    *)
      echo "Unknown parameter passed: $1"
      echo "Use --help for usage information."
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "$CORRUPT_FILES_LOG" ]]; then
    echo "Error: No log file found. Cannot undo."
    exit 1
fi

if [[ $DRY_RUN_FLAG -eq 1 ]]; then
    echo "\n$(date '+%Y-%m-%d %H:%M:%S') - Running in dry-run mode. No files will be restored" | tee -a "$LOG_FILE"
fi

# For every line in CORRUPT_FILES_LOG, copy the file from backup to primary
tail -r "$CORRUPT_FILES_LOG" | while read -r LINE; do
    PRIMARY_FILE=$(echo "$LINE" | sed -n 's;.*Corrupt file: \(.*\);\1;p')
    BACKUP_FILE=$(echo "$PRIMARY_FILE" | sed "s;${PRIMARY_DIR};${BACKUP_DIR};g")

    if [[ -e "$BACKUP_FILE" ]]; then
        if [[ $DRY_RUN_FLAG -eq 0 ]]; then
            cp "$BACKUP_FILE" "$PRIMARY_FILE"
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Restored: $BACKUP_FILE -> $PRIMARY_FILE" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: File $BACKUP_FILE does not exist. Skipping." | tee -a "$LOG_FILE"
    fi
done

exit 0