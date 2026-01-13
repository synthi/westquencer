-- lib/State.lua
-- v0.58 (INJECTION FIX)

local State = {}
-- Eliminados los includes locales que causaban duplicidad
local SequencerRef = nil
local PatchbayRef = nil

State.session_data = { snapshots = {} }
for i=1, 16 do State.session_data.snapshots[i] = nil end

function State.init(seq_ref, pb_ref)
  SequencerRef = seq_ref
  PatchbayRef = pb_ref
  
  params.action_write = function(filename, name, number) State.save_to_disk(number) end
  params.action_read = function(filename, silent, number) State.load_from_disk(number) end
end

local function deep_copy_table(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do copy[deep_copy_table(orig_key)] = deep_copy_table(orig_value) end
        setmetatable(copy, deep_copy_table(getmetatable(orig)))
    else copy = orig end
    return copy
end

function State.save_snapshot(slot)
  if not SequencerRef or not PatchbayRef then return end
  
  local snap = {}
  snap.steps = {}
  for i=1, 16 do
     snap.steps[i] = {
        vals = deep_copy_table(SequencerRef.steps[i].vals),
        gate_active = SequencerRef.steps[i].gate_active,
        gate_prob = SequencerRef.steps[i].gate_prob,
        gate_len = SequencerRef.steps[i].gate_len
     }
  end
  snap.connections = deep_copy_table(PatchbayRef.connections)
  snap.gens = {
     clk_a = { rate=SequencerRef.clk_a.rate_index, swing=SequencerRef.clk_a.swing, pw=SequencerRef.clk_a.pw, muted=SequencerRef.clk_a.muted },
     clk_b = { rate=SequencerRef.clk_b.rate_index, swing=SequencerRef.clk_b.swing, pw=SequencerRef.clk_b.pw, muted=SequencerRef.clk_b.muted },
     chaos = { prob=SequencerRef.gens.chaos.prob, muted=SequencerRef.gens.chaos.muted },
     comp  = { thresh=SequencerRef.gens.comp.thresh, src_a=SequencerRef.gens.comp.src_a, src_b=SequencerRef.gens.comp.src_b, muted=SequencerRef.gens.comp.muted },
     jump  = { target=SequencerRef.gens.jump.target, prob=SequencerRef.gens.jump.prob }
  }
  State.session_data.snapshots[slot] = snap
  print("State: Saved Snapshot "..slot)
end

function State.load_snapshot(slot)
  local snap = State.session_data.snapshots[slot]
  if not snap or not SequencerRef then return end
  
  for i=1, 16 do
     SequencerRef.steps[i].vals = deep_copy_table(snap.steps[i].vals)
     SequencerRef.steps[i].gate_active = snap.steps[i].gate_active
     SequencerRef.steps[i].gate_prob = snap.steps[i].gate_prob
     SequencerRef.steps[i].gate_len = snap.steps[i].gate_len
  end
  PatchbayRef.connections = deep_copy_table(snap.connections)
  local g = snap.gens
  if g then
     SequencerRef.clk_a.rate_index = g.clk_a.rate; SequencerRef.clk_a.swing = g.clk_a.swing; SequencerRef.clk_a.pw = g.clk_a.pw; SequencerRef.clk_a.muted = g.clk_a.muted
     SequencerRef.clk_b.rate_index = g.clk_b.rate; SequencerRef.clk_b.swing = g.clk_b.swing; SequencerRef.clk_b.pw = g.clk_b.pw; SequencerRef.clk_b.muted = g.clk_b.muted
     SequencerRef.gens.chaos.prob = g.chaos.prob; SequencerRef.gens.chaos.muted = g.chaos.muted
     SequencerRef.gens.comp.thresh = g.comp.thresh; SequencerRef.gens.comp.src_a = g.comp.src_a; SequencerRef.gens.comp.src_b = g.comp.src_b; SequencerRef.gens.comp.muted = g.comp.muted
     SequencerRef.gens.jump.target = g.jump.target; SequencerRef.gens.jump.prob = g.jump.prob
  end
  print("State: Loaded Snapshot "..slot)
end

function State.clear_snapshot(slot) State.session_data.snapshots[slot] = nil; print("State: Cleared Snapshot "..slot) end
function State.save_to_disk(number) tab.save(State.session_data, _path.data .. "westquencer/set_" .. number .. ".data"); print("State: Session Saved.") end
function State.load_from_disk(number) local d = tab.load(_path.data .. "westquencer/set_" .. number .. ".data"); if d then State.session_data = d; print("State: Session Loaded.") else print("State: No Data Found.") end end
return State