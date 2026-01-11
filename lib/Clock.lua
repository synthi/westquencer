-- lib/Clock.lua
-- v0.33 (REAL SWING MATH)

local Clock = {}
Clock.__index = Clock

Clock.RATES = {
  16, 12, 8, 7, 6, 5, 4, 3, 2,
  1,
  0.5, 0.333, 0.25, 0.2, 0.166, 0.142, 0.125, 0.111, 0.1, 0.083, 0.0625
}

Clock.NAMES = {
  "/16", "/12", "/8", "/7", "/6", "/5", "/4", "/3", "/2",
  "x1",
  "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x16"
}

function Clock.new()
  local c = {}
  setmetatable(c, Clock)
  c.phase = 0
  c.trig = false
  c.gate_state = false
  c.rate_index = 10 -- x1
  c.swing = 50      -- 50% = No Swing, >50% = Swing
  c.pw = 50
  c.muted = false
  c.parity = 0      -- 0 = Odd step (Long), 1 = Even step (Short)
  c.history = {}
  for i=1, 64 do c.history[i] = 0 end
  return c
end

function Clock:update(dt, step_dur_base)
  self.trig = false
  
  if self.muted then 
    self:push_history(0)
    return 
  end
  
  -- 1. Calcular Multiplicador de Velocidad
  local mult = 1
  local idx = util.clamp(self.rate_index, 1, #Clock.RATES)
  
  if idx <= 9 then
     mult = Clock.RATES[idx]
  elseif idx == 10 then
     mult = 1
  else
     local multis = {2,3,4,5,6,7,8,9,10,11,12,16}
     local sub_idx = idx - 10
     if multis[sub_idx] then mult = 1/multis[sub_idx] end
  end
  
  local cycle_dur = step_dur_base * mult

  -- 2. Aplicar Matemática de Swing
  -- Solo aplica si Swing != 50.
  -- Parity 0 (Beat): Se alarga. Parity 1 (Off-beat): Se acorta.
  local swing_factor = 1.0
  if self.swing ~= 50 then
    -- Convertir 0-100 a factor de deformación. 
    -- 50 -> 0.0, 75 -> 0.33 (Tresillo aprox)
    local s_val = (util.clamp(self.swing, 0, 100) - 50) / 75.0 
    if self.parity == 0 then
       swing_factor = 1.0 + s_val
    else
       swing_factor = 1.0 - s_val
    end
  end
  
  local current_dur = cycle_dur * swing_factor
  
  -- 3. Acumulador de Fase
  self.phase = self.phase + dt
  
  while self.phase >= current_dur do
    self.phase = self.phase - current_dur
    self.trig = true
    self.parity = 1 - self.parity -- Alternar paridad para Swing
  end
  
  -- 4. Gate / Pulse Width
  -- El PW se calcula sobre el ciclo base para consistencia visual
  local duty = current_dur * (self.pw / 100)
  self.gate_state = (self.phase < duty)
  
  self:push_history(self.gate_state and 1 or 0)
end

function Clock:push_history(val)
  table.remove(self.history, 1)
  table.insert(self.history, val)
end

return Clock