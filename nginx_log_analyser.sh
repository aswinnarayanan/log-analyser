#!/bin/bash
#hello
# --- Configuration ---
# Directory containing the Nginx log files
LOG_DIR="/var/log/nginx"
# Pattern to match the log files (adjust if needed)
LOG_PATTERN="access.log*"

# Regex pattern to identify common bots (adjust as needed)
# Case-insensitive matching will be enabled in gawk
BOT_PATTERN="UptimeRobot|Googlebot|Bingbot|Baiduspider|YandexBot|DuckDuckBot|SemrushBot|AhrefsBot|MJ12bot|DotBot|PetalBot|facebookexternalhit|python|curl|wget|HeadlessChrome|\\b(bot|spider|crawler)\\b"
# Note: \b ensures "bot" matches as a whole word, not part of "robot" (though UptimeRobot is listed separately)

# --- End Configuration ---

echo "Analyzing Nginx logs in ${LOG_DIR} matching '${LOG_PATTERN}'..."
echo "Excluding requests matching common bot pattern: ${BOT_PATTERN}"
# Uncomment the next line to print first lines for debugging
# echo "Printing first log line for each new unique IP to stderr for debugging..."
echo "--------------------------------------------------"

# --- Find Log Files and Create Stream Command ---
# Use find for robustness with filenames. Use zcat -f to handle both compressed (.gz) and plain text.
log_stream_cmd="find \"${LOG_DIR}\" -name \"${LOG_PATTERN}\" -print0 | xargs -0 zcat -f"

# Check if any files are found
if ! find "${LOG_DIR}" -name "${LOG_PATTERN}" -print -quit | grep -q .; then
    echo "Error: No log files found matching '${LOG_PATTERN}' in ${LOG_DIR}"
    exit 1
fi

echo "Processing logs with gawk..."

# --- Process Stream with GAWK ---
# Updated to calculate unique users per month
awk_results
