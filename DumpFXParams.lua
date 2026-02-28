-- Dump FX Parameters for first input track
-- Run this in Reaper to see all parameter indices

local track = reaper.GetTrack(0, 0) -- First track (0-indexed)
if not track then
  reaper.ShowConsoleMsg("No track found!\n")
  return
end

-- Get track name
local _, trackName = reaper.GetTrackName(track)
reaper.ShowConsoleMsg("Track: " .. trackName .. "\n\n")

-- Dump params for FX slots 0, 1, 2 (Gate, Comp, EQ)
local fxNames = {"Gate", "Compressor", "EQ"}

for fxIdx = 0, 2 do
  local _, fxName = reaper.TrackFX_GetFXName(track, fxIdx, "")
  reaper.ShowConsoleMsg("\n========================================\n")
  reaper.ShowConsoleMsg("FX " .. fxIdx .. " (" .. fxNames[fxIdx+1] .. "): " .. (fxName or "unknown") .. "\n")
  reaper.ShowConsoleMsg("========================================\n")

  local numParams = reaper.TrackFX_GetNumParams(track, fxIdx)
  reaper.ShowConsoleMsg("Total params: " .. numParams .. "\n\n")

  for paramIdx = 0, numParams - 1 do
    local _, paramName = reaper.TrackFX_GetParamName(track, fxIdx, paramIdx)
    local val = reaper.TrackFX_GetParamNormalized(track, fxIdx, paramIdx)
    reaper.ShowConsoleMsg(string.format("Param %2d: %-30s = %.4f\n", paramIdx, paramName, val))
  end
end

reaper.ShowConsoleMsg("\n\n========================================\n")
reaper.ShowConsoleMsg("Copy this entire output and share it!\n")
reaper.ShowConsoleMsg("========================================\n")
