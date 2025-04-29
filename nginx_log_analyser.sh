#!/bin/bash

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
# Use gawk explicitly for mktime() function and IGNORECASE
# Filters common bots, finds first/last raw timestamps, and unique IP count.
# Optionally prints first seen line for each unique IP to stderr.
awk_results=$(eval "$log_stream_cmd" | \
gawk -v bot_regex="${BOT_PATTERN}" '
# Function to convert Nginx timestamp [DD/Mon/YYYY:HH:MM:SS +ZZZZ] to epoch for comparison
# Uses split() instead of sub() with backreferences
function nginx_ts_to_epoch(ts_str,   datetime_str, epoch, parts, n_parts, date_part, date_parts, n_date_parts, hh, mm, ss, dd, mon, yyyy, mktime_fmt) {

    gsub(/\[|\]/, "", ts_str)
    datetime_str = ts_str

    sub(/ [+].*/, "", datetime_str) # Remove timezone

    # Convert Month name to number - DO THIS FIRST
    gsub(/Jan/, "01", datetime_str); gsub(/Feb/, "02", datetime_str);
    gsub(/Mar/, "03", datetime_str); gsub(/Apr/, "04", datetime_str);
    gsub(/May/, "05", datetime_str); gsub(/Jun/, "06", datetime_str);
    gsub(/Jul/, "07", datetime_str); gsub(/Aug/, "08", datetime_str);
    gsub(/Sep/, "09", datetime_str); gsub(/Oct/, "10", datetime_str);
    gsub(/Nov/, "11", datetime_str); gsub(/Dec/, "12", datetime_str);

    # Split into date and time parts using ":"
    n_parts = split(datetime_str, parts, ":")
    if (n_parts != 4) { return -1 } # Basic validation

    hh = parts[2]; mm = parts[3]; ss = parts[4]; date_part = parts[1]

    # Split date part using "/"
    n_date_parts = split(date_part, date_parts, "/")
    if (n_date_parts != 3) { return -1 } # Basic validation
    dd = date_parts[1]; mon = date_parts[2]; yyyy = date_parts[3]

    # Construct the "YYYY MM DD HH MM SS" string for mktime
    mktime_fmt = sprintf("%s %s %s %s %s %s", yyyy, mon, dd, hh, mm, ss)

    # Convert to epoch using mktime
    epoch = mktime(mktime_fmt)

    return epoch
}

BEGIN {
    IGNORECASE = 1 # Enable case-insensitive regex matching
    min_epoch = -1
    max_epoch = -1
    first_ts_str = "N/A" # Initialize to N/A
    last_ts_str = "N/A"  # Initialize to N/A
    unique_ips = 0
    # seen_ips array will track unique IPs encountered
}

# Main processing block for each line
{
    # FILTER: Skip line if it matches the bot regex
    if ($0 ~ bot_regex) {
        next # Skip to the next log line immediately
    }

    # --- Process lines that were NOT filtered ---

    # Count unique IPs and print first line seen for debugging (optional)
    ip_addr = $1
    if (!(ip_addr in seen_ips)) {
        unique_ips++
        seen_ips[ip_addr] = 1
        # Uncomment the next line to print debug info to stderr
        # print "[DEBUG NEW IP] " $0 > "/dev/stderr"
    }

    # Extract timestamp using regex - find [DD/Mon/YYYY:HH:MM:SS +ZZZZ]
    if (match($0, /\[([^]]+)\]/, ts_match)) {
        current_ts_str = ts_match[1] # The part inside brackets

        current_epoch = nginx_ts_to_epoch(current_ts_str) # Convert to epoch for comparison

        if (current_epoch != -1) { # If conversion succeeded
             # Check for first timestamp
             if (min_epoch == -1 || current_epoch < min_epoch) {
                 min_epoch = current_epoch
                 first_ts_str = current_ts_str
             }
             # Check for last timestamp
             if (max_epoch == -1 || current_epoch > max_epoch) {
                 max_epoch = current_epoch
                 last_ts_str = current_ts_str
             }
        }
    }
}

# After processing all lines
END {
    # Ensure N/A is printed if no valid timestamps were ever found
    if (first_ts_str == "") first_ts_str = "N/A"
    if (last_ts_str == "") last_ts_str = "N/A"
    # Final output to stdout: First TS string, Last TS string, IP count
    print first_ts_str, last_ts_str, unique_ips
}
')

# --- Parse AWK Results ---
# Assume timestamps dont contain newlines, rely on awk output format
# Read the last field first (IP count), then reconstruct timestamps
ip_count="${awk_results##* }" # Get everything after the last space (IP count)
ts_part="${awk_results% *}"    # Get everything before the last space (both timestamps)

# Check if parsing likely failed
if [[ -z "$ip_count" || ! "$ip_count" =~ ^[0-9]+$ ]]; then
     if [[ -z "$awk_results" ]]; then
        echo "Error: AWK command produced no output. Check permissions or log stream."
     else
        echo "Error: Failed to parse AWK output correctly."
        echo "AWK results line: '$awk_results'"
     fi
     # Check if only N/A N/A was printed before the (invalid) count
     if [[ "$ts_part" == "N/A N/A" ]]; then
        echo "Warning: No valid (non-bot) timestamps found." >&2
        first_ts="N/A"
        last_ts="N/A"
        ip_count=0 # Set count to 0 if timestamps also failed
     else
        exit 1
     fi
fi

# Separate the two timestamps using regex matching
if [[ "$ts_part" =~ ^(.*[0-9]{4})\ (.*)$ ]]; then
    first_ts="${BASH_REMATCH[1]}"
    last_ts="${BASH_REMATCH[2]}"
else
    # Fallback or error if the split didn't work as expected
    first_ts="Error Parsing"
    last_ts="$ts_part" # Put everything here if split failed
    # If both are N/A, handle that too
    if [[ "$ts_part" == "N/A N/A" ]]; then
        first_ts="N/A"
        last_ts="N/A"
    fi
fi


# --- Display Results ---
echo "--------------------------------------------------"
echo "Log Timeframe (Raw Timestamps, Common Bots Excluded):"
echo "  Earliest Timestamp Found: $first_ts"
echo "  Latest Timestamp Found:   $last_ts"
echo "--------------------------------------------------"
echo "IP Address Analysis (Common Bots Excluded):"
echo "  Total unique source IP addresses: $ip_count"
echo "--------------------------------------------------"
echo "Analysis complete." # Add note about debug if uncommented
# If you uncommented the debug print in gawk, add:
# echo "Debug lines for first appearance of each non-bot IP may have been printed above to stderr."


exit 0
