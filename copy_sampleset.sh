#!/bin/bash

show_usage() {
	echo "Usage: $0 <source_set> <target_set_or_range> [directory]"
    echo "Copies all hitsound samples (excluding whistles) from one sampleset to another"
    echo ""
    echo "Arguments:"
    echo "  source_set          Source sampleset number (1, 2, 3, etc.)"
    echo "  target_set_or_range Target sampleset number or inclusive range (e.g., 2 or 10-20)"
    echo "  directory           Optional target directory (defaults to current directory)"
    echo ""
    echo "Examples:"
    echo "  $0 1 2               # Copy sampleset 1 to sampleset 2"
    echo "  $0 3 10-20           # Copy sampleset 3 to samplesets 10 through 20"
    echo "  $0 2 5 /path/to/sounds # Copy sampleset 2 to 5 in specific directory"
    exit 1
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Error: Incorrect number of arguments" >&2
    show_usage
fi

if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "Error: Source sampleset must be a positive integer" >&2
    show_usage
fi
set_a=$1

if ! [[ $2 =~ ^[0-9]+(-[0-9]+)?$ ]]; then
    echo "Error: Target must be a positive integer or range (e.g., 2 or 10-20)" >&2
    show_usage
fi
set_b=$2

dir="${3:-$(pwd)}"
if [[ ! -d "$dir" ]]; then
    echo "Error: Directory '$dir' does not exist" >&2
    exit 1
fi

cd "$dir" || exit 1

echo "Starting operation with:"
echo "	Source sampleset: $set_a"
echo "	Target sampleset(s): $set_b"
echo "	Directory: $dir"
echo "---------------------------------------------"

copy_file() {
    local f=$1
    local target_set=$2
    local filename=$(basename "$f")
    local filepath=$(dirname "$f")
    local ext="${filename##*.}"

    if [ "$set_a" -eq 1 ]; then # Handle sampleset 1 (which doesn't include the number in the filename)
        local new_filename="${filename%.*}$target_set.$ext"
    else # For other samplesets, just replace the number
        local new_filename="${filename//$set_a/$target_set}"
    fi

    local new="$filepath/$new_filename"
    echo "-> $new_filename"
    cp "$f" "$new"
}

copy_sampleset() {
    local target_set=$1
    local pattern

    if [ "$set_a" -eq 1 ]; then
        pattern="(soft|drum|normal)-(hitnormal|hitfinish|hitclap|sliderslide|slidertick)\.(ogg|wav)$"
    else
        pattern="(soft|drum|normal)-(hitnormal|hitfinish|hitclap|sliderslide|slidertick)$set_a\.(ogg|wav)$"
    fi

    find "$dir" -type f -regextype posix-extended -regex ".*/$pattern" | while read -r f; do
        copy_file "$f" "$target_set"
    done
}

if [[ $set_b =~ ^[0-9]+-[0-9]+$ ]]; then # Handle range case (e.g., 10-20)
    start=$(echo "$set_b" | cut -d'-' -f1)
    end=$(echo "$set_b" | cut -d'-' -f2)
    
    if [ "$start" -gt "$end" ]; then
        echo "Error: Invalid range - start must be less than or equal to end" >&2
        exit 1
    fi

    for ((i = start; i <= end; i++)); do
        echo "Processing sampleset $i..."
        copy_sampleset "$i"
		echo "---------------------------------------------"
    done
else # Single target sampleset case
	echo "Processing sampleset $set_b..."
    copy_sampleset "$set_b"
	echo "---------------------------------------------"
fi

echo "Operation completed successfully"
