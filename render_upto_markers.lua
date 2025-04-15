-- CONFIGURATION
local BASE_INDEX = 11 -- Incremental number to start with for the filenames
local RENDER_PATTERN = "soft-hitwhistle%d" -- %d will be replaced with incremental number
local VOLUME_TRACK_NAME = "Volume" -- Make sure it's the parent folder track of all your other tracks
local MIDI_TRACK_NAMES = { -- Tracks to process and clip off at each marker
  "Transcription 1",
  "Transcription 2"
}
local IGNORED_MIDI_NOTES = {} -- Note values to ignore finding note_starts for (12 = C0, etc)
local FADE_OUT_BARS = 0.5 -- Number of bars to fade out after the marker
local FADE_SHAPE = 4 -- 0=linear, 3=fast start, 4=fast end, 5=bezier
local NOTE_START_PREFIX = "NOTE_START_" -- Prefix for hidden note_start markers
local NOTE_METADATA_FILENAME = "note_metadata.csv" 
local DEBUG_LOG_FILENAME = "render_script_debug.log"
local LOG_TO_FILE = true

-- RUNNING VARIABLES
local LAST_NOTE_POSITIONS = {} -- Table to store note start times

function debug(msg)
    reaper.ShowConsoleMsg(msg .. "\n")
    print(msg)
	
	if LOG_TO_FILE then
        local log_path = reaper.GetProjectPath("") .. "/" .. DEBUG_LOG_FILENAME
        local log_file = io.open(log_path, "a")
        if log_file then
            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
            log_file:write(string.format("[%s] %s\n", timestamp, msg))
            log_file:close()
        else
            reaper.ShowConsoleMsg("ERROR: Could not write to debug log\n")
        end
    end
end

function find_track_by_name(name)
    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track, "")
        if track_name == name then
            debug(string.format("Found track '%s' at index %d", name, i))
            return track
        end
    end
    debug(string.format("Track '%s' not found", name))
    return nil
end

function process_marker(marker_time, index)
    debug(string.rep("-", 50))
    debug(string.format("PROCESSING MARKER #%d at %.3f seconds", index, marker_time))
    reaper.Undo_BeginBlock()
    
    -- Process MIDI tracks
	for _, track_name in ipairs(MIDI_TRACK_NAMES) do
        debug(string.format("Processing MIDI track: %s", track_name))
        local track = find_track_by_name(track_name)
        if track then
            local num_items = reaper.CountTrackMediaItems(track)
            debug(string.format("Found %d items in track '%s'", num_items, track_name))
            
            -- Split items at marker
            for i = num_items - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(track, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                
                if pos + len > marker_time then
                    debug("Item extends beyond marker - splitting...")
                    local new_item = reaper.SplitMediaItem(item, marker_time)
                    if new_item then
                        debug("Split successful - deleting right portion")
                        reaper.DeleteTrackMediaItem(track, new_item)
                    end
                end
            end
            
			-- Populate note_starts
            debug("Detecting note starts in trimmed items...")
            local items = get_track_items(track)
            for _, item in ipairs(items) do
                local take = reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local note_starts = get_note_starts(take, marker_time)
                    for _, start_pos in ipairs(note_starts) do
                        local marker_id = string.format("%s%d_%.3f", NOTE_START_PREFIX, index, start_pos)
                        reaper.AddProjectMarker2(0, false, start_pos, 0, marker_id, -1, reaper.ColorToNative(0, 0, 255))
                        LAST_NOTE_POSITIONS[index] = start_pos
                        debug(string.format("Note start at %.3f (before marker %.3f)", start_pos, marker_time))
                    end
                end
            end
        end
    end

	debug(string.format("Processing volume track: %s", VOLUME_TRACK_NAME))
	local vol_track = find_track_by_name(VOLUME_TRACK_NAME)

	-- Ensure volume track exists
	if not vol_track then
		debug("Volume track not found - creating new one...")
		local track_index = reaper.CountTracks()
		local success = reaper.InsertTrackAtIndex(track_index, false)
		if success then
			vol_track = reaper.GetTrack(0, track_index)
			reaper.GetSetMediaTrackInfo_String(vol_track, "P_NAME", VOLUME_TRACK_NAME, true)
			debug("Created new volume track")
		else
			debug("ERROR: Failed to create volume track")
		end
	end

	-- Process volume envelope
	if vol_track then
		debug("Getting volume envelope...")
		local vol_env = reaper.GetTrackEnvelopeByName(vol_track, "Volume")
		
		if not vol_env then
			debug("Volume envelope not found - creating...")
			reaper.SetOnlyTrackSelected(vol_track)
			reaper.Main_OnCommand(40406, 0) -- Show volume envelope
			vol_env = reaper.GetTrackEnvelopeByName(vol_track, "Volume")
			if not vol_env then
				debug("ERROR: Failed to create volume envelope")
			end
		end

		if vol_env then
			debug("Configuring volume envelope...")
			local timeSigNum, timeSigDenom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, marker_time)
			local bar_duration = (timeSigNum * (60 / bpm) * (4 / timeSigDenom))
			local fade_end_time = marker_time + (bar_duration * FADE_OUT_BARS)

			reaper.DeleteEnvelopePointRange(vol_env, -math.huge, math.huge)
		
			-- Insert envelope points (Magic number 716.218 = 0.0dB apparently?)
			debug("Adding envelope points...")
			reaper.InsertEnvelopePoint(vol_env, marker_time, 716.218, FADE_SHAPE, 0, false)
			reaper.InsertEnvelopePoint(vol_env, fade_end_time, 0.0, FADE_SHAPE, 0, false)
			reaper.Envelope_SortPoints(vol_env)

			local point_count = reaper.CountEnvelopePoints(vol_env)
    		debug(string.format("Final point count: %d", point_count))
			for i = 0, point_count-1 do
				local ret, time, value, shape, tension, selected = reaper.GetEnvelopePoint(vol_env, i)
				debug(string.format("Point %d: time=%.3f, value=%.3f, shape=%d", i+1, time, value, shape))
			end
		
			debug(string.format("Setting time selection: 0 to %.3f", fade_end_time))
			reaper.GetSet_LoopTimeRange(true, false, 0, fade_end_time, false)
			
			local filename = string.format(RENDER_PATTERN, BASE_INDEX + (index - 1))
			reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", filename, true)

			debug(string.format("Rendering file: %s", filename))
			reaper.Main_OnCommand(42230, 0) -- Render using last saved settings
			debug("Render complete")
		end
	end

    debug("Restoring project state...")
    reaper.Undo_EndBlock("Render Marker " .. index, -1)
    reaper.Undo_DoUndo2(0)

    debug(string.format("Finished processing marker #%d", index))
	save_note_metadata(index, marker_time)
end

function get_track_items(track)
    local items = {}
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        items[i+1] = reaper.GetTrackMediaItem(track, i)
    end
    return items
end

function get_note_starts(take, marker_time)
    local note_starts = {}
    local _, notecnt = reaper.MIDI_CountEvts(take)
    
    -- Convert marker time to PPQ
    local marker_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, marker_time)
    local one_bar_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, 1)  -- 1 bar lookback
    
    -- Create lookup table for ignored notes (faster checking)
    local ignore_notes = {}
    for _, note in ipairs(IGNORED_MIDI_NOTES) do
        ignore_notes[note] = true
    end
    
    for i = 0, notecnt - 1 do
        local _, _, _, startppq, endppq, chan, pitch = reaper.MIDI_GetNote(take, i)
        
        -- Skip ignored notes
        if not ignore_notes[pitch] then
            -- Find notes ending near our marker (within 1 bar before)
            if endppq <= marker_ppq and endppq > (marker_ppq - one_bar_ppq) then
                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, startppq)
                table.insert(note_starts, start_time)
            end
        end
    end
    
    -- Return only the last note before marker (from remaining notes)
    table.sort(note_starts)
    if #note_starts > 0 then
        return {note_starts[#note_starts]}
    end
    return {}
end

function save_note_metadata(index, end_time)
    local start_pos = LAST_NOTE_POSITIONS[index] or 0
    local filename = string.format(RENDER_PATTERN, BASE_INDEX + (index - 1))
	debug(string.format("Saving note metadata: %s,%.3f,%.3f\n", filename, start_pos, end_time))
    
    -- Save to file
	local meta_file_path = reaper.GetProjectPath("") .. "/" .. NOTE_METADATA_FILENAME
    local meta_file = io.open(meta_file_path, "a")
    if meta_file then
        meta_file:write(string.format("%s,%.3f,%.3f\n", filename, start_pos, end_time))
        meta_file:close()
    end
end

function init_files()
    local meta_file_path = reaper.GetProjectPath("") .. "/" .. NOTE_METADATA_FILENAME
	local log_file_path = reaper.GetProjectPath("") .. "/" .. DEBUG_LOG_FILENAME
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")

    -- Append headers with timestamps
    local meta_file = io.open(meta_file_path, "w")
    if meta_file then
		meta_file:write(string.format("# Metadata generated %s\n", timestamp))
        meta_file:write("# Project: " .. reaper.GetProjectName(0, "") .. "\n")
        meta_file:write("filename,start_time,end_time\n")
        meta_file:close()
    end

	if LOG_TO_FILE then
        local log_file = io.open(log_file_path, "w")
        if log_file then
            log_file:write(string.format("Render Script Log - %s\n\n", timestamp))
            log_file:close()
        end
    end
end

function main()
    debug("\n\n=== STARTING RENDER SCRIPT ===")
    debug("CONFIGURATION:")
    debug(string.format("  BASE_INDEX: %d", BASE_INDEX))
    debug(string.format("  RENDER_PATTERN: '%s'", RENDER_PATTERN))
    debug(string.format("  VOLUME_TRACK_NAME: '%s'", VOLUME_TRACK_NAME))
	if #IGNORED_MIDI_NOTES > 0 then
		debug(string.format("  Ignoring MIDI notes: %s", table.concat(IGNORED_MIDI_NOTES, ", ")))
	else
		debug("  No MIDI notes ignored")
	end
    debug("  MIDI_TRACK_NAMES:")
    for i, name in ipairs(MIDI_TRACK_NAMES) do
        debug(string.format("    [%d] '%s'", i, name))
    end
    debug(string.format("  FADE_OUT_BARS: %.1f", FADE_OUT_BARS))
    debug(string.format("  FADE_SHAPE: %d", FADE_SHAPE))
    debug(string.format("  NOTE_START_PREFIX: '%s'", NOTE_START_PREFIX))
    debug(string.format("  NOTE_METADATA_FILENAME: '%s'", NOTE_METADATA_FILENAME))
    debug(string.format("  DEBUG_LOG_FILENAME: '%s'", DEBUG_LOG_FILENAME))
    debug(string.format("  LOG_TO_FILE: %s" .. "\n", LOG_TO_FILE and "true" or "false"))

	init_files()
    
    debug("Gathering project markers...")
    local markers = {}
    local _, num_markers = reaper.CountProjectMarkers(0)
    debug(string.format("Found %d markers in project", num_markers))
    
    for i = 0, num_markers - 1 do
        local retval, _, pos = reaper.EnumProjectMarkers3(0, i)
        if retval then
            table.insert(markers, pos)
            debug(string.format("Marker %d at %.3f seconds", i+1, pos))
        end
    end
    table.sort(markers)

    debug(string.format("\nProcessing %d markers...", #markers))
    for i, marker_time in ipairs(markers) do
        process_marker(marker_time, i)
    end
    
    debug("\n=== RENDER SCRIPT COMPLETE ===")
end

reaper.ShowConsoleMsg("")
reaper.defer(main)