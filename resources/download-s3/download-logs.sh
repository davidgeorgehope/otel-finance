#!/bin/bash

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
TIMESTAMP_TRUNCATED="20241024_190458"
TIMESTAMP="${LOG_TYPE}_${TIMESTAMP_FULL}"
[[ "$LOG_TYPE" == "truncated" ]] && TIMESTAMP="${LOG_TYPE}_${TIMESTAMP_TRUNCATED}"

S3_URL="${S3_BASE}/logs_${TIMESTAMP}.tar.gz"

# Use home directory for temporary storage
TEMP_DIR="${HOME}/log_extract_${TIMESTAMP}"

echo "Found logs at $S3_URL"

# Only show warning and prompt for full logs
if [[ "$LOG_TYPE" == "full" ]]; then
    echo "Warning: This will overwrite existing log files in /var/log"
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
fi

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

# Calculate complete target dates
DAY4=$(date -d "4 days ago" +%d)
DAY3=$(date -d "3 days ago" +%d)
DAY2=$(date -d "2 days ago" +%d)
DAY1=$(date -d "1 day ago" +%d)
MONTH=$(date -d "1 day ago" +%b)  # Month abbreviation (Jan, Feb, etc.)
MONTH_NUM=$(date -d "1 day ago" +%m)  # Month number (01-12)
YEAR=$(date -d "1 day ago" +%Y)
YEAR_SHORT=$(date -d "1 day ago" +%y)

# Function to adjust dates in files
adjust_dates() {
    local file=$1
    echo "Processing $file"
    
    if [[ $file == *"access.log" ]]; then
        echo "Found access log, updating dates..."
        # Debug: show content before
        echo "Before update:"
        head -n 1 "$file"
        
        # Replace fixed source dates with fully dynamic dates
        sed -i "s|\[22\/Oct\/2024:|\[${DAY4}\/${MONTH}\/${YEAR}:|g" "$file"
        sed -i "s|\[23\/Oct\/2024:|\[${DAY3}\/${MONTH}\/${YEAR}:|g" "$file"
        sed -i "s|\[24\/Oct\/2024:|\[${DAY2}\/${MONTH}\/${YEAR}:|g" "$file"
        sed -i "s|\[25\/Oct\/2024:|\[${DAY1}\/${MONTH}\/${YEAR}:|g" "$file"
        
        # Debug: show content after
        echo "After update:"
        head -n 1 "$file"
    elif [[ $file == *"mysql.log" ]]; then
        # MySQL general format
        sed -i "s|2024-10-22|${YEAR}-${MONTH_NUM}-${DAY4}|g" "$file"
        sed -i "s|2024-10-23|${YEAR}-${MONTH_NUM}-${DAY3}|g" "$file"
        sed -i "s|2024-10-24|${YEAR}-${MONTH_NUM}-${DAY2}|g" "$file"
        sed -i "s|2024-10-25|${YEAR}-${MONTH_NUM}-${DAY1}|g" "$file"
    elif [[ $file == *"mysql-slow.log" ]]; then
        # MySQL slow query format
        sed -i "s|Time: 2024-10-22|Time: ${YEAR}-${MONTH_NUM}-${DAY4}|g" "$file"
        sed -i "s|Time: 2024-10-23|Time: ${YEAR}-${MONTH_NUM}-${DAY3}|g" "$file"
        sed -i "s|Time: 2024-10-24|Time: ${YEAR}-${MONTH_NUM}-${DAY2}|g" "$file"
        sed -i "s|Time: 2024-10-25|Time: ${YEAR}-${MONTH_NUM}-${DAY1}|g" "$file"
    elif [[ $file == *"error.log" ]]; then
        if [[ $file == *"mysql"* ]]; then
            # MySQL error log format
            sed -i "s|241022|${YEAR_SHORT}${MONTH_NUM}${DAY4}|g" "$file"
            sed -i "s|241023|${YEAR_SHORT}${MONTH_NUM}${DAY3}|g" "$file"
            sed -i "s|241024|${YEAR_SHORT}${MONTH_NUM}${DAY2}|g" "$file"
            sed -i "s|241025|${YEAR_SHORT}${MONTH_NUM}${DAY1}|g" "$file"
        else
            # Nginx error log format
            sed -i "s|2024\/10\/22|${YEAR}\/${MONTH_NUM}\/${DAY4}|g" "$file"
            sed -i "s|2024\/10\/23|${YEAR}\/${MONTH_NUM}\/${DAY3}|g" "$file"
            sed -i "s|2024\/10\/24|${YEAR}\/${MONTH_NUM}\/${DAY2}|g" "$file"
            sed -i "s|2024\/10\/25|${YEAR}\/${MONTH_NUM}\/${DAY1}|g" "$file"
        fi
    fi
}

# Debug: show what directories exist
echo "Available directories:"
ls -la "$TEMP_DIR/process/var/log/"

# Process files in temporary directory first
find "$TEMP_DIR/process/var/log/nginx_backend" "$TEMP_DIR/process/var/log/nginx_frontend" "$TEMP_DIR/process/var/log/mysql" -type f 2>/dev/null | while read -r file; do
    adjust_dates "$file"
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