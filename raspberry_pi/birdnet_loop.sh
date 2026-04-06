#!/bin/bash

# ===== CONFIG =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
COOLDOWN_FILE="$HOME/birdnet_logs/cooldown.txt"

RECORDINGS_DIR="$HOME/birdnet_recordings"
LOGS_DIR="$HOME/birdnet_logs"
CHECKPOINTS_DIR="$HOME/birdnet_checkpoints"

# Capture device is auto-detected at startup.
DEVICE=""

# Recording settings
DURATION=15  # 15 seconds per recording
# Using 48kHz sample rate for high quality bird call detection

# Optional: Keep a rolling log of last 24 hours only
ROLLING_LOG="$LOGS_DIR/last_24h.csv"
LOG_MAX_LINES=10000  # Approximately 24 hours of detections

# ===== LOAD CONFIG FROM YAML =====
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "⚠ Warning: config.yaml not found. Using defaults."
        MIN_CONF=0.2
        COOLDOWN_SECONDS=1800
        return
    fi
    
    # Parse YAML config
    MIN_CONF=$(grep "^min_confidence:" "$CONFIG_FILE" | awk '{print $2}')
    COOLDOWN_SECONDS=$(grep "^cooldown_seconds:" "$CONFIG_FILE" | awk '{print $2}')
    QUIET_START=$(grep "^  start:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    QUIET_END=$(grep "^  end:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    HA_WEBHOOK=$(grep "^home_assistant_webhook:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    
    # Parse AWS settings
    AWS_ENABLED=$(grep "^  enabled:" "$CONFIG_FILE" | awk '{print $2}')
    AWS_API_URL=$(grep "^  api_url:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    AWS_API_KEY=$(grep "^  api_key:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    
    # Parse location settings
    LATITUDE=$(grep "^  latitude:" "$CONFIG_FILE" | awk '{print $2}')
    LONGITUDE=$(grep "^  longitude:" "$CONFIG_FILE" | awk '{print $2}')
    
    # Parse analysis settings
    SENSITIVITY=$(grep "^  sensitivity:" "$CONFIG_FILE" | awk '{print $2}')
    OVERLAP=$(grep "^  overlap:" "$CONFIG_FILE" | awk '{print $2}')
    NORMALIZE_AUDIO=$(grep "^  normalize_audio:" "$CONFIG_FILE" | awk '{print $2}')
    
    # Load interesting species list
    INTERESTING_SPECIES=()
    in_interesting=false
    in_ignore=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^interesting_species: ]]; then
            in_interesting=true
            in_ignore=false
        elif [[ "$line" =~ ^ignore_species: ]]; then
            in_ignore=true
            in_interesting=false
        elif [[ "$line" =~ ^[a-z_]+: ]]; then
            in_interesting=false
            in_ignore=false
        elif $in_interesting && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"(.+)\" ]]; then
            INTERESTING_SPECIES+=("${BASH_REMATCH[1]}")
        elif $in_ignore && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"(.+)\" ]]; then
            IGNORE_SPECIES+=("${BASH_REMATCH[1]}")
        fi
    done < "$CONFIG_FILE"
    
    echo "Loaded config:"
    echo "  Min confidence: $MIN_CONF"
    if [ -n "$SENSITIVITY" ]; then
        echo "  Sensitivity: $SENSITIVITY"
    fi
    if [ -n "$OVERLAP" ]; then
        echo "  Overlap: ${OVERLAP}s"
    fi
    if [ "$NORMALIZE_AUDIO" = "true" ]; then
        echo "  Audio normalization: enabled"
    fi
    echo "  Cooldown: ${COOLDOWN_SECONDS}s"
    echo "  Interesting species: ${#INTERESTING_SPECIES[@]}"
    echo "  Ignore species: ${#IGNORE_SPECIES[@]}"
    if [ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ]; then
        echo "  Location: $LATITUDE, $LONGITUDE"
    fi
    if [ -n "$QUIET_START" ]; then
        echo "  Quiet hours: $QUIET_START - $QUIET_END"
    fi
    if [ -n "$HA_WEBHOOK" ]; then
        echo "  Webhook: $HA_WEBHOOK"
    else
        echo "  Webhook: NOT CONFIGURED"
    fi
    if [ "$AWS_ENABLED" = "true" ] && [ -n "$AWS_API_URL" ]; then
        echo "  AWS logging: enabled"
    fi
}

# Check if we're in quiet hours
is_quiet_hours() {
    if [ -z "$QUIET_START" ] || [ -z "$QUIET_END" ]; then
        return 1  # No quiet hours configured
    fi
    
    current_time=$(date +%H:%M)
    
    # Convert times to minutes for easier comparison
    current_mins=$(date +%H%M)
    start_mins=${QUIET_START/:/}
    end_mins=${QUIET_END/:/}
    
    # Handle overnight quiet hours (e.g., 22:00 - 07:00)
    if [ "$start_mins" -gt "$end_mins" ]; then
        if [ "$current_mins" -ge "$start_mins" ] || [ "$current_mins" -lt "$end_mins" ]; then
            return 0  # In quiet hours
        fi
    else
        if [ "$current_mins" -ge "$start_mins" ] && [ "$current_mins" -lt "$end_mins" ]; then
            return 0  # In quiet hours
        fi
    fi
    
    return 1  # Not in quiet hours
}

# Check if species should be ignored
should_ignore_species() {
    local species="$1"
    for ignore in "${IGNORE_SPECIES[@]}"; do
        if [ "$species" = "$ignore" ]; then
            return 0  # Should ignore
        fi
    done
    return 1  # Don't ignore
}

# Check if species is interesting (if list is configured)
is_interesting_species() {
    local species="$1"
    
    # If no interesting species configured, all are interesting
    if [ ${#INTERESTING_SPECIES[@]} -eq 0 ]; then
        return 0
    fi
    
    for interesting in "${INTERESTING_SPECIES[@]}"; do
        if [ "$species" = "$interesting" ]; then
            return 0  # Is interesting
        fi
    done
    return 1  # Not interesting
}

# Auto-detect capture device, preferring USB microphones.
detect_audio_device() {
    local line
    local card
    local dev

    line=$(arecord -l 2>/dev/null | awk '
        /card [0-9]+: .*device [0-9]+:/ && ($0 ~ /USB|Saramonic|PnP|Audio Device/) {print; exit}
    ')

    # Fallback: first available capture device.
    if [ -z "$line" ]; then
        line=$(arecord -l 2>/dev/null | awk '/card [0-9]+: .*device [0-9]+:/ {print; exit}')
    fi

    if [ -z "$line" ]; then
        echo "❌ No capture device found (arecord -l returned no input devices)."
        return 1
    fi

    card=$(echo "$line" | sed -E 's/.*card ([0-9]+):.*/\1/')
    dev=$(echo "$line" | sed -E 's/.*device ([0-9]+):.*/\1/')

    if [ -z "$card" ] || [ -z "$dev" ]; then
        echo "❌ Failed to parse capture device from: $line"
        return 1
    fi

    DEVICE="plughw:${card},${dev}"
    echo "  Audio input: $DEVICE"
    return 0
}

# Check cooldown for species
check_cooldown() {
    local species="$1"
    local current_time=$(date +%s)
    local last_alert=""
    local time_diff=0

    # Allow disabling cooldown via config.
    if [ -z "$COOLDOWN_SECONDS" ] || [ "$COOLDOWN_SECONDS" -le 0 ]; then
        return 0
    fi
    
    # Create cooldown file if it doesn't exist
    touch "$COOLDOWN_FILE"
    
    # Check if species was recently alerted
    if grep -q "^$species|" "$COOLDOWN_FILE"; then
        # Use only the most recent numeric timestamp for this species.
        last_alert=$(grep "^$species|" "$COOLDOWN_FILE" | tail -n 1 | cut -d'|' -f2 | tr -cd '0-9')

        if [ -n "$last_alert" ]; then
            time_diff=$((current_time - last_alert))
        fi
        
        if [ $time_diff -lt $COOLDOWN_SECONDS ]; then
            return 1  # Still in cooldown
        fi
    fi
    
    # Update cooldown file
    grep -v "^$species|" "$COOLDOWN_FILE" > "$COOLDOWN_FILE.tmp" 2>/dev/null
    echo "$species|$current_time" >> "$COOLDOWN_FILE.tmp"
    mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"
    
    return 0  # Not in cooldown, can alert
}

# Log detection to AWS (runs in background, non-blocking)
log_to_aws() {
    local species="$1"
    local confidence="$2"
    local timestamp="$3"
    local alerted="$4"  # true or false
    
    if [ "$AWS_ENABLED" != "true" ] || [ -z "$AWS_API_URL" ] || [ -z "$AWS_API_KEY" ]; then
        return  # AWS not configured
    fi
    
    # Send in background, don't wait for response
    (curl -X POST "$AWS_API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $AWS_API_KEY" \
        -d "{\"species\":\"$species\",\"confidence\":$confidence,\"timestamp\":\"$timestamp\",\"alerted\":$alerted}" \
        --max-time 10 \
        -s -S > /dev/null 2>&1) &
}

# Send alert to Home Assistant
send_alert() {
    local species="$1"
    local confidence="$2"
    local timestamp="$3"
    
    # Send to Home Assistant (existing)
    if [ -n "$HA_WEBHOOK" ]; then
        echo "  📲 Sending alert to Home Assistant..."
        
        local payload="{\"species\":\"$species\",\"confidence\":$confidence,\"timestamp\":\"$timestamp\"}"
        echo "     DEBUG: URL=$HA_WEBHOOK"
        echo "     DEBUG: Payload=$payload"
        
        response=$(curl -X POST "$HA_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 5 \
            -s -S -w "\nHTTP_CODE:%{http_code}" 2>&1)
        
        http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
        
        if [ "$http_code" = "200" ]; then
            echo "     ✅ Alert sent successfully (HTTP $http_code)"
        else
            echo "     ❌ Alert failed (HTTP $http_code)"
            echo "     Error: $response"
        fi
    fi
    
    # Send to AWS (new - non-blocking)
    if [ "$AWS_ENABLED" = "true" ] && [ -n "$AWS_API_URL" ]; then
        echo "  ☁️  Logging to AWS..."
        log_to_aws "$species" "$confidence" "$timestamp" "true"
    fi
}

# ===== SETUP =====
mkdir -p "$RECORDINGS_DIR"
mkdir -p "$LOGS_DIR"
mkdir -p "$CHECKPOINTS_DIR"

# Initialize rolling log with header if it doesn't exist
if [ ! -f "$ROLLING_LOG" ]; then
    echo "Timestamp,Start (s),End (s),Scientific name,Common name,Confidence,Filepath" > "$ROLLING_LOG"
fi

echo "Starting BirdNET loop with filtering..."
echo "Recording dir: $RECORDINGS_DIR"
echo "Logs dir: $LOGS_DIR"
echo ""

load_config
if ! detect_audio_device; then
    echo "Exiting: no usable audio capture device detected."
    exit 1
fi
echo ""

# ===== GRACEFUL SHUTDOWN =====
trap 'echo "Shutting down..."; exit 0' SIGINT SIGTERM

# ===== LOOP =====
while true
do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    FILE="audio_$TIMESTAMP.wav"
    FULL_PATH="$RECORDINGS_DIR/$FILE"

    echo "[$(date '+%H:%M:%S')] Recording..."

    # Record audio at 48kHz (high quality)
    arecord -D $DEVICE -f S16_LE -r 48000 -c 1 -d $DURATION "$FULL_PATH" 2>/dev/null

    # Validate file exists and is not empty
    if [ ! -s "$FULL_PATH" ]; then
        echo "  ⚠ Recording failed. Skipping..."
        rm -f "$FULL_PATH" 2>/dev/null
        continue
    fi

    # Normalize audio if enabled (improves detection of distant/quiet birds)
    if [ "$NORMALIZE_AUDIO" = "true" ]; then
        if command -v sox &> /dev/null; then
            sox "$FULL_PATH" "${FULL_PATH}.norm.wav" norm -3 2>/dev/null
            if [ -s "${FULL_PATH}.norm.wav" ]; then
                mv "${FULL_PATH}.norm.wav" "$FULL_PATH"
            fi
        fi
    fi

    # Run BirdNET via Docker with persistent model cache
    echo "  🔎 Analyzing..."
    ANALYZE_ERR_FILE="$LOGS_DIR/analyze_last_error.log"
    docker run --rm \
        --entrypoint python \
        -v "$RECORDINGS_DIR":/recordings \
        -v "$LOGS_DIR":/logs \
        -v "$CHECKPOINTS_DIR":/birdnet_analyzer/checkpoints \
        birdnet-pi -m birdnet_analyzer.analyze \
        "/recordings/$FILE" -o /logs \
        --rtype csv \
        --min_conf $MIN_CONF \
        ${LATITUDE:+--lat $LATITUDE} \
        ${LONGITUDE:+--lon $LONGITUDE} \
        ${LATITUDE:+--week -1} \
        ${SENSITIVITY:+--sensitivity $SENSITIVITY} \
        ${OVERLAP:+--overlap $OVERLAP} \
        2>"$ANALYZE_ERR_FILE"
    ANALYZE_EXIT=$?

    if [ $ANALYZE_EXIT -ne 0 ]; then
        echo "  ⚠ Analysis failed (exit code: $ANALYZE_EXIT)"
        if [ -s "$ANALYZE_ERR_FILE" ]; then
            echo "  ⚠ Analyzer error output:"
            sed 's/^/    /' "$ANALYZE_ERR_FILE" | tail -20
        fi

        # Exit code 2 usually means an unsupported or malformed argument.
        # Retry with minimal, known-safe arguments so detection can continue.
        if [ $ANALYZE_EXIT -eq 2 ]; then
            echo "  ↩ Retrying analysis with compatibility args..."
            docker run --rm \
                --entrypoint python \
                -v "$RECORDINGS_DIR":/recordings \
                -v "$LOGS_DIR":/logs \
                -v "$CHECKPOINTS_DIR":/birdnet_analyzer/checkpoints \
                birdnet-pi -m birdnet_analyzer.analyze \
                "/recordings/$FILE" -o /logs \
                --rtype csv \
                --min_conf $MIN_CONF \
                2>"$ANALYZE_ERR_FILE"
            ANALYZE_EXIT=$?

            if [ $ANALYZE_EXIT -eq 0 ]; then
                echo "  ✅ Compatibility retry succeeded"
            else
                echo "  ⚠ Compatibility retry failed (exit code: $ANALYZE_EXIT)"
                if [ -s "$ANALYZE_ERR_FILE" ]; then
                    echo "  ⚠ Analyzer error output:"
                    sed 's/^/    /' "$ANALYZE_ERR_FILE" | tail -20
                fi
            fi
        fi
    fi

    # DELETE AUDIO IMMEDIATELY - we don't need it anymore
    rm -f "$FULL_PATH" 2>/dev/null

    # Process results
    RESULT_CSV="$LOGS_DIR/${FILE%.wav}.BirdNET.results.csv"
    if [ -f "$RESULT_CSV" ]; then
        echo "  📄 Analysis results found"
        # Read detections and process each one
        while IFS=',' read -r start end sci_name common_name confidence filepath; do
            # Skip header line
            if [ "$start" = "Start (s)" ]; then
                continue
            fi
            
            # Log ALL detections to rolling log
            echo "$(date '+%Y-%m-%d %H:%M:%S'),$start,$end,$sci_name,$common_name,$confidence,$filepath" >> "$ROLLING_LOG"
            
            # Log ALL detections to AWS (in background)
            log_to_aws "$common_name" "$confidence" "$(date -Iseconds)" "false"
            
            echo "  🐦 $common_name (conf: $confidence)"
            
            # ===== APPLY FILTERS =====
            
            # Filter 1: Check if in ignore list
            if should_ignore_species "$common_name"; then
                echo "     ⏭  Ignored (in ignore list)"
                continue
            fi
            
            # Filter 2: Check if interesting (if list configured)
            if ! is_interesting_species "$common_name"; then
                echo "     ⏭  Skipped (not in interesting list)"
                continue
            fi
            
            # Filter 3: Check quiet hours
            if is_quiet_hours; then
                echo "     🌙 Quiet hours (no alert)"
                continue
            fi
            
            # Filter 4: Check cooldown
            if ! check_cooldown "$common_name"; then
                echo "     ⏱  Cooldown active"
                continue
            fi
            
            # All filters passed - send alert!
            echo "     ✅ ALERT! Sending notification..."
            send_alert "$common_name" "$confidence" "$(date -Iseconds)"
            
        done < "$RESULT_CSV"
        
        # DELETE CSV IMMEDIATELY - data already processed
        rm -f "$RESULT_CSV" 2>/dev/null
    else
        echo "  ℹ No detections this cycle"
    fi
    
    # Delete any other analysis files (selection tables, etc)
    rm -f "$LOGS_DIR/${FILE%.wav}."* 2>/dev/null
    
    # Keep rolling log under size limit (keep last N lines)
    if [ -f "$ROLLING_LOG" ]; then
        LINE_COUNT=$(wc -l < "$ROLLING_LOG")
        if [ "$LINE_COUNT" -gt "$LOG_MAX_LINES" ]; then
            tail -n $((LOG_MAX_LINES / 2)) "$ROLLING_LOG" > "$ROLLING_LOG.tmp"
            echo "Timestamp,Start (s),End (s),Scientific name,Common name,Confidence,Filepath" > "$ROLLING_LOG"
            tail -n +2 "$ROLLING_LOG.tmp" >> "$ROLLING_LOG"
            rm -f "$ROLLING_LOG.tmp"
            echo "  📋 Trimmed rolling log"
        fi
    fi

done