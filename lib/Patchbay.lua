-- lib/Patchbay.lua
-- v0.29 (CORE)

local Patchbay = {}

Patchbay.connections = {}
Patchbay.source_states = {} 
Patchbay.input_history = {} 

function Patchbay.init_history(id)
  if not Patchbay.input_history[id] then
    Patchbay.input_history[id] = {}
    for i=1, 64 do Patchbay.input_history[id][i] = 0 end
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
  
  for i, s in ipairs(list) do 
    if s == src_id then found_idx = i; break end 
  end
  
  if found_idx then
    table.remove(list, found_idx)
    return false
  else 
    table.insert(list, src_id)
    Patchbay.init_history(dst_id)
    return true 
  end
end

function Patchbay.is_connected(src_id, dst_id)
  local list = Patchbay.connections[dst_id]
  if not list then return false end
  for _, s in ipairs(list) do if s == src_id then return true end end
  return false
end

function Patchbay.set_source_active(src_id, active)
  Patchbay.source_states[src_id] = active
end

function Patchbay.get_input_active(dst_id)
  local list = Patchbay.connections[dst_id]
  if not list then return false end
  for _, src_id in ipairs(list) do
    if Patchbay.source_states[src_id] then return true end
  end
  return false
end

function Patchbay.record_history(dst_id, val)
  if not Patchbay.input_history[dst_id] then Patchbay.init_history(dst_id) end
  table.remove(Patchbay.input_history[dst_id], 1)
  table.insert(Patchbay.input_history[dst_id], val and 1 or 0)
end

return Patchbay