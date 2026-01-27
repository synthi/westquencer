-- lib/MidiIO.lua
-- v0.61.1 (FIX: MUSICUTIL SNAP)

local MidiIO = {}
local musicutil = require 'musicutil'
local nb_ref = nil 

function MidiIO.init(nb_lib)
  nb_ref = nb_lib
  print("MidiIO v0.61.1: Fix Musicutil.")
end

local function get_scaled_val(val, row_char)
  local min = params:get("row_"..row_char.."_min")
  local max = params:get("row_"..row_char.."_max")
  return util.linlin(0, 127, min, max, val)
end

-- HELPER DE ESCALAS CORREGIDO
local function get_note(val)
  -- 1. Obtener Root (Params devuelve 1-12, musicutil necesita 0-11)
  local root_param = params:get("root_note") or 1
  local root = root_param - 1 
  
  -- 2. Obtener Nombre de Escala
  local scale_idx = params:get("scale_mode") or 1
  -- Proteccion por si musicutil no esta cargado o el indice falla
  local scale_name = "Major"
  if musicutil.SCALES[scale_idx] then 
     scale_name = musicutil.SCALES[scale_idx].name 
  end

  -- 3. Generar la tabla de notas para todo el rango MIDI (128 notas)
  -- generate_scale(root, scale_name, octaves)
  local scale_pool = musicutil.generate_scale(root, scale_name, 11)
  
  -- 4. Ajustar el valor (0-127) a la nota mas cercana de la piscina
  return musicutil.snap_note_to_array(val, scale_pool)
end

function MidiIO.send_event(step, pos_v)
  if not nb_ref then return end
  
  local rows = {"A", "B", "C", "D"}
  
  -- DURACION
  local tempo = clock.get_tempo() or 110
  local step_time = 60 / tempo / 4 
  local duration = (step.gate_len / 100) * 0.9 * step_time 
  if duration < 0.05 then duration = 0.05 end
  
  -- LEGATO
  if step.gate_tie then duration = duration + step_time end 
  
  -- VELOCITY
  local vel = 100
  for _, r in ipairs(rows) do
     if params:get("row_"..r.."_role") == 2 then 
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
     player_abcd:play_note(note, vel_norm, duration)
  end
  
  -- === INDIVIDUAL ROW VOICES ===
  for _, r in ipairs(rows) do
     local role = params:get("row_"..r.."_role")
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
           
        elseif role == 4 then -- ROLE: MOD
           if player.mod then
              local mod_val = get_scaled_val(val, r) / 127
              player:mod(mod_val)
           end
        end
     end
  end
end

return MidiIO
