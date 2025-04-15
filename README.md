# Osu! Hitsounding Scripts

A collection of scripts to streamline hitsound creation for Osu! beatmaps.

## Scripts Overview

### 1. `copy_sampleset.sh`
**Purpose**: Copies all hitsound samples (excluding whistles) from one sampleset to another
 
**Usage**:
```bash
./copy_sampleset.sh <source_set> <target_set_or_range> [directory]
```
**Arguments**:
- `source_set` - Source sampleset number (1, 3, 6, etc.)
- `target_set_or_range` - Target sampleset number or inclusive range (e.g., 2 or 10-20)
- `directory` - Optional target directory (defaults to current directory)

**Examples**:
```bash
# Copy sampleset 1 to sampleset 2
./copy_sampleset.sh 1 2

# Copy sampleset 3 to samplesets 10 through 20
./copy_sampleset.sh 3 10-20

# Copy sampleset 2 to 5 in specific directory"
./copy_sampleset.sh 2 5 /path/to/sounds
```
### 2. `duplicate_whistles.sh`
**Purpose**: Copies hitwhistle samples across different sample types and samplesets

**Usage**:
```bash
./duplicate_whistles.sh [-p] <sampletype> [sampleset_range]
```
**Arguments**:
- `sampletype` - Source sample type (soft, normal, drum)
- `sampleset_range` - Optional inclusive range of samplesets (e.g., 1-10), auto-detected if omitted

**Options**:
- `-p` - Check for and copy prefixed samples (e.g., 1011, 3012, etc.)

**Examples**:
```bash
# Copy soft hitwhistles to other types for samplesets 1-10
./duplicate_whistles.sh soft 1-10

# Copy drum hitwhistles for samplesets 5-15 and include prefixed copies
./duplicate_whistles.sh -p drum 5-15

# Copy normal hitwhistles to auto-detected range and include prefixed copies
./duplicate_whistles.sh -p normal
```
### 3. `fade_samples.sh`
**Purpose**: Applies various fade effects to audio files

**Usage**:
```bash
./fade_samples.sh <fade_type> [fade_ms] [-s strength_db] [-d directory] [-p file_pattern]
```
**Arguments**:
- `fade_type` - Type of fade: soft-in, soft-out, full-in, full-out
- `fade_ms` - Fade duration in milliseconds (optional, default: full file length)

**Options**:
- `-s strength_db` - Strength in dB (only for soft fades, default: 1.0)
- `-d directory` - Directory to process (default: current directory)
- `-p file_pattern` - Regex pattern for files to process (default: hitsound files)

**Examples**:
```bash
# Apply soft fade-in of max duration starting from -4dB to 0dB in a specific directory to all osu! hitsound files
./fade_samples.sh soft-in -s 4.0 -d ~/sounds

# Apply a full fade-out of duration 100ms to all files ending in .ogg
./fade_samples.sh full-out 100 -p '.*\.ogg'

# Apply a soft fade-out of duration 50ms starting from 0db to -2dB to all files matching the pattern
./fade_samples.sh soft-out 50 -s 2.0 -p '^note-[0-9]+\.wav$'
```
### 4. `render_upto_markers.lua` (Reaper ReaScript)
**Purpose**: Batch renders project up to each marker point (meant to be paired with `trim_rendered_notes.sh`)

**Requirements**:
- [REAPER](https://www.reaper.fm/)
- Markers placed at each desired notes' endpoints

**Output**:
- Rendered audio files containing everything from the beginning of the project up to and including each desired note
- meta_data.csv with note timing information

### 5. `trim_rendered_notes.sh`
**Purpose**: Trims audio files based on start times specified in a CSV file

**Usage**:
```bash
./trim_rendered_notes.sh [input_csv]
```
**Arguments**:
- `input_csv` - Path to CSV file containing filenames and start times (default: note_metadata.csv in current directory)

## Installation
1. Clone this repository:
```bash
git clone https://github.com/pianosuki/hitsounding-scripts.git
```
2. Make the scripts executable:
```bash
chmod +x *.sh
```
3. For ReaScript:
- Copy `render_upto_markers.lua` to REAPER's Scripts directory
