-- lib/Patchbay.lua
-- v0.58 (SMART RANDOM)

local Patchbay = {}
local LogicOps = include('lib/LogicOps')

Patchbay.connections = {}
Patchbay.source_states = {} 
Patchbay.input_history = {} 

function Patchbay.init_history(id)
  if not Patchbay.input_history[id] then
    Patchbay.input_history[id] = {}
    for i=1, 300 do Patchbay.input_history[id][i] = 0 end -- 300 steps (1.5s)
  end
end

function Patchbay.connect(src_id, dst_id)
  if not Patchbay.connections[dst_id] then Patchbay.connections[dst_id] = {} end
  for _, ex in ipairs(Patchbay.connections[dst_id]) do 
    if ex == src_id then return end 
  end
  table.insert(Patchbay.connections[dst_id], src_id)
  Patchbay.init_history(dst_id)
end

function Patchbay.toggle_connection(src_id, dst_id)
  if not Patchbay.connections[dst_id] then Patchbay.connections[dst_id] = {} end
  local list = Patchbay.connections[dst_id]
  local found_idx = nil
  for i, s in ipairs(list) do if s == src_id then found_idx = i; break end end
  
  if found_idx then table.remove(list, found_idx); return false
  else table.insert(list, src_id); Patchbay.init_history(dst_id); return true end
end

function Patchbay.is_connected(src_id, dst_id)
  local list = Patchbay.connections[dst_id]
  if not list then return false end
  for _, s in ipairs(list) do if s == src_id then return true end end
  return false
end

function Patchbay.set_source_active(src_id, active) Patchbay.source_states[src_id] = active end

function Patchbay.get_input_active(dst_id)
  local list = Patchbay.connections[dst_id]
  if not list then return false end
  for _, src_id in ipairs(list) do if Patchbay.source_states[src_id] then return true end end
  return false
end

function Patchbay.record_history(dst_id, val)
  if not Patchbay.input_history[dst_id] then Patchbay.init_history(dst_id) end
  -- Edge detection para Inputs? No necesario, queremos ver el Gate suma
  table.remove(Patchbay.input_history[dst_id], 1)
  table.insert(Patchbay.input_history[dst_id], val and 1 or 0)
end

-- SMART RANDOMIZER
function Patchbay.randomize_connections()
  -- 1. Clear All
  Patchbay.connections = {}
  
  -- 2. SOURCES DISPONIBLES
  local logic_sources = {LogicOps.BUTTONS.CLOCK_A, LogicOps.BUTTONS.CLOCK_B, LogicOps.BUTTONS.CHAOS, LogicOps.BUTTONS.COMPARATOR}
  
  -- 3. GARANTIZAR VIDA (Clock H)
  if math.random(100) < 90 then
     -- 70% Clock, 30% Chaos/Others
     local src
     if math.random(100) < 70 then 
        src = (math.random(100) < 50) and LogicOps.BUTTONS.CLOCK_A or LogicOps.BUTTONS.CLOCK_B
     else
        src = logic_sources[math.random(#logic_sources)]
     end
     Patchbay.connect(src, LogicOps.BUTTONS.CLOCK_H)
  end
  
  -- 4. RESTO DE INPUTS
  for _, dst in ipairs(LogicOps.INPUTS) do
     if dst ~= LogicOps.BUTTONS.CLOCK_H then
        if math.random(100) < 30 then -- 30% prob de conexión
           local src_type = math.random(100)
           local src
           if src_type < 60 then -- Logic Source
              src = logic_sources[math.random(#logic_sources)]
           else -- Step Gate (Self-gen)
              src = LogicOps.STEP_GATE_BASE_ID + math.random(1, 16)
           end
           Patchbay.connect(src, dst)
        end
     end
  end
end

return Patchbay