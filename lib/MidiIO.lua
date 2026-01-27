-- lib/MidiIO.lua
-- v0.62 (PITCH RANGE & OCTAVE)

local MidiIO = {}
local musicutil = require 'musicutil'
local nb_ref = nil 

function MidiIO.init(nb_lib)
  nb_ref = nb_lib
  print("MidiIO v0.62: Math Engine Ready.")
end

local function get_scaled_val(val, row_char)
  local min = params:get("row_"..row_char.."_min")
  local max = params:get("row_"..row_char.."_max")
  return util.linlin(0, 127, min, max, val)
end

-- HELPER: NOTA AVANZADA
local function get_note(val)
  -- 1. Parametros
  local root_param = params:get("root_note") or 1
  local root = root_param - 1 
  local scale_idx = params:get("scale_mode") or 1
  local scale_name = musicutil.SCALES[scale_idx].name 
  
  -- 2. Range & Base Octave
  local range_opt = params:get("pitch_range") -- 1=1Oct, 2=2Oct, 3=3Oct, 4=4Oct, 5=Full
  local base_oct = params:get("base_octave")
  
  local oct_span = 1
  if range_opt == 2 then oct_span = 2
  elseif range_opt == 3 then oct_span = 3
  elseif range_opt == 4 then oct_span = 4
  elseif range_opt == 5 then oct_span = 10.5 end -- Full 0-127
  
  -- 3. Calcular Nota Raw
  -- Normalizar 0-1
  local norm = val / 127
  -- Escalar a rango de semitonos
  local semitones = norm * (oct_span * 12)
  -- Sumar offset de octava base (base * 12)
  local raw_note = semitones + (base_oct * 12) + 24 -- +24 para que Base 0 sea C1 (o C3 según standard)
  
  -- 4. Quantizar
  local scale_pool = musicutil.generate_scale(root, scale_name, 10)
  return musicutil.snap_note_to_array(math.floor(raw_note), scale_pool)
end

function MidiIO.send_event(step, pos_v)
  if not nb_ref then return end
  local rows = {"A", "B", "C", "D"}
  
  local tempo = clock.get_tempo() or 110
  local step_time = 60 / tempo / 4 
  local duration = (step.gate_len / 100) * 0.9 * step_time 
  if duration < 0.05 then duration = 0.05 end
  if step.gate_tie then duration = duration + step_time end 
  
  local vel = 100
  for _, r in ipairs(rows) do
     if params:get("row_"..r.."_role") == 2 then vel = get_scaled_val(step.vals[r], r) end
  end
  local vel_norm = util.clamp(vel / 127, 0, 1) 
  
  -- MAIN VOICE
  local abcd_row = rows[pos_v] 
  local abcd_val = step.vals[abcd_row]
  local player_abcd = params:lookup_param("voice_abcd"):get_player()
  
  if player_abcd and player_abcd.play_note then
     local note = get_note(abcd_val)
     player_abcd:play_note(note, vel_norm, duration)
  end
  
  -- INDIVIDUAL VOICES
  for _, r in ipairs(rows) do
     local role = params:get("row_"..r.."_role")
     local player = params:lookup_param("voice_"..string.lower(r)):get_player()
     local val = step.vals[r]
     
     if player then
        if role == 1 then -- Pitch
           if player.play_note then
              local note = get_note(val)
              player:play_note(note, vel_norm, duration)
           end
        elseif role == 3 then -- CC
           if player.cc then
              local cc_num = params:get("row_"..r.."_cc")
              local cc_val = get_scaled_val(val, r) / 127 
              player:cc(cc_num, cc_val)
           end
        elseif role == 4 then -- Mod
           if player.mod then
              local mod_val = get_scaled_val(val, r) / 127
              player:mod(mod_val)
           end
        end
     end
  end
end

return MidiIO