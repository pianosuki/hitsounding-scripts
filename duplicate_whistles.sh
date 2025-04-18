#!/bin/bash

check_prefixes=false
valid_types=("soft" "normal" "drum")

show_usage() {
	echo "Usage: $0 [-p] <sampletype> [sampleset_range]"
    echo "Copies hitwhistle samples across different sample types and samplesets"
    echo ""
    echo "Options:"
    echo "  -p            Check for and copy prefixed samples (e.g., 1011, 3012, etc.)"
    echo ""
    echo "Arguments:"
    echo "  sampletype       Source sample type (soft, normal, drum)"
    echo "  sampleset_range  Optional inclusive range of samplesets (e.g., 1-10), auto-detected if omitted"
    echo ""
    echo "Examples:"
    echo "  $0 soft 1-10          # Copy soft hitwhistles to other types for samplesets 1-10"
    echo "  $0 -p drum 5-15       # Copy drum hitwhistles for samplesets 5-15 and include prefixed copies"
    echo "  $0 -p normal          # Copy normal hitwhistles to auto-detected range and include prefixed copies"
    exit 1
}

while getopts ":p" opt; do
	case ${opt} in
		p)
			check_prefixes=true
			;;
		\?)
			echo "Error: Invalid option -$OPTARG" >&2
			show_usage
			;;
	esac
done
shift $((OPTIND -1))

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Error: Incorrect number of arguments" >&2
	show_usage
fi

sampletype=$1
sampleset_range=${2:-NULL}

function detect_range() {
	local numbers=($(ls *-hitwhistle*.ogg 2>/dev/null | grep -oE '[0-9]+' || true))
	for type in "${valid_types[@]}"; do
		if [[ -f "${type}-hitwhistle.ogg" ]]; then
			numbers+=("1")
			break
		fi
	done
	numbers=($(printf "%s\n" "${numbers[@]}" | sort -n | uniq))
	numbers=($(printf "%s\n" "${numbers[@]}" | awk '$1 <= 999'))

	if [[ ${#numbers[@]} -eq 0 ]]; then
		echo "Error: No matching sample files found to determine range" >&2
		return 1
	fi

	local start=${numbers[0]}
	local end=${numbers[-1]}

	if [ "$start" -gt 999 ] || [ "$end" -gt 999 ]; then
		echo "Error: Sampleset range out of bounds ($start-$end)" >&2
		return 1
	fi

	echo "$start-$end"
}

function parse_range() {
	if [[ ! $1 =~ ^[0-9]+-[0-9]+$ ]]; then
		echo "Error: Invalid samplesets range format. Use format like 11-50" >&2
		return 1
	fi

	local start=$(cut -d'-' -f1 <<< "$1")
	local end=$(cut -d'-' -f2 <<< "$1")

	if [[ "$start" -gt "$end" ]]; then
        echo "Error: Start of range ($start) must be less than or equal to end ($end)" >&2
        return 1
    fi
    
    if [[ "$start" -lt 1 ]] || [[ "$end" -gt 999 ]]; then
        echo "Error: Sampleset range must be between 1 and 999" >&2
        return 1
    fi

	echo "$start $end"
}

function copy_sampleset_variants() {
	local sampleset=$1
	local source_file=$2

	for target_type in "${valid_types[@]}"; do
		if [[ "$target_type" != "$sampletype" ]]; then
			local target_file="${target_type}-hitwhistle"
			[[ "$sampleset" -ne 1 ]] && target_file+="$sampleset"
			target_file+=".ogg"

			if [[ ! -f "$target_file" ]] || ! cmp -s "$source_file" "$target_file"; then
				cp "$source_file" "$target_file"
				echo "-> $target_file"
			fi
		fi
	done
}

function handle_prefixed_copies() {
	local sampleset=$1
	local source_file=$2
	local -n candidates_ref=$3
	local prefixes=(1 2 3 4 5 6 7 8 9 10)
	
	for prefix in "${prefixes[@]}"; do
		if (( sampleset < 100 )); then
			prefix_regex="${prefix}0${sampleset}"
		else
			prefix_regex="${prefix}${sampleset}"
		fi
		
		for file in "${candidates_ref[@]}"; do
			if [[ "$file" =~ $prefix_regex ]]; then
				prefixed_sampleset=$(echo "$file" | grep -oE "${prefix_regex}" | head -n 1)
				if [[ -n "$prefixed_sampleset" ]]; then
					for target_type in "${valid_types[@]}"; do
						prefix_target_file="${target_type}-hitwhistle${prefixed_sampleset}.ogg"
						if [[ ! -f "$prefix_target_file" ]] || ! cmp -s "$source_file" "$prefix_target_file"; then
							cp "$source_file" "$prefix_target_file"
							echo "-> $prefix_target_file [Prefix: $prefix]"
						fi
					done
					break
				fi
			fi
		done
	done
}

if [[ ! " ${valid_types[@]} " =~ " $sampletype " ]]; then
    echo "Error: Invalid sampletype '$sampletype'. Must be one of: ${valid_types[*]}" >&2
    show_usage
fi

if [[ "$sampleset_range" = "NULL" || -z "$sampleset_range" ]]; then
	detect_range_result=$(detect_range) || {
		echo "$detect_range_result" >&2
    	exit 1
	}

	sampleset_range=$detect_range_result
fi

echo "Starting operation with:"
echo "	Sample type: $sampletype"
echo "	Check prefixes: $check_prefixes"
echo "	Sampleset range: $sampleset_range"
echo "---------------------------------------------"

parse_range_result=$(parse_range "$sampleset_range") || {
    echo "$parse_range_result" >&2
    exit 1
}

read start end <<< "$parse_range_result"

if [[ "$check_prefixes" == true ]]; then
	echo "Looking for prefixed samples..."
	mapfile -t candidate_files < <(find . -maxdepth 1 -type f -regextype posix-extended -regex "\./(soft|normal|drum)-hit(clap|finish)[0-9]{4,5}\.(ogg|wav)")

	declare -A unique_prefixes
    for file in "${candidate_files[@]}"; do
        # Extract the numeric suffix (e.g., 101 from normal-hitclap101.ogg)
        if [[ "$file" =~ [0-9]{3,4}\.(ogg|wav)$ ]]; then
            prefix_num=${BASH_REMATCH[0]%%.*}
            unique_prefixes["$prefix_num"]=1
        fi
    done
    
    echo "Found ${#candidate_files[@]} prefixed sample files"
    echo "Found ${#unique_prefixes[@]} unique prefixed samplesets"
	echo "---------------------------------------------"
fi

for ((sampleset=start; sampleset<=end; sampleset++)); do
    source_file="${sampletype}-hitwhistle"
    [[ "$sampleset" -ne 1 ]] && source_file+="$sampleset"
    source_file+=".ogg"

    if [[ -f "$source_file" ]]; then
        echo "Processing sampleset $sampleset..."
        copy_sampleset_variants "$sampleset" "$source_file"
        if [[ "$check_prefixes" == true ]]; then
            handle_prefixed_copies "$sampleset" "$source_file" candidate_files
        fi
		echo "---------------------------------------------"
    fi
done

echo "Operation completed successfully"
