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
    echo "Processing $file"
    
    if [[ $file == *"access.log" ]]; then
        echo "Found access log, updating dates..."
        # Debug: show content before
        echo "Before update:"
        head -n 1 "$file"
        
        # Replace each source date with target date
        sed -i 's|\[22\/Oct\/2024:|\[26\/Oct\/2024:|g' "$file"
        sed -i 's|\[23\/Oct\/2024:|\[27\/Oct\/2024:|g' "$file"
        sed -i 's|\[24\/Oct\/2024:|\[28\/Oct\/2024:|g' "$file"
        
        # Debug: show content after
        echo "After update:"
        head -n 1 "$file"
    elif [[ $file == *"mysql.log" ]]; then
        # MySQL general format
        sed -i 's|2024-10-22|2024-10-26|g' "$file"
        sed -i 's|2024-10-23|2024-10-27|g' "$file"
        sed -i 's|2024-10-24|2024-10-28|g' "$file"
    elif [[ $file == *"mysql-slow.log" ]]; then
        # MySQL slow query format
        sed -i 's|Time: 2024-10-22|Time: 2024-10-26|g' "$file"
        sed -i 's|Time: 2024-10-23|Time: 2024-10-27|g' "$file"
        sed -i 's|Time: 2024-10-24|Time: 2024-10-28|g' "$file"
    elif [[ $file == *"error.log" ]]; then
        if [[ $file == *"mysql"* ]]; then
            # MySQL error log format
            sed -i 's|241022|241026|g' "$file"
            sed -i 's|241023|241027|g' "$file"
            sed -i 's|241024|241028|g' "$file"
        else
            # Nginx error log format
            sed -i 's|2024\/10\/22|2024\/10\/26|g' "$file"
            sed -i 's|2024\/10\/23|2024\/10\/27|g' "$file"
            sed -i 's|2024\/10\/24|2024\/10\/28|g' "$file"
        fi
    fi
}

# Process all relevant log files
find /var/log/nginx_* /var/log/mysql -type f 2>/dev/null | while read -r file; do
    adjust_dates "$file"
done

# Clean up
cd / || exit 1
rm -rf "$TEMP_DIR"

echo "Truncated logs have been downloaded and extracted to /var/log"
echo "Files extracted:"
find /var/log/nginx_* /var/log/mysql -type f 2>/dev/null | sort