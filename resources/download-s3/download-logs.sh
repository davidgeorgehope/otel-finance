#!/bin/bash

set -euo pipefail  # Exit on error, undefined variables are errors, fail on pipe errors

# Check if log type argument is provided
if [ "$#" -ne 1 ] || [[ ! "$1" =~ ^(full|truncated)$ ]]; then
    echo "Usage: $0 [full|truncated]"
    exit 1
fi

LOG_TYPE="$1"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Hardcoded S3 base URL and timestamps
S3_BASE="https://david-hope-elastic-snapshots.s3.us-east-2.amazonaws.com"
TIMESTAMP_FULL="20241028_133026"
TIMESTAMP_TRUNCATED="20241028_133026"
TIMESTAMP="${LOG_TYPE}_${TIMESTAMP_FULL}"
[[ "$LOG_TYPE" == "truncated" ]] && TIMESTAMP="${LOG_TYPE}_${TIMESTAMP_TRUNCATED}"

S3_URL="${S3_BASE}/logs_${TIMESTAMP}.tar.gz"

# Use home directory for temporary storage
TEMP_DIR="${HOME}/log_extract_${TIMESTAMP}"

echo "Found logs at $S3_URL"

echo "Downloading ${LOG_TYPE} logs..."

# Create temporary directories for processing
mkdir -p "$TEMP_DIR/process"
cd "$TEMP_DIR" || exit 1

# Download and extract to temp processing directory
curl -O "$S3_URL"
FILENAME=$(basename "$S3_URL")

echo "Extracting logs to temporary directory for processing..."
# Extract to process directory, maintaining full path
tar xzf "$FILENAME" -C "$TEMP_DIR/process"

echo "Adjusting dates in log files..."

# Dates in the logs (source dates)
LOG_DAY1=28  # Latest date in logs
LOG_DAY2=27
LOG_DAY3=26
LOG_DAY4=25  # Earliest date in logs
LOG_MONTH=Oct
LOG_MONTH_NUM=10
LOG_YEAR=2024
LOG_YEAR_SHORT=24

# Target dates (dates you want to replace with)
DAY1=$(date -d "today" +%d)         # Today's date
DAY2=$(date -d "1 day ago" +%d)     # 1 day ago
DAY3=$(date -d "2 days ago" +%d)    # 2 days ago
DAY4=$(date -d "3 days ago" +%d)    # 3 days ago
MONTH=$(date -d "today" +%b)        # Current month abbreviation
MONTH_NUM=$(date -d "today" +%m)    # Current month number
YEAR=$(date -d "today" +%Y)         # Current year
YEAR_SHORT=$(date -d "today" +%y)   # Current year in two digits

# Function to adjust dates in files
adjust_dates() {
    local file=$1
    echo "Processing $file"
    
    # Create a temporary file in a controlled location
    local temp_file="${file}.tmp"
    
    if [[ $file == *"access.log" ]]; then
        echo "Found access log, updating dates..."
        sed -e "s|\[${LOG_DAY1}/${LOG_MONTH}/${LOG_YEAR}:|\[${DAY1}/${MONTH}/${YEAR}:|g" \
            -e "s|\[${LOG_DAY2}/${LOG_MONTH}/${LOG_YEAR}:|\[${DAY2}/${MONTH}/${YEAR}:|g" \
            -e "s|\[${LOG_DAY3}/${LOG_MONTH}/${LOG_YEAR}:|\[${DAY3}/${MONTH}/${YEAR}:|g" \
            -e "s|\[${LOG_DAY4}/${LOG_MONTH}/${LOG_YEAR}:|\[${DAY4}/${MONTH}/${YEAR}:|g" \
            "$file" > "$temp_file" && mv "$temp_file" "$file"
    elif [[ $file == *"mysql.log" ]]; then
        sed -e "s|${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY1}|${YEAR}-${MONTH_NUM}-${DAY1}|g" \
            -e "s|${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY2}|${YEAR}-${MONTH_NUM}-${DAY2}|g" \
            -e "s|${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY3}|${YEAR}-${MONTH_NUM}-${DAY3}|g" \
            -e "s|${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY4}|${YEAR}-${MONTH_NUM}-${DAY4}|g" \
            "$file" > "$temp_file" && mv "$temp_file" "$file"
    elif [[ $file == *"mysql-slow.log" ]]; then
        sed -e "s|Time: ${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY1}|Time: ${YEAR}-${MONTH_NUM}-${DAY1}|g" \
            -e "s|Time: ${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY2}|Time: ${YEAR}-${MONTH_NUM}-${DAY2}|g" \
            -e "s|Time: ${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY3}|Time: ${YEAR}-${MONTH_NUM}-${DAY3}|g" \
            -e "s|Time: ${LOG_YEAR}-${LOG_MONTH_NUM}-${LOG_DAY4}|Time: ${YEAR}-${MONTH_NUM}-${DAY4}|g" \
            "$file" > "$temp_file" && mv "$temp_file" "$file"
    elif [[ $file == *"error.log" ]]; then
        if [[ $file == *"mysql"* ]]; then
            sed -e "s|${LOG_YEAR_SHORT}${LOG_MONTH_NUM}${LOG_DAY1}|${YEAR_SHORT}${MONTH_NUM}${DAY1}|g" \
                -e "s|${LOG_YEAR_SHORT}${LOG_MONTH_NUM}${LOG_DAY2}|${YEAR_SHORT}${MONTH_NUM}${DAY2}|g" \
                -e "s|${LOG_YEAR_SHORT}${LOG_MONTH_NUM}${LOG_DAY3}|${YEAR_SHORT}${MONTH_NUM}${DAY3}|g" \
                -e "s|${LOG_YEAR_SHORT}${LOG_MONTH_NUM}${LOG_DAY4}|${YEAR_SHORT}${MONTH_NUM}${DAY4}|g" \
                "$file" > "$temp_file" && mv "$temp_file" "$file"
        else
            sed -e "s|${LOG_YEAR}/${LOG_MONTH_NUM}/${LOG_DAY1}|${YEAR}/${MONTH_NUM}/${DAY1}|g" \
                -e "s|${LOG_YEAR}/${LOG_MONTH_NUM}/${LOG_DAY2}|${YEAR}/${MONTH_NUM}/${DAY2}|g" \
                -e "s|${LOG_YEAR}/${LOG_MONTH_NUM}/${LOG_DAY3}|${YEAR}/${MONTH_NUM}/${DAY3}|g" \
                -e "s|${LOG_YEAR}/${LOG_MONTH_NUM}/${LOG_DAY4}|${YEAR}/${MONTH_NUM}/${DAY4}|g" \
                "$file" > "$temp_file" && mv "$temp_file" "$file"
        fi
    fi

    # Clean up any stray temporary files
    rm -f "$temp_file"
}

# List of directories to process
DIRS=(
    "$TEMP_DIR/process/var/log/nginx_backend"
    "$TEMP_DIR/process/var/log/nginx_frontend"
    "$TEMP_DIR/process/var/log/mysql"
)

echo "Available directories:"
ls -la "$TEMP_DIR/process/var/log/"

# Process files in each directory
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Processing directory: $dir"
        find "$dir" -type f 2>/dev/null | while read -r file; do
            adjust_dates "$file"
        done
    else
        echo "Directory $dir does not exist, skipping."
    fi
done

echo "Moving processed files to /var/log..."
if [[ "$LOG_TYPE" == "full" ]]; then
    # For full logs, move with overwrite
    mv -f "$TEMP_DIR/process/var/log/nginx_backend/"* /var/log/nginx_backend/
    mv -f "$TEMP_DIR/process/var/log/nginx_frontend/"* /var/log/nginx_frontend/
    mv -f "$TEMP_DIR/process/var/log/mysql/"* /var/log/mysql/
else
    # For truncated logs, be more careful
    mv -n "$TEMP_DIR/process/var/log/nginx_backend/"* /var/log/nginx_backend/
    mv -n "$TEMP_DIR/process/var/log/nginx_frontend/"* /var/log/nginx_frontend/
    mv -n "$TEMP_DIR/process/var/log/mysql/"* /var/log/mysql/
fi

# Clean up
cd / || exit 1
rm -rf "$TEMP_DIR"

echo "${LOG_TYPE^} logs have been downloaded, extracted, and dates adjusted in /var/log"
echo "Files processed:"
find /var/log/nginx_* /var/log/mysql -type f 2>/dev/null | sort
