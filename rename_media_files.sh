#!/bin/zsh
# rename_media_files.sh
#
# Renaming tool for images, sidecar and videos based on their metadata.
# Uses exiftool to extract metadata and rename files accordingly.
# If no metadata can be found, file will not be renamed.
# - Supports pair renaming for image and sidecar files
# - Supports collision resolution for files with the same name
# - Supports undo operation to revert the last rename operation
# - Use dry-run to see what files will be renamed without actually renaming them
#
# TODO:
# - User defined date format

# Nice to have:
# - Multiple undo levels
# - User defined fallback metadata field

# Config
# Supported image and video extensions
IMAGE_EXTENSIONS=("jpg" "jpeg" "png" "heic" "webp")
IMAGE_SIDECAR_EXTENSIONS=("mp4" "mov" "aae")
VIDEO_EXTENSIONS=("mp4" "mov" "avi" "mkv" "flv" "wmv" "webm" "mts")

# Parse command-line arguments
UNDO_FLAG=0
DRY_RUN_FLAG=0
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dir) TARGET_DIR="$2"; shift ;;
    --undo) UNDO_FLAG=1 ;;
    --dry-run) DRY_RUN_FLAG=1 ;;
    --help)
      echo "Usage: $0 --dir <directory> [--undo] [--dry-run] [--help]"
      echo "  --dir     Specify the directory containing images to check."
      echo "  --undo    Undo the last rename operation."
      echo "  --dry-run Show what files will be renamed without actually renaming them."
      echo "  --help    Display this help message."
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

LOG_FILE="./rename_log.txt"

# Undo last rename operation
if [[ $UNDO_FLAG -eq 1 ]]; then
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Error: No log file found. Cannot undo."
        exit 1
    fi

    # Read log file and apply reverse mv operation
    tail -r "$LOG_FILE" | while read -r LINE; do
        ORIGINAL=$(echo "$LINE" | sed -n 's/^Renamed: \(.*\) ->.*/\1/p')
        RENAMED=$(echo "$LINE" | sed -n 's/^Renamed: .* -> \(.*\)$/\1/p')

        if [[ -n "$ORIGINAL" && -n "$RENAMED" ]]; then
            if [[ -e "$RENAMED" ]]; then
                if [[ $DRY_RUN_FLAG -eq 0 ]]; then
                    mv "$RENAMED" "$ORIGINAL"
                fi
                echo "Reverted: $RENAMED -> $ORIGINAL"
            else
                echo "Warning: File $RENAMED does not exist. Skipping."
            fi
        fi
    done

    # Clear log contents
    truncate -s 0 "$LOG_FILE"

    echo "Undo operation completed."
    exit 0
fi

# Check if the directory is provided
if [ -z "$TARGET_DIR" ]; then
  echo "Error: --dir option is required."
  echo "Use --help for usage information."
  exit 1
fi

# Check if the directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory $TARGET_DIR does not exist."
  exit 1
fi

# Exit immediately if a command exits with a non-zero status
set -e

# Check if exiftool is installed
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool is not installed. Install it and try again."
    exit 1
fi

# Clear log contents
truncate -s 0 "$LOG_FILE"

# Create an associative array for grouping files
typeset -A FILE_GROUPS

# Helper function to check if an array contains an element
function contains() {
    local item="$1"
    shift
    for elem in "$@"; do
        if [[ "$elem" == "$item" ]]; then
            return 0
        fi
    done
    return 1
}

# Helper function to resolve filename collisions
function resolve_collision() {
    local directory="$1"
    local base_name="$2"
    local extension="$3"
    local counter=1

    local new_name="${base_name}.${extension}"
    while [[ -e "$directory/$new_name" ]]; do
        new_name="${base_name}_$counter.${extension}"
        ((counter++))
    done

    echo "$new_name"
}

# Prepare find command
find_command="find $TARGET_DIR -type f"
for EXTENSION in "${IMAGE_EXTENSIONS[@]}"; do
    find_command="${find_command} -iname \"*.${EXTENSION}\" -o"
done
find_command="${find_command% -o}"
# echo "find_command: $find_command"

# Pair renaming for image and sidecar files
eval "$find_command" | sort | while read -r FILE; do
    SIDECAR_FILES=""
    DATE_TAKEN=""

    local base_name=$(basename "$FILE")
    local dir_name=$(dirname "$FILE")
    local filename="${base_name%.*}"
    local file_extension="${base_name##*.}"

    # Rename image file
    if [[ -n "$FILE" ]]; then
        # Extract DateTimeOriginal
        DATE_TAKEN=$(exiftool -s3 -d '%Y-%m-%d_%H%M%S' -DateTimeOriginal "$FILE" 2>/dev/null || echo "")

        # Skip if no valid date is found
        if [[ -z "$DATE_TAKEN" ]]; then
            echo "Skipping: $FILE (no valid date found)" | tee -a "$LOG_FILE"
            continue
        fi

        # Resolve collisions
        IMAGE_NEW_NAME=$(resolve_collision "$dir_name" "$DATE_TAKEN" "$file_extension")
        if [[ $DRY_RUN_FLAG -eq 0 ]]; then
            mv "$FILE" "$dir_name/$IMAGE_NEW_NAME"
        fi

        echo "Renamed: $FILE -> $dir_name/$IMAGE_NEW_NAME" | tee -a "$LOG_FILE"
    fi

    # Find potential sidecar files
    for EXTENSION in "${IMAGE_SIDECAR_EXTENSIONS[@]}"; do
        SIDE_FILE="${dir_name}/${filename}.${EXTENSION}"
        if [[ -e "$SIDE_FILE" ]]; then
            SIDECAR_FILES="${SIDECAR_FILES}$SIDE_FILE;"
        fi
    done

    # Remove trailing semicolon
    SIDECAR_FILES="${SIDECAR_FILES%;}"

    # Rename sidecar files
    if [[ -n $SIDECAR_FILES ]]; then
        IFS=';' read -rA ADDR <<< "$SIDECAR_FILES"
        for SIDE_FILE in "${ADDR[@]}"; do
            SIDE_EXTENSION="${SIDE_FILE##*.}"
            SIDE_NEW_NAME=$(resolve_collision "$dir_name" "$DATE_TAKEN" "$SIDE_EXTENSION")
            if [[ $DRY_RUN_FLAG -eq 0 ]]; then
                mv "$SIDE_FILE" "$dir_name/$SIDE_NEW_NAME"
            fi

            echo "Renamed: $SIDE_FILE -> $dir_name/$SIDE_NEW_NAME" | tee -a "$LOG_FILE"
        done
    fi
done


# # Rename video files
# find "$TARGET_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi"  -o -iname "*.mts" \) | sort | while read -r FILE; do
#     local base_name=$(basename "$FILE")
#     local dir_name=$(dirname "$FILE")
#     local filename="${base_name%.*}"

#     # Find potential corresponding image file, and if found, do not rename
#     local IMAGE_FILE=""
#     for EXTENSION in "${IMAGE_EXTENSIONS[@]}"; do
#         IMG_FILE="${dir_name}/${filename}.${EXTENSION}"
#         if [[ -e "$IMG_FILE" ]]; then
#             IMAGE_FILE="$IMG_FILE"
#             break
#         fi
#     done

#     if [[ -n $IMAGE_FILE ]]; then
#         echo "Skipping: $FILE (video is already renamed, sidecar)" | tee -a "$LOG_FILE"
#         continue
#     fi

#     # Extract -CreatedDate from video metadata and check for collisions
#     local DATE_TAKEN=$(exiftool -s3 -d '%Y-%m-%d_%H%M%S' -CreateDate "$FILE" 2>/dev/null || echo "")
#     # Check if date not found, i.e date is 0000:00:00 00:00:00
#     if [[ "$DATE_TAKEN" == "0000:00:00 00:00:00" ]]; then
#         echo "Skipping: $FILE (no valid date found)" | tee -a "$LOG_FILE"
#         continue
#     fi
#     local VIDEO_NEW_NAME=$(resolve_collision "$dir_name" "$DATE_TAKEN" "${FILE##*.}")
#     if [[ $DRY_RUN_FLAG -eq 0 ]]; then
#         mv "$FILE" "$dir_name/$VIDEO_NEW_NAME"
#     fi
#     echo "Renamed: $FILE -> $dir_name/$VIDEO_NEW_NAME" | tee -a "$LOG_FILE"
# done

echo "Renaming completed successfully!"
exit 0