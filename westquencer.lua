-- lib/MidiIO.lua
-- v0.61 (NATIVE NB IMPLEMENTATION: play_note)

local MidiIO = {}
local musicutil = require 'musicutil'
local nb_ref = nil 

function MidiIO.init(nb_lib)
  nb_ref = nb_lib
  print("MidiIO v0.61: Native Engine Ready.")
end

local function get_scaled_val(val, row_char)
  local min = params:get("row_"..row_char.."_min")
  local max = params:get("row_"..row_char.."_max")
  return util.linlin(0, 127, min, max, val)
end

local function get_note(val)
  local root = params:get("root_note") or 0
  local scale_type = params:get("scale_mode") or 1
  return musicutil.snap_note_to_scale(val, root, scale_type)
end

function MidiIO.send_event(step, pos_v)
  if not nb_ref then return end
  
  local rows = {"A", "B", "C", "D"}
  
  -- DURACION (Calculada para NB: Segundos)
  local tempo = clock.get_tempo() or 110
  local step_time = 60 / tempo / 4 -- 1/16th en segundos
  -- 100% gate = 90% del tiempo del paso para dejar respirar, ajustable
  local duration = (step.gate_len / 100) * 0.9 * step_time 
  if duration < 0.05 then duration = 0.05 end
  
  -- LEGATO (Si TIE está activo, sumamos un paso extra de duración)
  if step.gate_tie then duration = duration + step_time end 
  
  -- VELOCITY (Normalizada 0.0 - 1.0 para NB)
  local vel = 100
  for _, r in ipairs(rows) do
     if params:get("row_"..r.."_role") == 2 then -- Role 2 = Velocity
        vel = get_scaled_val(step.vals[r], r)
     end
  end
  local vel_norm = util.clamp(vel / 127, 0, 1) 
  
  -- === MAIN VOICE (ABCD MULTIPLEXER) ===
  local abcd_row = rows[pos_v] 
  local abcd_val = step.vals[abcd_row]
  local player_abcd = params:lookup_param("voice_abcd"):get_player()
  
  if player_abcd and player_abcd.play_note then
     local note = get_note(abcd_val)
     -- Metodo Nativo: play_note(note, velocity, duration_sec)
     player_abcd:play_note(note, vel_norm, duration)
  elseif player_abcd then
     -- Debug si el player existe pero no tiene el método (raro en nb estándar)
     print("MidiIO Error: Player '"..player_abcd.name.."' missing :play_note")
  end
  
  -- === INDIVIDUAL ROW VOICES ===
  for _, r in ipairs(rows) do
     local role = params:get("row_"..r.."_role")
     -- Buscar player especifico para esta fila (voice_a, voice_b...)
     local player = params:lookup_param("voice_"..string.lower(r)):get_player()
     local val = step.vals[r]
     
     if player then
        if role == 1 then -- ROLE: PITCH
           if player.play_note then
              local note = get_note(val)
              player:play_note(note, vel_norm, duration)
           end
           
        elseif role == 3 then -- ROLE: CC
           if player.cc then
              local cc_num = params:get("row_"..r.."_cc")
              local cc_val = get_scaled_val(val, r) / 127 
              player:cc(cc_num, cc_val)
           end
           
        elseif role == 4 then -- ROLE: MOD (Timbre/Cutoff genérico de NB)
           if player.mod then
              local mod_val = get_scaled_val(val, r) / 127
              player:mod(mod_val)
           end
        end
     end
  end
end

return MidiIO
