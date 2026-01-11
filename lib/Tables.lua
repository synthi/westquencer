-- lib/Tables.lua
-- Lookup Tables for optimization (Drift, Brightness curves).

local Tables = {}

Tables.drift_curve = {}
Tables.led_brightness = {}

function Tables.init()
  -- 1. Pre-calculate Gaussian Drift (1024 values)
  for i=1, 1024 do
    -- Simple approximation or math.random
    Tables.drift_curve[i] = math.random(-10, 10) / 100.0
  end
  
  -- 2. Pre-calculate LED curves (0-15) for smooth faders
  for i=0, 127 do
    Tables.led_brightness[i] = math.floor((i / 127) * 15)
  end
end

function Tables.get_drift()
  local idx = math.random(1, 1024)
  return Tables.drift_curve[idx]
end

return Tables