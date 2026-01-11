-- lib/State.lua
-- v0.51 (DEEP SERIALIZATION & SESSION DUMP)

local State = {}
-- Dependencias se resuelven via include global, asumiendo "Single Brain"
local Sequencer = include('lib/Sequencer')
local Patchbay = include('lib/Patchbay')
local Clock = include('lib/Clock')

State.session_data = {
  snapshots = {} 
}
for i=1, 16 do State.session_data.snapshots[i] = nil end

function State.init()
  -- Register Norns PSET hooks
  params.action_write = function(filename, name, number)
    State.save_to_disk(number)
  end
  
  params.action_read = function(filename, silent, number)
    State.load_from_disk(number)
  end
end

-- DEEP COPY HELPER
local function deep_copy_table(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy_table(orig_key)] = deep_copy_table(orig_value)
        end
        setmetatable(copy, deep_copy_table(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function State.save_snapshot(slot)
  local snap = {}
  
  -- 1. Steps (Values & Gates)
  snap.steps = {}
  for i=1, 16 do
     snap.steps[i] = {
        vals = deep_copy_table(Sequencer.steps[i].vals),
        gate_active = Sequencer.steps[i].gate_active,
        gate_prob = Sequencer.steps[i].gate_prob,
        gate_len = Sequencer.steps[i].gate_len
     }
  end
  
  -- 2. Patchbay Connections (CRITICAL)
  snap.connections = deep_copy_table(Patchbay.connections)
  
  -- 3. Generators Params (Rates, Swing, Chaos)
  snap.gens = {
     clk_a = { rate=Sequencer.clk_a.rate_index, swing=Sequencer.clk_a.swing, pw=Sequencer.clk_a.pw, muted=Sequencer.clk_a.muted },
     clk_b = { rate=Sequencer.clk_b.rate_index, swing=Sequencer.clk_b.swing, pw=Sequencer.clk_b.pw, muted=Sequencer.clk_b.muted },
     chaos = { prob=Sequencer.gens.chaos.prob, muted=Sequencer.gens.chaos.muted },
     comp  = { thresh=Sequencer.gens.comp.thresh, src_a=Sequencer.gens.comp.src_a, src_b=Sequencer.gens.comp.src_b, muted=Sequencer.gens.comp.muted },
     jump  = { target=Sequencer.gens.jump.target, prob=Sequencer.gens.jump.prob }
  }
  
  State.session_data.snapshots[slot] = snap
  print("State: Saved Snapshot "..slot)
end

function State.load_snapshot(slot)
  local snap = State.session_data.snapshots[slot]
  if not snap then return end
  
  -- Restore Steps
  for i=1, 16 do
     Sequencer.steps[i].vals = deep_copy_table(snap.steps[i].vals)
     Sequencer.steps[i].gate_active = snap.steps[i].gate_active
     Sequencer.steps[i].gate_prob = snap.steps[i].gate_prob
     Sequencer.steps[i].gate_len = snap.steps[i].gate_len
  end
  
  -- Restore Connections
  Patchbay.connections = deep_copy_table(snap.connections)
  
  -- Restore Generators
  local g = snap.gens
  if g then
     Sequencer.clk_a.rate_index = g.clk_a.rate; Sequencer.clk_a.swing = g.clk_a.swing; Sequencer.clk_a.pw = g.clk_a.pw; Sequencer.clk_a.muted = g.clk_a.muted
     Sequencer.clk_b.rate_index = g.clk_b.rate; Sequencer.clk_b.swing = g.clk_b.swing; Sequencer.clk_b.pw = g.clk_b.pw; Sequencer.clk_b.muted = g.clk_b.muted
     Sequencer.gens.chaos.prob = g.chaos.prob; Sequencer.gens.chaos.muted = g.chaos.muted
     Sequencer.gens.comp.thresh = g.comp.thresh; Sequencer.gens.comp.src_a = g.comp.src_a; Sequencer.gens.comp.src_b = g.comp.src_b; Sequencer.gens.comp.muted = g.comp.muted
     Sequencer.gens.jump.target = g.jump.target; Sequencer.gens.jump.prob = g.jump.prob
  end
  
  print("State: Loaded Snapshot "..slot)
end

function State.clear_snapshot(slot)
  State.session_data.snapshots[slot] = nil
  print("State: Cleared Snapshot "..slot)
end

-- DISK I/O (PSET)
function State.save_to_disk(number)
  local filename = _path.data .. "westquencer/set_" .. number .. ".data"
  -- Guardamos TODA la session_data (los 16 snaps)
  -- Y tambien el estado actual como "active_state"?
  -- Por simplicidad, guardamos los snapshots. El estado activo lo guarda params automaticamente? No, params guarda params.
  -- Guardamos snapshots.
  tab.save(State.session_data, filename)
  print("State: Session Saved to Disk.")
end

function State.load_from_disk(number)
  local filename = _path.data .. "westquencer/set_" .. number .. ".data"
  local d = tab.load(filename)
  if d then
     State.session_data = d
     print("State: Session Loaded from Disk.")
  else
     print("State: No Data Found.")
  end
end

return State