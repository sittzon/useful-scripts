#!/bin/zsh
# check_corrupt_files.sh
#
# Tool for verifying file integrity for images, videos and audio. 
# Uses ImageMagick and ffprobe (ffmpeg) for file verification.
# Calculates and stores CRC checksum for files that passes verification.

IMAGE_EXTENSIONS=("jpg" "jpeg" "png" "webp" "heic")
VIDEO_EXTENSIONS=("mp4" "mov" "mpg" "avi" "mkv" "flv" "wmv" "webm" "mts")

TARGET_DIR=""
OUTPUT_FILE="./corrupt_files.txt"
NO_VERIFY_FLAG=0
CORRUPT_FILES_FOUND=0
VERBOSE_FLAG=0

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dir) TARGET_DIR="$2"; shift ;;
    --no-verify) NO_VERIFY_FLAG=1 ;;
    --verbose) VERBOSE_FLAG=1 ;;
    --help)
      echo "Usage: $0 --dir <directory> [--no-verify] [--verbose] [--help]"
      echo "  --dir          Specify the directory containing images to check."
      echo "  --verbose      Echo crc matches and creation of crc files."
      echo "  --no-verify    Disables crc verification of files that have a corresponding crc file."
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

# Clear the output file if it exists
truncate -s 0 "$OUTPUT_FILE"

echo "Checking image and video files in $TARGET_DIR  for corruption..."

# Function to calculate the CRC checksum of a file
# BUG WITH CRC32: https://unix.stackexchange.com/questions/481141/why-does-crc32-say-some-of-my-files-are-bad
# Replaced with modified crc32mod
calculate_crc() {
  ./crc32mod "$1" 2>/dev/null || cksum "$1" | awk '{print $1}' # Use crc32 or fallback to cksum
}

# Prepare find command
find_command="find \"$TARGET_DIR\" -type f"
for EXTENSION in "${IMAGE_EXTENSIONS[@]}"; do
    find_command="${find_command} -iname \"*.${EXTENSION}\" -o"
done
for EXTENSION in "${VIDEO_EXTENSIONS[@]}"; do
    find_command="${find_command} -iname \"*.${EXTENSION}\" -o"
done
find_command="${find_command% -o}"
# echo "find_command: $find_command"

# Find all image and video files in the directory and its subdirectories
current_dir=""
eval "$find_command" | sort | while read -r file; do
  
  dir=$(dirname "$file")
  if ([ -z "$current_dir" ] || [ "$current_dir" != "$dir" ]); then
    current_dir="$dir"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying directory: $current_dir"
  fi
  
  # echo "file: $file"

  crc_file="${file}.crc32.txt"
  # If corresponding .crc file found, then verify
  if [ -f "$crc_file" ]; then
    if [ $NO_VERIFY_FLAG -eq 0 ]; then
      # Perform CRC check
      calculated_crc=$(calculate_crc "$file")
      stored_crc=$(cat "$crc_file" | tr -d '\r\n') # Handle potential line endings
      if [ "$calculated_crc" != "$stored_crc" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRC mismatch: $file" | tee -a "$OUTPUT_FILE"
        CORRUPT_FILES_FOUND=1
      elif [[ "$VERBOSE_FLAG" -eq 1 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRC match: $file"
      fi
    fi
  # Else, do crc computation
  else
    # If file is of video type, use ffprobe, else identify
    if [[ " ${VIDEO_EXTENSIONS[@]} " =~ " ${file##*.} " ]]; then
      ffprobe -v error -i "$file" >/dev/null 2>&1
    else
      identify -regard-warnings -verbose "$file" >/dev/null 2>&1
    fi
    if [ $? -ne 0 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Corrupt file: $file" | tee -a "$OUTPUT_FILE"
      CORRUPT_FILES_FOUND=1
    else
      # If no errors found and .crc does not exist, create the .crc file
      calculate_crc "$file" > "$crc_file"
      if [[ "$VERBOSE_FLAG" -eq 1 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Created crc file: $crc_file"
      fi
    fi
  fi
  
done

# Provide feedback to the user
if [ $CORRUPT_FILES_FOUND -eq 1 ]; then
  echo "Corrupt files found. Check $OUTPUT_FILE for details."
  echo "Tip: Use backsync.sh to restore corrupt files from backup."
  exit 1
fi

echo "No corrupt files found."
exit 0
