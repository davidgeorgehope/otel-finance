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

# Adjust dates in logs
echo "Adjusting dates in log files..."

# Function to adjust dates in log files
adjust_dates() {
    log_file="$1"
    echo "Processing $log_file"

    # Read the entire file into a variable
    file_content=$(cat "$log_file")

    # Generate dates for the last 3 days (excluding today)
    date_offsets=(3 2 1)
    declare -A new_dates
    for offset in "${date_offsets[@]}"; do
        date_key=$(date -d "-$offset day" '+%Y-%m-%d')
        new_dates[$offset]=$date_key
    done

    # Patterns and replacements for different log formats
    declare -A patterns
    # Nginx access log: [25/Oct/2024:21:55:00 +0000]
    patterns["nginx_access"]='\[[0-9]{2}/[A-Za-z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}\]'
    # Nginx error log: 2024/10/25 20:04:58
    patterns["nginx_error"]='[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
    # MySQL general log: 2024-10-27 02:27:33.070065
    patterns["mysql_general"]='[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?'
    # MySQL slow log: # Time: 2024-10-27 09:38:58
    patterns["mysql_slow"]='# Time: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
    # MySQL error log: 241028 13:30:08
    patterns["mysql_error"]='[0-9]{6} [0-9]{2}:[0-9]{2}:[0-9]{2}'

    # For each pattern, perform replacements
    for pattern_name in "${!patterns[@]}"; do
        pattern="${patterns[$pattern_name]}"
        # Extract dates matching the pattern
        original_dates=$(echo "$file_content" | grep -oE "$pattern" | sort | uniq)
        index=0
        for orig_date in $original_dates; do
            index=$(( (index % 3) + 1 ))  # Cycle through 1 to 3
            new_date="${new_dates[$index]}"

            case $pattern_name in
                nginx_access)
                    # Extract date part
                    old_date=$(echo "$orig_date" | grep -oE '[0-9]{2}/[A-Za-z]{3}/[0-9]{4}')
                    new_date_formatted=$(date -d "$new_date" '+%d/%b/%Y')
                    # Construct full original and new date strings
                    old_datetime="$orig_date"
                    new_datetime=$(echo "$orig_date" | sed "s|$old_date|$new_date_formatted|")
                    # Escape characters
                    old_datetime_esc=$(echo "$old_datetime" | sed 's/[\/&]/\\&/g')
                    new_datetime_esc=$(echo "$new_datetime" | sed 's/[\/&]/\\&/g')
                    # Replace
                    file_content=$(echo "$file_content" | sed "s/$old_datetime_esc/$new_datetime_esc/g")
                    ;;
                nginx_error)
                    old_date=$(echo "$orig_date" | grep -oE '^[0-9]{4}/[0-9]{2}/[0-9]{2}')
                    new_date_formatted=$(date -d "$new_date" '+%Y/%m/%d')
                    old_datetime="$orig_date"
                    new_datetime=$(echo "$orig_date" | sed "s|$old_date|$new_date_formatted|")
                    old_datetime_esc=$(echo "$old_datetime" | sed 's/[\/&]/\\&/g')
                    new_datetime_esc=$(echo "$new_datetime" | sed 's/[\/&]/\\&/g')
                    # Replace
                    file_content=$(echo "$file_content" | sed "s/$old_datetime_esc/$new_datetime_esc/g")
                    ;;
                mysql_general)
                    old_date=$(echo "$orig_date" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
                    new_date_formatted="$new_date"
                    old_datetime="$orig_date"
                    new_datetime=$(echo "$orig_date" | sed "s|$old_date|$new_date_formatted|")
                    # Escape special characters
                    old_datetime_esc=$(echo "$old_datetime" | sed 's/[\.\/&]/\\&/g')
                    new_datetime_esc=$(echo "$new_datetime" | sed 's/[\.\/&]/\\&/g')
                    # Replace
                    file_content=$(echo "$file_content" | sed "s/$old_datetime_esc/$new_datetime_esc/g")
                    ;;
                mysql_slow)
                    old_date=$(echo "$orig_date" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
                    new_date_formatted="$new_date"
                    old_datetime="$orig_date"
                    new_datetime="# Time: $new_date_formatted $(echo "$orig_date" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}')"
                    # Escape special characters
                    old_datetime_esc=$(echo "$old_datetime" | sed 's/[ #\.\/&]/\\&/g')
                    new_datetime_esc=$(echo "$new_datetime" | sed 's/[ #\.\/&]/\\&/g')
                    # Replace
                    file_content=$(echo "$file_content" | sed "s/$old_datetime_esc/$new_datetime_esc/g")
                    ;;
                mysql_error)
                    old_date=$(echo "$orig_date" | grep -oE '^[0-9]{6}')
                    new_date_formatted=$(date -d "$new_date" '+%y%m%d')
                    old_datetime="$orig_date"
                    new_datetime=$(echo "$orig_date" | sed "s|$old_date|$new_date_formatted|")
                    # Escape special characters
                    old_datetime_esc=$(echo "$old_datetime" | sed 's/[\/&]/\\&/g')
                    new_datetime_esc=$(echo "$new_datetime" | sed 's/[\/&]/\\&/g')
                    # Replace
                    file_content=$(echo "$file_content" | sed "s/$old_datetime_esc/$new_datetime_esc/g")
                    ;;
                *)
                    continue
                    ;;
            esac
        done
    done

    # Write the modified content back to the file
    echo "$file_content" > "$log_file"
}

# Find and process log files
log_files=$(find /var/log/nginx* /var/log/mysql -type f \( -name "*.log*" -o -name "*.err*" \) 2>/dev/null)

for file in $log_files; do
    adjust_dates "$file"
done

# Clean up
cd / || exit 1
rm -rf "$TEMP_DIR"

echo "Truncated logs have been downloaded, extracted to /var/log, and dates adjusted."
echo "Files extracted and processed:"
echo "$log_files"