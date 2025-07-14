#!/bin/bash
# --- Configuration ---
# Directory containing the Nginx log files
LOG_DIR="/var/log/nginx"
# Pattern to match the log files (adjust if needed)
LOG_PATTERN="access.log*"

# Regex pattern to identify common bots (adjust as needed)
BOT_PATTERN="UptimeRobot|Googlebot|Bingbot|Baiduspider|YandexBot|DuckDuckBot|SemrushBot|AhrefsBot|MJ12bot|DotBot|PetalBot|facebookexternalhit|python|curl|wget|HeadlessChrome|\\b(bot|spider|crawler)\\b"

# --- End Configuration ---

echo "Analyzing Nginx logs in ${LOG_DIR} matching '${LOG_PATTERN}'..."
echo "Excluding requests matching common bot pattern: ${BOT_PATTERN}"
echo "--------------------------------------------------"

# --- Find Log Files and Create Stream Command ---
log_stream_cmd="find \"${LOG_DIR}\" -name \"${LOG_PATTERN}\" -print0 | xargs -0 zcat -f"

# Check if any files are found
if ! find "${LOG_DIR}" -name "${LOG_PATTERN}" -print -quit | grep -q .; then
    echo "Error: No log files found matching '${LOG_PATTERN}' in ${LOG_DIR}"
    exit 1
fi

# Process logs with gawk
eval "${log_stream_cmd}" | gawk -v IGNORECASE=1 -v bot_pattern="${BOT_PATTERN}" '
    # Regex to extract IP and timestamp
    match($0, /^([^ ]+) .* \[([0-9]{2}\/[A-Za-z]+\/[0-9]{4}):/, groups) {
        ip = groups[1]
        timestamp = groups[2]
        
        # Extract month and year (e.g., "Jan/2023")
        split(timestamp, date_parts, "/")
        month_year = date_parts[2] "/" date_parts[3]

        # Skip if the line matches the bot pattern
        if ($0 ~ bot_pattern) {
            next
        }

        # Track unique IPs per month
        unique_ips[month_year][ip] = 1
    }
    END {
        # Output the count of unique IPs per month
        for (month in unique_ips) {
            count = length(unique_ips[month])
            print month ": " count " unique users"
        }
    }
'