-- lib/Step.lua
-- v0.16 (GATE PARAMS)
--
-- Changelog:
-- v0.16: Añadidos parámetros gate_len y gate_prob.

local Step = {}
Step.__index = Step

function Step.new(id)
  local s = {}
  setmetatable(s, Step)
  
  s.id = id
  
  -- Valores CV (0-127)
  s.vals = { A=64, B=0, C=0, D=127 }
  
  -- Lógica de Gate
  s.gate_active = false     -- On/Off básico
  s.gate_prob = 100         -- Probabilidad (0-100%)
  s.gate_len = 50           -- Longitud (0-100%, 50 = media duración)
  
  -- Lógica Avanzada
  s.logic_mode = "NONE"
  s.vertical_burst = false
  
  return s
end

return Step