-- lib/Sequencer.lua
-- v0.52 (TIME-BASED VISUAL SYNC)

local Step = include('lib/Step')
local MidiIO = include('lib/MidiIO')
local LogicOps = include('lib/LogicOps')
local Clock = include('lib/Clock')

local PatchbayRef = nil 

local Sequencer = {}

-- State
Sequencer.steps = {} 
Sequencer.pos_h = 1
Sequencer.pos_v = 1
Sequencer.direction_h = 1
Sequencer.running = true 

Sequencer.editor_focus = { active=false, step_index=0, row_id=nil }

Sequencer.loop_start = 1
Sequencer.loop_end = 16
Sequencer.jam_active = false
Sequencer.jam_step = nil

-- CLOCKS
Sequencer.clk_a = Clock.new()
Sequencer.clk_b = Clock.new()
Sequencer.prev_gate_a = false
Sequencer.prev_gate_b = false

-- VISUAL TIMESTAMPS (La solución al parpadeo errático)
-- Guardamos el momento exacto del último trigger
Sequencer.visual = {
  last_trig_a = 0,
  last_trig_b = 0,
  last_trig_chaos = 0,
  last_trig_comp = 0,
  last_trig_vertical = 0,
  step_prob_result = true
}

-- GENS
Sequencer.gens = {
  chaos = { prob=50, trig=false, muted=false, history={} },
  comp  = { src_a=1, src_b=2, thresh=0, trig=false, muted=false, history={} },
  jump  = { target=1, prob=100 }
}

for i=1,64 do table.insert(Sequencer.gens.chaos.history, 0) end
for i=1,64 do table.insert(Sequencer.gens.comp.history, 0) end

function Sequencer.init(pb_ref)
  PatchbayRef = pb_ref 
  for i=1, 16 do Sequencer.steps[i] = Step.new(i) end
  if PatchbayRef then PatchbayRef.connect(LogicOps.BUTTONS.CLOCK_A, LogicOps.BUTTONS.CLOCK_H) end
  print("SEQ v0.52: Init (Time-Based Visuals).")
end

-- Helpers UI (Standard)
function Sequencer.set_loop_window(s, e) Sequencer.loop_start=util.clamp(s,1,16); Sequencer.loop_end=util.clamp(e,1,16) end
function Sequencer.reset_loop_window() Sequencer.loop_start=1; Sequencer.loop_end=16 end
function Sequencer.set_focus(idx, row) Sequencer.editor_focus.active=true; Sequencer.editor_focus.step_index=idx; Sequencer.editor_focus.row_id=row; if Sequencer.on_step_change then Sequencer.on_step_change() end end
function Sequencer.clear_focus() Sequencer.editor_focus.active=false; if Sequencer.on_step_change then Sequencer.on_step_change() end end
function Sequencer.modify_focused_value(d) if not Sequencer.editor_focus.active then return end; local s=Sequencer.steps[Sequencer.editor_focus.step_index]; local r=Sequencer.editor_focus.row_id; s.vals[r]=util.clamp(s.vals[r]+d, 0, 127) end
local function get_row_val(step, src_idx) if not step then return 0 end; if src_idx==1 then return step.vals.A elseif src_idx==2 then return step.vals.B elseif src_idx==3 then return step.vals.C else return step.vals.D end end


function Sequencer.clock_coroutine()
  local last_time = util.time()
  local trig_flags = { reset_h=false, dir_h=false, jump=false, reset_v=false, clk_v_prev=false }
  
  while true do
    local now = util.time()
    local dt = now - last_time
    last_time = now
    if dt < 0 or dt > 0.5 then dt = 0.005 end
    
    pcall(function()
      local bpm = clock.get_tempo() or 110
      if bpm < 10 then bpm = 110 end
      local step_dur_base = 60 / bpm / 4
      
      -- 1. CALCULAR GENERADORES
      Sequencer.clk_a:update(dt, step_dur_base)
      Sequencer.clk_b:update(dt, step_dur_base)
      
      -- Visual Timestamps (Si hay flanco de subida, actualizamos tiempo)
      if Sequencer.clk_a.trig then Sequencer.visual.last_trig_a = now end
      if Sequencer.clk_b.trig then Sequencer.visual.last_trig_b = now end

      -- Chaos
      local g_chaos = Sequencer.gens.chaos
      g_chaos.trig = false
      if not g_chaos.muted and math.random(100) <= g_chaos.prob then 
         if math.random(100) < 5 then 
            g_chaos.trig = true 
            Sequencer.visual.last_trig_chaos = now
         end 
      end
      -- Para el Osciloscopio: Insertamos Trigger (o Gate si preferimos ver pulso)
      -- Insertamos trigger visual 1/0
      table.remove(g_chaos.history, 1); table.insert(g_chaos.history, g_chaos.trig and 1 or 0)

      -- Comparator
      local g_comp = Sequencer.gens.comp
      local was_comp = g_comp.trig
      g_comp.trig = false
      local curr_s = Sequencer.steps[Sequencer.pos_h]
      if curr_s and not g_comp.muted then
        local va = get_row_val(curr_s, g_comp.src_a)
        local vb = get_row_val(curr_s, g_comp.src_b)
        -- Logica Comparator: Output HIGH mientras A > B (Gate Behavior)
        if va > vb + g_comp.thresh then 
           g_comp.trig = true 
        end
      end
      -- Visual Trigger solo en el flanco de subida del comparador para no saturar
      if g_comp.trig and not was_comp then Sequencer.visual.last_trig_comp = now end
      
      -- Historial: Guardamos el estado Gate (1 sostenido)
      table.remove(g_comp.history, 1); table.insert(g_comp.history, g_comp.trig and 1 or 0)
      
      -- 2. PUBLICAR AL PATCHBAY
      if PatchbayRef then
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CLOCK_A, Sequencer.clk_a.gate_state)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CLOCK_B, Sequencer.clk_b.gate_state)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CHAOS, g_chaos.trig)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.COMPARATOR, g_comp.trig)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.KEY_PULSE, Sequencer.jam_active)
        
        for i=1, 16 do
          local g_act = (Sequencer.pos_h == i) and Sequencer.steps[i].gate_active
          PatchbayRef.set_source_active(LogicOps.STEP_GATE_BASE_ID + i, g_act)
        end
      end

      -- 3. LEER ENTRADAS
      local function read_in(id) 
         if not PatchbayRef then return false end
         local v=PatchbayRef.get_input_active(id)
         PatchbayRef.record_history(id, v)
         return v 
      end
      
      if read_in(LogicOps.BUTTONS.RESET_H) then
        if not trig_flags.reset_h then Sequencer.pos_h = 16; trig_flags.reset_h = true end
      else trig_flags.reset_h = false end
      
      local dir_in = read_in(LogicOps.BUTTONS.DIR_H)
      if dir_in then
         if not trig_flags.dir_h then 
             Sequencer.direction_h = Sequencer.direction_h * -1; trig_flags.dir_h = true 
         end
      else trig_flags.dir_h = false end
      
      local is_held = read_in(LogicOps.BUTTONS.HOLD_H)
      
      local jump_in = read_in(LogicOps.BUTTONS.RND_JUMP)
      if jump_in then
         if not trig_flags.jump then
            if math.random(100) <= Sequencer.gens.jump.prob then 
               Sequencer.pos_h = Sequencer.gens.jump.target 
            end
            trig_flags.jump = true
         end
      else trig_flags.jump = false end
      
      if read_in(LogicOps.BUTTONS.RESET_V) then
         if not trig_flags.reset_v then Sequencer.pos_v = 1; trig_flags.reset_v = true end
      else trig_flags.reset_v = false end

      -- 4. EJECUTAR MOTORES
      local clk_v_in = read_in(LogicOps.BUTTONS.CLOCK_V)
      if clk_v_in and not trig_flags.clk_v_prev then
         Sequencer.pos_v = Sequencer.pos_v + 1
         if Sequencer.pos_v > 4 then Sequencer.pos_v = 1 end
         if Sequencer.visual.step_prob_result then
            if Sequencer.steps[Sequencer.pos_h] then MidiIO.send_event(Sequencer.steps[Sequencer.pos_h], Sequencer.pos_v) end
         end
         Sequencer.visual.last_trig_vertical = now -- Visual Trigger
      end
      trig_flags.clk_v_prev = clk_v_in
      
      local clk_h_pulse = read_in(LogicOps.BUTTONS.CLOCK_H)
      local step_changed = false
      
      if clk_h_pulse and not Sequencer.clk_h_prev then
        if Sequencer.jam_active and Sequencer.jam_step then
           Sequencer.pos_h = Sequencer.jam_step
        elseif not is_held then
           local next_h = Sequencer.pos_h + Sequencer.direction_h
           if Sequencer.direction_h > 0 then
              if next_h > Sequencer.loop_end then next_h = Sequencer.loop_start end
           else
              if next_h < Sequencer.loop_start then next_h = Sequencer.loop_end end
           end
           if next_h < 1 then next_h = 16 end
           if next_h > 16 then next_h = 1 end
           Sequencer.pos_h = next_h
        end
        Sequencer.pos_v = 1 
        
        local curr_s = Sequencer.steps[Sequencer.pos_h]
        if curr_s then
           Sequencer.visual.step_prob_result = (math.random(100) <= curr_s.gate_prob)
           if Sequencer.visual.step_prob_result then MidiIO.send_event(curr_s, 1) end
        end
        step_changed = true
      end
      Sequencer.clk_h_prev = clk_h_pulse
      
      -- 5. UPDATE UI (Solo si hay cambios relevantes)
      -- Ahora que usamos Timestamps, no necesitamos refrescar tan a menudo desde el motor
      -- El UI Metro se encarga de leer los timestamps.
      -- Solo forzamos si cambia el paso para actualizar posiciones.
      if Sequencer.on_step_change and step_changed then
         Sequencer.on_step_change()
      end
      
    end)
    clock.sleep(0.005)
  end
end
return Sequencer