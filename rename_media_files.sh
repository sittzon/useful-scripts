#!/bin/zsh
# rename_media_files.sh
#
# Renaming tool for images and videos based on their metadata.
# Uses exiftool to extract metadata and rename files accordingly.
# If no metadata can be found, file will not be renamed.
# - Supports pair renaming for image and video files
# - Supports collision resolution for files with the same name
#
# 2025-01-24: 
# - Does not handle subdirectories correctly
# - Only supports files that have DateTimeOriginal or CreateDate metadata
#
# TODO:
# - Handle subdirectories
# - Add support for undo last rename operation

# Exit immediately if a command exits with a non-zero status
set -e

# Check if exiftool is installed
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool is not installed. Install it and try again."
    exit 1
fi

# Folder containing media files (default is current directory)
TARGET_DIR=${1:-.}

# Create an associative array for grouping files
typeset -A FILE_GROUPS

# Supported image and video extensions
IMAGE_EXTENSIONS=("jpg" "jpeg" "png" "heic")
VIDEO_EXTENSIONS=("mp4" "mov")

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

# Iterate over all media files in the target directory
find "$TARGET_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png"  -o -iname "*.heic" -o -iname "*.mp4" -o -iname "*.mov" \) | while read -r FILE; do
    # Extract the base name (without extension), and extension
    BASENAME=$(basename "$FILE" | sed -E 's/\.[^.]+$//')
    EXTENSION="${FILE##*.}"
    EXTENSION_LOWER=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

    # Group files by their basename
    FILE_GROUPS["$BASENAME"]="${FILE_GROUPS["$BASENAME"]}$FILE,"
done

# Process each group
for BASENAME in ${(k)FILE_GROUPS}; do
    IFS=',' read -r -A FILES <<< "${FILE_GROUPS[$BASENAME]}"
    IMAGE_FILE=""
    VIDEO_FILE=""
    DATE_TAKEN=""

    # Separate image and video files
    for FILE in "${FILES[@]}"; do
        EXTENSION="${FILE##*.}"
        EXTENSION_LOWER=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

        if contains "$EXTENSION_LOWER" "${IMAGE_EXTENSIONS[@]}"; then
            IMAGE_FILE=$FILE
        elif contains "$EXTENSION_LOWER" "${VIDEO_EXTENSIONS[@]}"; then
            VIDEO_FILE=$FILE
        fi
    done

    # Rename image file
    if [[ -n $IMAGE_FILE ]]; then
        # Extract DateTimeOriginal
        DATE_TAKEN=$(exiftool -s3 -d '%Y-%m-%d_%H%M%S' -DateTimeOriginal "$IMAGE_FILE" 2>/dev/null || echo "")

        # Skip if no valid date is found
        if [ -z "$DATE_TAKEN" ]; then
            echo "Warning: Skipping $IMAGE_FILE (no valid date found)"
            continue
        fi

        # Resolve collisions
        IMAGE_NEW_NAME=$(resolve_collision "$TARGET_DIR" "$DATE_TAKEN" "${IMAGE_FILE##*.}")
        mv "$IMAGE_FILE" "$TARGET_DIR/$IMAGE_NEW_NAME"

        echo "Renamed: $IMAGE_FILE -> $TARGET_DIR/$IMAGE_NEW_NAME"
    fi

    # Pair rename video file if it exists
    if [[ -n $VIDEO_FILE ]] && [ -n "$DATE_TAKEN" ]; then
        if [[ -n $IMAGE_NEW_NAME ]]; then
            # Use the same base name as the image file
            VIDEO_NEW_NAME=$(resolve_collision "$TARGET_DIR" "$DATE_TAKEN" "${VIDEO_FILE##*.}")
            mv "$VIDEO_FILE" "$TARGET_DIR/$VIDEO_NEW_NAME"
            echo "Renamed: $VIDEO_FILE -> $TARGET_DIR/$VIDEO_NEW_NAME"
        fi
    # Else, rename video file independently
    elif [[ -n $VIDEO_FILE ]] && [ -z "$DATE_TAKEN" ]; then
        # Extract -CreatedDate from video metadata and check for collisions
        DATE_TAKEN=$(exiftool -s3 -d '%Y-%m-%d_%H%M%S' -CreateDate "$VIDEO_FILE" 2>/dev/null || echo "")
        VIDEO_NEW_NAME=$(resolve_collision "$TARGET_DIR" "$DATE_TAKEN" "${VIDEO_FILE##*.}")
        mv "$VIDEO_FILE" "$TARGET_DIR/$VIDEO_NEW_NAME"
        echo "Renamed: $VIDEO_FILE -> $TARGET_DIR/$VIDEO_NEW_NAME"
    fi
done

echo "Renaming completed successfully!"
