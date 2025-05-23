#!/bin/bash

show_usage() {
    echo "Usage: $0 <fade_type> [fade_ms] [-s strength_db] [-d directory] [-p file_pattern]"
    echo "Applies various fade effects to audio files"
    echo ""
    echo "Arguments:"
    echo "  fade_type     Type of fade: soft-in, soft-out, full-in, full-out"
    echo "  fade_ms       Fade duration in milliseconds (optional, default: full file length)"
    echo ""
    echo "Options:"
    echo "  -s strength_db   Strength in dB (only for soft fades, default: 1.0)"
    echo "  -d directory     Directory to process (default: current directory)"
    echo "  -p file_pattern  Regex pattern for files to process (default: hitsound files)"
    echo ""
    echo "Examples:"
    echo "  $0 soft-in -s 4.0 -d ~/sounds"
    echo "  $0 full-out 100 -p '.*\.ogg'"
    echo "  $0 soft-out 50 -s 2.0 -p '^note-[0-9]+\.wav$'"
    exit 1
}

fade_ms=""
strength_db=1.0
directory=$(pwd)
file_pattern='^(soft|drum|normal)-hit(whistle|finish|clap)[0-9]*\.(ogg|wav)$'

if [[ $# -lt 1 ]]; then
    echo "Error: Missing required arguments" >&2
    show_usage
fi

positional_args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -d)
            directory=$2
            shift 2
            ;;
        -p)
            file_pattern=$2
            shift 2
            ;;
        -s)
            strength_db=$2
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            show_usage
            ;;
        *)
            positional_args+=("$1")
            shift
            ;;
    esac
done

fade_type=${positional_args[0]}
fade_ms=${positional_args[1]:-""}

valid_fade_types=("soft-in" "soft-out" "full-in" "full-out")
if [[ ! " ${valid_fade_types[@]} " =~ " $fade_type " ]]; then
    echo "Error: Invalid fade type. Must be one of: ${valid_fade_types[*]}" >&2
    show_usage
fi

if [[ "$fade_type" == "soft-in" || "$fade_type" == "soft-out" ]]; then
    if ! [[ "$strength_db" =~ ^[0-9.]+$ ]]; then
        echo "Error: Fade strength must be a positive number" >&2
        show_usage
    fi
fi

if [[ ! -d "$directory" ]]; then
    echo "Error: Directory '$directory' does not exist" >&2
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed" >&2
    exit 1
fi

fade_sec=$(awk -v ms="$fade_ms" 'BEGIN { print ms/1000 }')

if [[ "$fade_type" == "soft-in" || "$fade_type" == "soft-out" ]]; then
    start_db=$(echo "$strength_db" | awk '{ if ($1 > 0) print -$1; else print $1 }')
    start_amp=$(awk -v db="$start_db" 'BEGIN { print 10^(db/20) }')
fi

processed_count=0
error_count=0

echo "Starting fade processing:"
echo "  Fade type: $fade_type"
[[ -n "$fade_ms" ]] && \
    echo "   Fade duration: ${fade_ms}ms" || \
    echo "  Fade duration: full file length"
[[ "$fade_type" == "soft-in" || "$fade_type" == "soft-out" ]] && \
    echo "  Fade strength: ${strength_db}dB"
echo "  Directory: $directory"
echo "  File pattern: $file_pattern"
echo "---------------------------------------------"

while IFS= read -r -d $'\0' file; do
    filename=$(basename "$file")
    if [[ "$filename" =~ $file_pattern ]]; then
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
        
        if [[ -z "$fade_ms" ]]; then
            fade_sec=$duration
        else
            fade_sec=$(awk -v ms="$fade_ms" 'BEGIN { print ms/1000 }')
            
            if (( $(echo "$fade_sec > $duration" | bc -l) )); then
                echo "Warning: Fade duration (${fade_sec}s) > file duration (${duration}s), using full duration"
                fade_sec=$duration
            fi
        fi

        tmpfile="${file%.*}_tmp.${file##*.}"
        
        echo "Processing $filename (duration: ${duration}s, fade: ${fade_sec}s)..."
        
        case "$fade_type" in
            "soft-in")
                ffmpeg_cmd=(
                    -y -hide_banner -loglevel error
                    -i "$file"
                    -af "volume='if(lt(t,$fade_sec), $start_amp + (1-$start_amp)*(t/$fade_sec), 1)':eval=frame"
                    "$tmpfile"
                )
                ;;
            "soft-out")
                fade_start=$(LC_ALL=C printf "%.6f" $(echo "$duration - $fade_sec" | bc))
                ffmpeg_cmd=(
                    -y -hide_banner -loglevel error
                    -i "$file"
                    -af "volume='if(gt(t,$fade_start), 1 - (1-$start_amp)*((t-$fade_start)/$fade_sec), 1)':eval=frame"
                    "$tmpfile"
                )
                ;;
            "full-in")
                ffmpeg_cmd=(
                    -y -hide_banner -loglevel error
                    -i "$file"
                    -af "afade=t=in:ss=0:d=$fade_sec"
                    "$tmpfile"
                )
                ;;
            "full-out")
                fade_start=$(LC_ALL=C printf "%.6f" $(echo "$duration - $fade_sec" | bc))
                ffmpeg_cmd=(
                    -y -hide_banner -loglevel error
                    -i "$file"
                    -af "afade=t=out:st=${fade_start}:d=$fade_sec"
                    "$tmpfile"
                )
                ;;
        esac
        
        if ffmpeg "${ffmpeg_cmd[@]}" 2>/dev/null; then
            if mv "$tmpfile" "$file"; then
                ((processed_count++))
            else
                echo "  Error: Failed to replace original file" >&2
                ((error_count++))
            fi
        else
            echo "  Error: ffmpeg processing failed" >&2
            ((error_count++))
            [ -f "$tmpfile" ] && rm "$tmpfile"
        fi
    fi
done < <(find "$directory" -type f -print0)

echo "---------------------------------------------"
echo "Processing complete!"
echo "Summary:"
echo "  Successfully processed: $processed_count files"
echo "  Errors encountered: $error_count files"

if [[ "$processed_count" -eq 0 ]]; then
    exit 1
else
    exit 0
fi
