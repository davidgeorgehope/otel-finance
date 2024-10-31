#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Hardcoded S3 base URL and filename
S3_BASE="https://david-hope-elastic-snapshots.s3.us-east-2.amazonaws.com"
TIMESTAMP="20241024_190458"
S3_URL="${S3_BASE}/logs_truncated_${TIMESTAMP}.tar.gz"

# Use home directory for temporary storage
TEMP_DIR="${HOME}/log_extract_${TIMESTAMP}"

echo "Downloading truncated logs from $S3_URL..."

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

# Download and extract
curl -O "$S3_URL"
FILENAME=$(basename "$S3_URL")

echo "Extracting logs to /var/log..."
# Extract and strip the var/log/log prefix from paths
tar xzf "$FILENAME" -C /var/log --strip-components=3

echo "Adjusting dates in log files..."

# Calculate target dates (last 3 days, excluding today)
TODAY=$(date +%Y%m%d)
DAY3=$(date -d "3 days ago" +%Y%m%d)
DAY2=$(date -d "2 days ago" +%Y%m%d)
DAY1=$(date -d "1 day ago" +%Y%m%d)

# Function to adjust dates in files
adjust_dates() {
    local file=$1
    # Nginx access logs format
    sed -i -E "s/\[([0-9]{2})\/Oct\/2024:/\[28\/Oct\/2024:/g" "$file"
    sed -i -E "s/\[([0-9]{2})\/Oct\/2024:/\[27\/Oct\/2024:/g" "$file"
    sed -i -E "s/\[([0-9]{2})\/Oct\/2024:/\[26\/Oct\/2024:/g" "$file"

    # MySQL general format
    sed -i -E "s/2024-10-[0-9]{2}/2024-10-28/g" "$file"
    sed -i -E "s/2024-10-[0-9]{2}/2024-10-27/g" "$file"
    sed -i -E "s/2024-10-[0-9]{2}/2024-10-26/g" "$file"

    # MySQL slow query format
    sed -i -E "s/Time: 2024-10-[0-9]{2}/Time: 2024-10-28/g" "$file"
    sed -i -E "s/Time: 2024-10-[0-9]{2}/Time: 2024-10-27/g" "$file"
    sed -i -E "s/Time: 2024-10-[0-9]{2}/Time: 2024-10-26/g" "$file"

    # MySQL error log format
    sed -i -E "s/241[0-9]{3}/241028/g" "$file"
    sed -i -E "s/241[0-9]{3}/241027/g" "$file"
    sed -i -E "s/241[0-9]{3}/241026/g" "$file"

    # Nginx error log format
    sed -i -E "s/2024\/10\/[0-9]{2}/2024\/10\/28/g" "$file"
    sed -i -E "s/2024\/10\/[0-9]{2}/2024\/10\/27/g" "$file"
# Clean up
cd / || exit 1
rm -rf "$TEMP_DIR"

echo "Truncated logs have been downloaded and extracted to /var/log"
echo "Files extracted:"
find /var/log/nginx_* /var/log/mysql -type f 2>/dev/null | sort