#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# AI-RON Minimal Status Line
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# Configuration
PAI_DIR="${PAI_DIR:-$HOME/.claude}"
CONTEXT_BASELINE=22600

# Parse input
input=$(cat)

# Extract data from JSON
eval "$(echo "$input" | jq -r '
  "duration_ms=" + (.cost.total_duration_ms // 0 | tostring) + "\n" +
  "cache_read=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring) + "\n" +
  "input_tokens=" + ((.context_window.current_usage.input_tokens // 0) | tostring) + "\n" +
  "cache_creation=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring) + "\n" +
  "output_tokens=" + ((.context_window.current_usage.output_tokens // 0) | tostring) + "\n" +
  "context_max=" + (.context_window.context_window_size // 200000 | tostring) + "\n" +
  "model_name=" + (.model.display_name // "" | @sh) + "\n" +
  "session_id=" + (.session_id // "" | @sh)
')"

# Ensure all numeric variables have valid defaults (handle empty input)
duration_ms=${duration_ms:-0}
cache_read=${cache_read:-0}
input_tokens=${input_tokens:-0}
cache_creation=${cache_creation:-0}
output_tokens=${output_tokens:-0}
context_max=${context_max:-0}

# Colors
RESET='\033[0m'
SLATE_500='\033[38;2;100;116;139m'
SLATE_600='\033[38;2;71;85;105m'
PAI_A='\033[38;2;59;130;246m'
CTX_BUCKET_EMPTY='\033[38;2;75;82;95m'

# Get gradient color for context bar bucket
get_bucket_color() {
    local pos=$1 max=$2
    local pct=$((pos * 100 / max))
    local r g b

    if [ "$pct" -le 33 ]; then
        r=$((74 + (250 - 74) * pct / 33))
        g=$((222 + (204 - 222) * pct / 33))
        b=$((128 + (21 - 128) * pct / 33))
    elif [ "$pct" -le 66 ]; then
        local t=$((pct - 33))
        r=$((250 + (251 - 250) * t / 33))
        g=$((204 + (146 - 204) * t / 33))
        b=$((21 + (60 - 21) * t / 33))
    else
        local t=$((pct - 66))
        r=$((251 + (239 - 251) * t / 34))
        g=$((146 + (68 - 146) * t / 34))
        b=$((60 + (68 - 60) * t / 34))
    fi
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Render context bar
render_context_bar() {
    local width=$1 pct=$2
    local output="" last_color=""

    [ "$pct" -gt 100 ] && pct=100
    local filled=$((pct * width / 100))
    [ "$filled" -lt 0 ] && filled=0

    for i in $(seq 1 $width 2>/dev/null); do
        if [ "$i" -le "$filled" ]; then
            local color=$(get_bucket_color $i $width)
            last_color="$color"
            output="${output}${color}⛁${RESET}"
            [ "$width" -gt 8 ] && output="${output} "
        else
            output="${output}${CTX_BUCKET_EMPTY}⛁${RESET}"
            [ "$width" -gt 8 ] && output="${output} "
        fi
    done

    output="${output% }"
    echo "$output"
    LAST_BUCKET_COLOR="${last_color:-\033[38;2;74;222;128m}"
}

# Calculate context usage
content_tokens=$((cache_read + input_tokens + cache_creation + output_tokens))
context_used=$((content_tokens + CONTEXT_BASELINE))

if [ "$context_max" -gt 0 ] && [ "$context_used" -gt 0 ]; then
    context_pct=$((context_used * 100 / context_max))
    context_k=$((context_used / 1000))
    max_k=$((context_max / 1000))
else
    context_pct=0; context_k=0; max_k=$((context_max / 1000))
fi

# Format duration
duration_sec=$((duration_ms / 1000))
if   [ "$duration_sec" -ge 3600 ]; then time_display="$((duration_sec / 3600))h$((duration_sec % 3600 / 60))m"
elif [ "$duration_sec" -ge 60 ];   then time_display="$((duration_sec / 60))m$((duration_sec % 60))s"
else time_display="${duration_sec}s"
fi

# Render context bar
bar=$(render_context_bar 16 $context_pct)

# Git status information
if git rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")

    # Get PR number and URL using gh CLI
    pr_data=$(gh pr view --json number,url -q '"\(.number)|\(.url)"' 2>/dev/null || echo "")
    pr_number=$(echo "$pr_data" | cut -d'|' -f1)
    pr_url=$(echo "$pr_data" | cut -d'|' -f2)

    # Get git status
    if git diff-index --quiet HEAD -- 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
        status="${SLATE_500}clean${RESET}"
    else
        status="${PAI_A}changed${RESET}"
    fi

    # Store git info for output
    has_git=true
else
    has_git=false
fi

# Session topic — keyed by session ID, discovered via PID bridge
TOPICS_DIR="${HOME}/.claude/session-topics"
mkdir -p "$TOPICS_DIR" 2>/dev/null

session_topic="AI-RON"
if [ -n "$session_id" ]; then
    # Write PID → session ID mapping so the agent can discover its session
    echo "$session_id" > "$TOPICS_DIR/pid-$PPID.map"

    # Read topic for this session (if agent has written one)
    TOPIC_FILE="$TOPICS_DIR/${session_id}.txt"
    if [ -f "$TOPIC_FILE" ]; then
        session_topic=$(head -1 "$TOPIC_FILE" | tr -d '\n' | tr '[:lower:]' '[:upper:]')
    fi
fi
# Truncate to ~60% of header line width (computed after line_width is known)
# Deferred — see topic truncation below after line_width is computed

# Pad variable parts so context line is always the same width
pct_display=$(printf "%3d" "$context_pct")            # "  5" to "100" (3 chars, % added in output)
used_display="${context_k}k"                          # "0k" to "1000k" (variable width)
max_display=$(printf "%4dk" "$max_k")               # " 200k" to "1000k" (5 chars)

# Build model suffix
model_plain=""
model_display=""
if [ -n "$model_name" ]; then
    model_plain=" | ${model_name}"
    model_display=" ${SLATE_500}|${RESET} ${SLATE_500}${model_name}${RESET}"
fi

# Compute total context line width (drives all other widths)
# "CONTEXT: " (9) + bar (31) + " " (1) + pct (3) + "%" (1) + gap + "(" + used_max + ")" (1) + model
# used_max has max width: "1000k/1000k" = 11. Gap absorbs shorter used values.
used_max_part="${used_display}/${max_display})"
used_max_width=$((5 + 1 + 5 + 1))  # max: "1000k" "/" "1000k" ")" = 12
gap_size=$((used_max_width - ${#used_max_part} + 1))  # +1 for the base space before (
gap=$(printf '%*s' "$gap_size" "")
line_width=$((9 + 31 + 1 + 3 + 1 + gap_size + 1 + ${#used_max_part} + ${#model_plain}))

# Truncate topic to ~60% of line width
max_topic_len=$((line_width * 60 / 100))
[ "${#session_topic}" -gt "$max_topic_len" ] && session_topic="${session_topic:0:$max_topic_len}"

# Set terminal title to session topic
printf '\033]0;%s\007' "$session_topic"

# Output: Header line (topic right-aligned to line_width)
topic_len=${#session_topic}
hr_len=$((line_width - topic_len - 1))  # -1 for the space before topic
hr=$(printf '─%.0s' $(seq 1 $hr_len))
printf "${SLATE_600}${hr}${RESET} ${PAI_A}${session_topic}${RESET}\n"

# Output: Context line (padded to fixed width)
printf "${PAI_A}CONTEXT:${RESET} ${bar} ${LAST_BUCKET_COLOR}${pct_display}%%${RESET}${gap}${SLATE_500}(${used_display}/${max_display})${RESET}${model_display}\n"

# Output git status line
if [ "$has_git" = true ]; then
    display_path="${PWD/#$HOME/~}"
    status_text="changed"
    # Fixed chars: "PWD: " (5) + " | " (3) + "GIT: " (5) + " (" (2) + ")" (1) = 16
    fixed_chars=16
    max_path_len=$((line_width - fixed_chars - ${#branch} - ${#status_text}))
    [ "$max_path_len" -lt 10 ] && max_path_len=10

    if [ "${#display_path}" -gt "$max_path_len" ]; then
        tail_len=$((max_path_len - 1))
        display_path="…${display_path: -$tail_len}"
    fi

    bottom_hr=$(printf '─%.0s' $(seq 1 $line_width))
    printf "${SLATE_600}${bottom_hr}${RESET}\n"
    printf "${PAI_A}PWD:${RESET} ${SLATE_500}${display_path}${RESET} ${SLATE_500}|${RESET} ${PAI_A}GIT:${RESET} ${SLATE_500}${branch}${RESET} (${status})\n"
fi
