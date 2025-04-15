#!/bin/bash

show_usage() {
    echo "Usage: $0 [input_csv]"
    echo "Trims audio files based on start times specified in a CSV file"
    echo ""
    echo "Arguments:"
    echo "  input_csv    Path to CSV file containing filenames and start times"
    echo "               (default: note_metadata.csv in current directory)"
    echo ""
    echo "CSV Format:"
    echo "  filename,start_time"
    echo "  (Lines starting with # are treated as comments)"
    echo ""
    echo "Requirements:"
    echo "  - ffmpeg must be installed and available in PATH"
    echo "  - Input audio files should be in OGG format"
    echo ""
    echo "Example:"
    echo "  $0 note_metadata.csv"
    exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
fi

input_csv="${1:-note_metadata.csv}"

if [ ! -f "$input_csv" ]; then
    echo "Error: Input CSV file '$input_csv' not found" >&2
    show_usage
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed" >&2
    echo "Please install ffmpeg and try again" >&2
    exit 1
fi

processed_count=0
skipped_count=0
error_count=0

echo "Starting audio trimming process using '$input_csv'"
echo "---------------------------------------------"

while IFS=, read -r filename start_time extra_columns || [[ -n "$filename" ]]; do
    if [[ "$filename" == "#"* || "$filename" == "filename"* || -z "$filename" ]]; then # Ignore headers/comments
        continue
    fi
    
    filename=$(echo "$filename" | tr -d '"' | xargs)
    start_time=$(echo "$start_time" | xargs)

    if ! [[ "$start_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "Warning: Invalid start time '$start_time' for file '$filename', skipping" >&2
        ((error_count++))
        continue
    fi
    
    source_file="${filename}.ogg"
    tmp_file="${filename}_tmp.ogg"

    if [ ! -f "$source_file" ]; then
        echo "Warning: Input file '$source_file' not found, skipping" >&2
        ((skipped_count++))
        continue
    fi
    
    if [[ $(echo "$start_time == 0" | bc -l) -eq 1 ]]; then
        echo "Skipping '$source_file' (start_time=0, nothing to trim)"
        ((skipped_count++))
        continue
    fi
    
    echo "Trimming '$source_file' (from $start_time seconds onwards)"

    if ffmpeg -hide_banner -loglevel error -y -i "$source_file" -ss "$start_time" -c:a copy "$tmp_file" 2>/dev/null; then
        if mv "$tmp_file" "$source_file"; then
            ((processed_count++))
        else
            echo "  Error: Failed to replace original file" >&2
            ((error_count++))
        fi
    else
        echo "  Error: ffmpeg failed to process file" >&2
        ((error_count++))
        [ -f "$tmp_file" ] && rm "$tmp_file"
    fi

done < <(grep -v '^#' "$input_csv")

echo "---------------------------------------------"
echo "Processing complete!"
echo "Summary:"
echo "  Successfully processed: $processed_count files"
echo "  Skipped: $skipped_count files"
echo "  Errors encountered: $error_count files"

if [ "$error_count" -gt 0 ]; then
    exit 1
else
    exit 0
fi
