-- lib/MidiIO.lua
-- MIDI Output Manager.
-- Handles MPE Voice Allocation and Note/CC transmission.

local MidiIO = {}
local midi_out

function MidiIO.init()
  midi_out = midi.connect(1)
end

function MidiIO.send_event(step_obj, vertical_index)
  -- 1. Identify active value based on Vertical Index
  -- 2. Determine functionality (Pitch vs CC) from PARAMS
  -- 3. Apply Velocity if configured
  
  -- Stub for Note On
  if step_obj.gate_active then
    -- midi_out:note_on(step_obj.vals.A, 100, 1)
  end
end

return MidiIO