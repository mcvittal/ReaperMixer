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
      
      -- Handle send read request: S,trackIdx (read sends for a track)
      local sTrack = line:match("^S,(%d+)")
      if sTrack then
        sTrack = tonumber(sTrack)
        local track = GetTrackByIndex(sTrack)
        if track then
          local response = {}
          local numSends = reaper.GetTrackNumSends(track, 0) -- 0 = sends
          
          for sendIdx = 0, numSends - 1 do
            local sendVol = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "D_VOL")
            local sendPan = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "D_PAN")
            table.insert(response, string.format("S,%d,%d,%.6f,%.6f", sTrack, sendIdx, sendVol, sendPan))
          end
          
          local rf = io.open(RESPONSE_FILE, "w")
          if rf then
            rf:write(table.concat(response, "\n") .. "\n")
            rf:close()
            reaper.ShowConsoleMsg("  Wrote SEND response for track " .. sTrack .. " (" .. numSends .. " sends)\n")
          end
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

function Main()
  ProcessCommands()
  reaper.defer(Main)
end

-- Register exit handler to clean up
function Exit()
  os.remove(CMD_FILE)
end

reaper.atexit(Exit)

-- Start the polling loop
Main()
