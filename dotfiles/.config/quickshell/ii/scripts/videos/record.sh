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
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# Prefer hardware encoding on the GPU (VAAPI) to keep CPU load low.
# Fall back to software x264 if no usable render node is present.
if [[ -e /dev/dri/renderD128 ]]; then
    ENC_ARGS=(-c h264_vaapi -d /dev/dri/renderD128 -t)
else
    ENC_ARGS=(--pixel-format yuv420p -t)
fi

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

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill wf-recorder &
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder "${ENC_ARGS[@]}" -o "$(getactivemonitor)" -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)"
        else
            wf-recorder "${ENC_ARGS[@]}" -o "$(getactivemonitor)" -f './recording_'"$(getdate)"'.mp4'
        fi
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

        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder "${ENC_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)"
        else
            wf-recorder "${ENC_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' --geometry "$region"
        fi
    fi
fi