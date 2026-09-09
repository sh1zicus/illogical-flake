#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

# Convert slurp format "X,Y WxH" to gpu-screen-recorder format "WxH+X+Y"
slurp2gsr() {
    if [[ "$1" =~ ^([0-9]+),([0-9]+)\ ([0-9]+)x([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[3]}x${BASH_REMATCH[4]}+${BASH_REMATCH[1]}+${BASH_REMATCH[2]}"
    else
        echo "$1"
    fi
}

mkdir -p "$RECORDING_DIR"

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

if pgrep gpu-screen-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill gpu-screen-recorder &
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mkv' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            gpu-screen-recorder -w monitor -f 60 -c h264 -cr icq -q 20 -a default_output -o "$RECORDING_DIR/recording_$(getdate).mkv" &
        else
            gpu-screen-recorder -w monitor -f 60 -c h264 -cr icq -q 20 -o "$RECORDING_DIR/recording_$(getdate).mkv" &
        fi
        disown
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        # Convert slurp format "X,Y WxH" to gpu-screen-recorder format "WxH+X+Y"
        gsr_region=$(slurp2gsr "$region")

        notify-send "Starting recording" 'recording_'"$(getdate)"'.mkv' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            gpu-screen-recorder -w monitor -f 60 -c h264 -cr icq -q 20 -r "$gsr_region" -a default_output -o "$RECORDING_DIR/recording_$(getdate).mkv" &
        else
            gpu-screen-recorder -w monitor -f 60 -c h264 -cr icq -q 20 -r "$gsr_region" -o "$RECORDING_DIR/recording_$(getdate).mkv" &
        fi
        disown
    fi
fi