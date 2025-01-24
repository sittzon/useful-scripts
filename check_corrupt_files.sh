#!/bin/bash

# Directory containing the files
IMAGE_DIR=""
OUTPUT_FILE="corrupt_files.txt"
VERBOSE_FLAG="-verbose"
NO_VERIFY_FLAG=0
CORRUPT_FILES_FOUND=0

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dir) IMAGE_DIR="$2"; shift ;;
    --no-verify) NO_VERIFY_FLAG=1; shift ;;
    --no-verbose) VERBOSE_FLAG=""; shift ;;
    --help)
      echo "Usage: $0 --dir <directory> [--no-verbose] [--no-verify] [--help]"
      echo "  --dir          Specify the directory containing images to check."
      echo "  --no-verbose   Disable verbose mode for the ImageMagick identify command."
      echo "  --no-verify    Disables crc32 verification of files that have a corresponding crc32-file"
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
if [ -z "$IMAGE_DIR" ]; then
  echo "Error: --dir option is required."
  echo "Use --help for usage information."
  exit 1
fi

# Check if the directory exists
if [ ! -d "$IMAGE_DIR" ]; then
  echo "Error: Directory $IMAGE_DIR does not exist."
  exit 1
fi

# Clear the output file if it exists
> "$OUTPUT_FILE"

echo "Checking image, video and audio files in $IMAGE_DIR and subdirectories for corruption..."

# Function to calculate the CRC checksum of a file
calculate_crc() {
  crc32 "$1" 2>/dev/null || cksum "$1" | awk '{print $1}' # Use crc32 or fallback to cksum
}

# Function to generate the .crc filename based on the hashed file path
generate_crc_filename() {
  local filepath="$1"
  local hash=$(echo -n "$filepath" | shasum -a 256 | awk '{print $1}') # Hash the full file path
  echo "$IMAGE_DIR/$hash.crc" # Store all .crc files in the root of the specified directory
}

# Find all JPG, JPEG, and PNG files in the directory and its subdirectories
find "$IMAGE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort | while read -r file; do
  # Generate a .crc filename based on the file path
  # crc_file=$(generate_crc_filename "$file")

  # Check for corresponding .crc file
  crc_file="${file}.crc32.txt"
  if [ -f "$crc_file" ] && [ $NO_VERIFY_FLAG -eq 0 ]; then
    # Perform CRC check
    calculated_crc=$(calculate_crc "$file")
    stored_crc=$(cat "$crc_file" | tr -d '\r\n') # Handle potential line endings
    if [ "$calculated_crc" != "$stored_crc" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - CRC mismatch: $file" >> "$OUTPUT_FILE"
      CORRUPT_FILES_FOUND=1
    fi
  else
    # Use ImageMagick's identify to check for corruption
    # If -verbose flag is not used, false negatives may occur 
    identify -regard-warnings $VERBOSE_FLAG "$file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Corrupt image: $file" >> "$OUTPUT_FILE"
      CORRUPT_FILES_FOUND=1
    else
      # If no errors found and .crc does not exist, create the .crc file
      calculate_crc "$file" > "$crc_file"
    fi
  fi
  
done

# Find common video file types and check them
find "$IMAGE_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.webm" -o -iname "*.mts" \) | sort | while read -r file; do
  # Check for corresponding .crc file
  crc_file="${file}.crc32.txt"
  if [ -f "$crc_file" ] && [ $NO_VERIFY_FLAG -eq 0 ]; then
   # Perform CRC check
    calculated_crc=$(calculate_crc "$file")
    stored_crc=$(cat "$crc_file" | tr -d '\r\n') # Handle potential line endings
    if [ "$calculated_crc" != "$stored_crc" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - CRC mismatch: $file" >> "$OUTPUT_FILE"
      CORRUPT_FILES_FOUND=1
    fi
  else
    # Use ffprobe to check for corruption
    ffprobe "$file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Corrupt video: $file" >> "$OUTPUT_FILE"
      CORRUPT_FILES_FOUND=1
    else
      # If no errors found and .crc does not exist, create the .crc file
      calculate_crc "$file" > "$crc_file"
    fi
  fi
done

# Find and sort MP3 files by name before checking
find "$IMAGE_DIR" -type f -iname "*.mp3" | sort | while read -r file; do
  # Use ffprobe to check for corruption
  ffprobe -v error -i "$file" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $file" >> "$OUTPUT_FILE"
    CORRUPT_FILES_FOUND=1
  fi
done

# Provide feedback to the user
#if [ -s "$OUTPUT_FILE" ]; then
if [ $CORRUPT_FILES_FOUND -eq 1 ]; then
  echo "Corrupt files found. Check $OUTPUT_FILE for details."
else
  echo "No corrupt files found."
fi
