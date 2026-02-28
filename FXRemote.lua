-- FX Remote Control ReaScript for Live Mixer
-- Place this script in your Reaper Scripts folder and run it
-- It polls a command file for FX parameter changes

local POLL_INTERVAL = 0.05 -- 50ms

-- Use /tmp on Mac/Linux, or project folder
local CMD_FILE = "/tmp/fx_commands.txt"
local RESPONSE_FILE = "/tmp/fx_response.txt"

-- Show we're running
reaper.ShowConsoleMsg("FXRemote: Started. Watching " .. CMD_FILE .. "\n")

-- Helper function to get track by index (0 = master, 1+ = regular tracks)
function GetTrackByIndex(trackIdx)
  -- Ensure trackIdx is a number
  trackIdx = tonumber(trackIdx) or 0
  
  if trackIdx == 0 or trackIdx < 1 then
    -- Return master track for index 0 (or any invalid index)
    local master = reaper.GetMasterTrack(0)
    if not master then
      reaper.ShowConsoleMsg("  WARNING: GetMasterTrack returned nil!\n")
    end
    return master
  else
    return reaper.GetTrack(0, trackIdx - 1) -- Convert to 0-indexed
  end
end

-- Create/clear the command file
local f = io.open(CMD_FILE, "w")
if f then 
  f:close() 
  reaper.ShowConsoleMsg("FXRemote: Command file created\n")
else
  reaper.ShowConsoleMsg("FXRemote: ERROR - Could not create command file!\n")
end

function ProcessCommands()
  local f = io.open(CMD_FILE, "r")
  if not f then return end
  
  local content = f:read("*all")
  f:close()
  
  if content and content ~= "" then
    -- Clear file immediately
    local cf = io.open(CMD_FILE, "w")
    if cf then cf:close() end
    
    -- Process each line
    for line in content:gmatch("[^\n]+") do
      reaper.ShowConsoleMsg("FXRemote: Processing: " .. line .. "\n")
      
      local trackIdxStr, fxIdxStr, paramIdxStr, valueStr = line:match("(%d+),(%d+),(%d+),([%d%.%-]+)")
      if trackIdxStr then
        local trackIdx = tonumber(trackIdxStr)
        local fxIdx = tonumber(fxIdxStr)
        local paramIdx = tonumber(paramIdxStr)
        local value = tonumber(valueStr)
        
        reaper.ShowConsoleMsg(string.format("  Parsed: track=%d, fx=%d, param=%d, val=%.4f\n", 
          trackIdx, fxIdx, paramIdx, value))
        
        local track = GetTrackByIndex(trackIdx)
        if track then
          local retval = reaper.TrackFX_SetParamNormalized(track, fxIdx, paramIdx, value)
          reaper.ShowConsoleMsg(string.format("  Set FX param result: %s\n", tostring(retval)))
        else
          reaper.ShowConsoleMsg(string.format("  ERROR: Track %d not found (parsed from '%s')\n", 
            trackIdx, trackIdxStr))
        end
      end
      
      -- Handle bypass toggle: B,trackIdx,fxIdx
      local bTrack, bFx = line:match("^B,(%d+),(%d+)")
      if bTrack then
        bTrack = tonumber(bTrack)
        bFx = tonumber(bFx)
        local track = GetTrackByIndex(bTrack)
        if track then
          local enabled = reaper.TrackFX_GetEnabled(track, bFx)
          reaper.TrackFX_SetEnabled(track, bFx, not enabled)
          local newEnabled = not enabled
          reaper.ShowConsoleMsg(string.format("  FX Bypass: Track %d, FX %d -> %s\n", 
            bTrack, bFx, tostring(newEnabled)))
          
          -- Write response with new bypass state
          local rf = io.open(RESPONSE_FILE, "w")
          if rf then
            rf:write(string.format("E,%d,%d,%d\n", bTrack, bFx, newEnabled and 1 or 0))
            rf:close()
          end
        end
      end
      
      -- Handle set bypass: S,trackIdx,fxIdx,enabled (1=on, 0=off)
      local sTrack, sFx, sEnabled = line:match("^S,(%d+),(%d+),(%d+)")
      if sTrack then
        sTrack = tonumber(sTrack)
        sFx = tonumber(sFx)
        sEnabled = tonumber(sEnabled) == 1
        local track = GetTrackByIndex(sTrack)
        if track then
          reaper.TrackFX_SetEnabled(track, sFx, sEnabled)
          reaper.ShowConsoleMsg(string.format("  FX Set: Track %d, FX %d -> %s\n", 
            sTrack, sFx, sEnabled and "ON" or "OFF"))
        end
      end
      
      -- Handle send mode: M,trackIdx,sendIdx,mode (0=post-fader, 3=pre-fader)
      local mTrack, mSend, mMode = line:match("^M,(%d+),(%d+),(%d+)")
      if mTrack then
        mTrack = tonumber(mTrack)
        mSend = tonumber(mSend)
        mMode = tonumber(mMode)
        local track = GetTrackByIndex(mTrack)
        if track then
          reaper.SetTrackSendInfo_Value(track, 0, mSend, "I_SENDMODE", mMode)
          reaper.ShowConsoleMsg(string.format("  Send Mode: Track %d, Send %d -> %s\n", 
            mTrack, mSend, mMode == 3 and "PRE" or "POST"))
        end
      end
      
      -- Handle output EQ read: O,trackIdx (only FX 0 = ReaEQ)
      local oTrack = line:match("^O,(%d+)")
      if oTrack then
        oTrack = tonumber(oTrack)
        local track = GetTrackByIndex(oTrack)
        if track then
          local response = {}
          local fxIdx = 0 -- ReaEQ is at slot 0 on output tracks
          
          local fxEnabled = reaper.TrackFX_GetEnabled(track, fxIdx)
          table.insert(response, string.format("E,%d,%d,%d", oTrack, fxIdx, fxEnabled and 1 or 0))
          
          -- Read EQ params: HPF freq (12), Low/LoMid/HiMid/High gains (1,4,7,10)
          local params = {1, 4, 7, 10, 12}
          for _, paramIdx in ipairs(params) do
            local val = reaper.TrackFX_GetParamNormalized(track, fxIdx, paramIdx)
            table.insert(response, string.format("P,%d,%d,%d,%.6f", oTrack, fxIdx, paramIdx, val))
          end
          
          local rf = io.open(RESPONSE_FILE, "w")
          if rf then
            rf:write(table.concat(response, "\n") .. "\n")
            rf:close()
            reaper.ShowConsoleMsg("  Wrote output EQ response for track " .. oTrack .. "\n")
          end
        end
      end
      
      -- Handle send read request: SENDS (read sends for ALL input tracks)
      if line == "SENDS" then
        local response = {}
        local numTracks = reaper.CountTracks(0)
        
        for trackIdx = 1, numTracks do
          local track = reaper.GetTrack(0, trackIdx - 1)
          if track then
            local _, trackName = reaper.GetTrackName(track)
            -- Only process IN/ tracks (input tracks with sends)
            if trackName:match("^IN/") then
              local numSends = reaper.GetTrackNumSends(track, 0) -- 0 = sends
              for sendIdx = 0, numSends - 1 do
                local sendVol = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "D_VOL")
                table.insert(response, string.format("S,%d,%d,%.6f", trackIdx, sendIdx, sendVol))
              end
            end
          end
        end
        
        local rf = io.open(RESPONSE_FILE, "w")
        if rf then
          rf:write(table.concat(response, "\n") .. "\n")
          rf:close()
          reaper.ShowConsoleMsg("  Wrote SENDS response for " .. #response .. " send entries\n")
        end
      end
      
      -- Handle read request: R,trackIdx (read all FX params)
      local rTrack = line:match("^R,(%d+)")
      if rTrack then
        rTrack = tonumber(rTrack)
        local track = GetTrackByIndex(rTrack)
        if track then
          local response = {}
          -- Read FX 0, 1, 2 (Gate, Comp, EQ)
          for fxIdx = 0, 2 do
            local fxEnabled = reaper.TrackFX_GetEnabled(track, fxIdx)
            table.insert(response, string.format("E,%d,%d,%d", rTrack, fxIdx, fxEnabled and 1 or 0))
            
            -- Read key params for each FX
            local params = {}
            if fxIdx == 0 then params = {0, 1, 2, 4} -- Gate: Thresh, Attack, Release, Hold
            elseif fxIdx == 1 then params = {0, 1, 2, 3} -- Comp: Thresh, Ratio, Attack, Release
            elseif fxIdx == 2 then params = {1, 4, 7, 10, 12} -- EQ: Low/LoMid/HiMid/High gains + HPF freq
            end
            
            for _, paramIdx in ipairs(params) do
              local val = reaper.TrackFX_GetParamNormalized(track, fxIdx, paramIdx)
              table.insert(response, string.format("P,%d,%d,%d,%.6f", rTrack, fxIdx, paramIdx, val))
            end
          end
          
          -- Write response to file
          local rf = io.open(RESPONSE_FILE, "w")
          if rf then
            rf:write(table.concat(response, "\n") .. "\n")
            rf:close()
            reaper.ShowConsoleMsg("  Wrote FX response for track " .. rTrack .. "\n")
          end
        end
      end
    end
  end
end

-- Meter update interval counter
local meterCounter = 0
local METER_UPDATE_INTERVAL = 2 -- Every 2nd cycle (100ms at 50ms poll)

-- Poll FX meters (GR from compressor, gate state from gate)
function PollFxMeters()
  meterCounter = meterCounter + 1
  if meterCounter < METER_UPDATE_INTERVAL then return end
  meterCounter = 0
  
  local response = {}
  local numTracks = reaper.CountTracks(0)
  
  for trackIdx = 1, numTracks do
    local track = reaper.GetTrack(0, trackIdx - 1)
    if track then
      local _, trackName = reaper.GetTrackName(track)
      
      -- Only process IN/ tracks (input tracks with FX)
      if trackName:match("^IN/") then
        -- Get compressor GR (FX slot 1 = ReaComp)
        -- ReaComp meter index for GR is typically index 1
        local retval, gr = reaper.TrackFX_GetNamedConfigParm(track, 1, "GainReduction_dB")
        if retval and gr then
          table.insert(response, string.format("GR,%d,%.2f", trackIdx, tonumber(gr) or 0))
        end
        
        -- Get gate state (FX slot 0 = ReaGate)
        -- Check if gate is open by comparing input to output level
        local gateOpen = false
        local gateLevel = 0
        
        -- ReaGate doesn't have a direct "open" parameter, but we can check
        -- the wet/dry ratio or meter the output. For now, approximate by
        -- checking if threshold is being exceeded (read threshold and compare to track peak)
        local thresh = reaper.TrackFX_GetParamNormalized(track, 0, 0) -- Threshold param
        local threshDb = (thresh * 120) - 60 -- Convert to dB
        
        -- Get track peak level
        local peakL = reaper.Track_GetPeakInfo(track, 0)
        local peakR = reaper.Track_GetPeakInfo(track, 1)
        local maxPeak = math.max(peakL, peakR, 0.0000001)
        local peakDb = 20 * (math.log(maxPeak) / math.log(10))
        
        gateOpen = peakDb > threshDb
        gateLevel = math.max(0, math.min(1, (peakDb + 60) / 60))
        
        table.insert(response, string.format("GATE,%d,%d,%.3f", trackIdx, gateOpen and 1 or 0, gateLevel))
      end
    end
  end
  
  -- Send meter data via response file if we have any
  if #response > 0 then
    local mf = io.open("/tmp/fx_meters.txt", "w")
    if mf then
      mf:write(table.concat(response, "\n") .. "\n")
      mf:close()
    end
  end
end

function Main()
  ProcessCommands()
  PollFxMeters()
  reaper.defer(Main)
end

-- Register exit handler to clean up
function Exit()
  os.remove(CMD_FILE)
end

reaper.atexit(Exit)

-- Start the polling loop
Main()
