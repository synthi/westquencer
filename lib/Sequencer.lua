-- lib/Sequencer.lua
-- v0.60.4 (TRIGGER SPY)

local Step = include('lib/Step')
local LogicOps = include('lib/LogicOps')
local Clock = include('lib/Clock')

local PatchbayRef = nil 
local MidiIORef = nil 

local Sequencer = {}

Sequencer.steps = {} 
Sequencer.pos_h = 1; Sequencer.pos_v = 1; Sequencer.direction_h = 1; Sequencer.running = true 
Sequencer.selection = { active = false, row_id = "A", steps = {} }
Sequencer.loop_start = 1; Sequencer.loop_end = 16; Sequencer.jam_active = false; Sequencer.jam_step = nil
Sequencer.clk_a = Clock.new(); Sequencer.clk_b = Clock.new()
Sequencer.visual = { last_trig_a=0, last_trig_b=0, last_trig_chaos=0, last_trig_comp=0, last_trig_key=0, last_trig_vertical=0, step_prob_result=true }

local BUF_SIZE = 800
Sequencer.gens = {
  chaos = { prob=50, trig=false, muted=false, history={}, prev_state=false },
  comp  = { src_a=1, src_b=2, thresh=0, trig=false, muted=false, history={}, prev_state=false },
  jump  = { target=1, prob=100 },
  key   = { history={}, prev_state=false },
  clk_a_hist = { data={}, prev_state=false },
  clk_b_hist = { data={}, prev_state=false }
}
for i=1,BUF_SIZE do 
  table.insert(Sequencer.gens.chaos.history, 0); table.insert(Sequencer.gens.comp.history, 0); table.insert(Sequencer.gens.key.history, 0)
  table.insert(Sequencer.gens.clk_a_hist.data, 0); table.insert(Sequencer.gens.clk_b_hist.data, 0)
end

function Sequencer.init(pb_ref, midi_ref)
  PatchbayRef = pb_ref 
  MidiIORef = midi_ref 
  for i=1, 16 do Sequencer.steps[i] = Step.new(i) end
  if PatchbayRef then PatchbayRef.connect(LogicOps.BUTTONS.CLOCK_A, LogicOps.BUTTONS.CLOCK_H) end
  print("SEQ v0.60.4: Init.")
end

-- Helpers (Sin cambios)
function Sequencer.add_selection(idx, row) Sequencer.selection.active=true; Sequencer.selection.row_id=row; Sequencer.selection.steps[idx]=true; if Sequencer.on_step_change then Sequencer.on_step_change() end end
function Sequencer.remove_selection(idx) Sequencer.selection.steps[idx]=nil; if Sequencer.on_step_change then Sequencer.on_step_change() end end
function Sequencer.clear_selection() Sequencer.selection.active=false; Sequencer.selection.steps={}; if Sequencer.on_step_change then Sequencer.on_step_change() end end
function Sequencer.modify_focused_value(d) if not Sequencer.selection.active then return end; local r=Sequencer.selection.row_id; for idx,_ in pairs(Sequencer.selection.steps) do local s=Sequencer.steps[idx]; s.vals[r]=util.clamp(s.vals[r]+d, 0, 127) end end
local function apply_rnd(val, strength) if math.random(100) > params:get("rnd_density") then return val end; local range=math.floor(127*(strength/100)); if range==0 then return val end; local delta=math.random(-range, range); return util.clamp(val+delta, 0, 127) end
function Sequencer.randomize_step_values(step_idx) local s=Sequencer.steps[step_idx]; local str=params:get("rnd_strength"); s.vals.A=apply_rnd(s.vals.A, str); s.vals.B=apply_rnd(s.vals.B, str); s.vals.C=apply_rnd(s.vals.C, str); s.vals.D=apply_rnd(s.vals.D, str); if math.random(100)<=params:get("rnd_density") then s.gate_prob=apply_rnd(s.gate_prob, str); s.gate_len=apply_rnd(s.gate_len, str); if math.random(100)<(str/2) then s.gate_active=not s.gate_active end end end
function Sequencer.randomize_row(row_type) local str=params:get("rnd_strength"); for i=1,16 do if math.random(100)<=params:get("rnd_density") then local s=Sequencer.steps[i]; if row_type=="GATE" then s.gate_prob=apply_rnd(s.gate_prob, str); if math.random(100)<(str/2) then s.gate_active=not s.gate_active end else s.vals[row_type]=apply_rnd(s.vals[row_type], str) end end end end
function Sequencer.randomize_global() local scope=params:get("rnd_scope"); if scope==1 or scope==3 then for i=1,16 do Sequencer.randomize_step_values(i) end end; if (scope==2 or scope==3) and PatchbayRef then PatchbayRef.randomize_connections() end end
function Sequencer.set_loop_window(s, e) Sequencer.loop_start=util.clamp(s,1,16); Sequencer.loop_end=util.clamp(e,1,16) end
function Sequencer.reset_loop_window() Sequencer.loop_start=1; Sequencer.loop_end=16 end
local function get_row_val(step, src_idx) if not step then return 0 end; if src_idx==1 then return step.vals.A elseif src_idx==2 then return step.vals.B elseif src_idx==3 then return step.vals.C else return step.vals.D end end
local function push_edge(buffer, state_obj, current_val) local val=(current_val and not state_obj.prev_state) and 1 or 0; table.remove(buffer, 1); table.insert(buffer, val); state_obj.prev_state=current_val end

function Sequencer.clock_coroutine()
  local last_time = util.time()
  local trig_flags = { reset_h=false, dir_h=false, jump=false, reset_v=false, clk_v_prev=false, jam_prev=false }
  
  while true do
    local now = util.time(); local dt = now - last_time; last_time = now; if dt < 0 or dt > 0.5 then dt = 0.005 end
    
    local status, err = pcall(function()
      local step_dur_base = 60 / (clock.get_tempo() or 110) / 4
      
      -- TKB JAM
      if Sequencer.jam_active then
         if Sequencer.jam_step then Sequencer.pos_h = Sequencer.jam_step end
         if not trig_flags.jam_prev then 
            Sequencer.visual.last_trig_key = now; trig_flags.jam_prev = true 
            if Sequencer.steps[Sequencer.pos_h] and MidiIORef then 
               print("SEQ: JAM TRIGGER Step "..Sequencer.pos_h) -- DEBUG
               MidiIORef.send_event(Sequencer.steps[Sequencer.pos_h], 1) 
            end
         end
      else trig_flags.jam_prev = false end
      push_edge(Sequencer.gens.key.history, Sequencer.gens.key, Sequencer.jam_active)

      Sequencer.clk_a:update(dt, step_dur_base); Sequencer.clk_b:update(dt, step_dur_base)
      if Sequencer.clk_a.trig then Sequencer.visual.last_trig_a = now end
      if Sequencer.clk_b.trig then Sequencer.visual.last_trig_b = now end
      push_edge(Sequencer.gens.clk_a_hist.data, Sequencer.gens.clk_a_hist, Sequencer.clk_a.gate_state)
      push_edge(Sequencer.gens.clk_b_hist.data, Sequencer.gens.clk_b_hist, Sequencer.clk_b.gate_state)

      local g_chaos = Sequencer.gens.chaos; g_chaos.trig = false
      if not g_chaos.muted and math.random(100) <= g_chaos.prob then if math.random(100) < 5 then g_chaos.trig = true; Sequencer.visual.last_trig_chaos = now end end
      push_edge(g_chaos.history, g_chaos, g_chaos.trig)

      local g_comp = Sequencer.gens.comp; local was_comp = g_comp.trig; g_comp.trig = false
      local curr_s = Sequencer.steps[Sequencer.pos_h]
      if curr_s and not g_comp.muted then
        local va = get_row_val(curr_s, g_comp.src_a); local vb = get_row_val(curr_s, g_comp.src_b)
        if va > vb + g_comp.thresh then g_comp.trig = true end
      end
      if g_comp.trig and not was_comp then Sequencer.visual.last_trig_comp = now end
      push_edge(g_comp.history, g_comp, g_comp.trig)
      
      if PatchbayRef then
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CLOCK_A, Sequencer.clk_a.gate_state)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CLOCK_B, Sequencer.clk_b.gate_state)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.CHAOS, g_chaos.trig)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.COMPARATOR, g_comp.trig)
        PatchbayRef.set_source_active(LogicOps.BUTTONS.KEY_PULSE, Sequencer.jam_active)
        for i=1, 16 do local g_act = (Sequencer.pos_h == i) and Sequencer.steps[i].gate_active; PatchbayRef.set_source_active(LogicOps.STEP_GATE_BASE_ID + i, g_act) end
      end

      local function read_in(id) if not PatchbayRef then return false end; local v=PatchbayRef.get_input_active(id); PatchbayRef.record_history(id, v); return v end
      
      if read_in(LogicOps.BUTTONS.RESET_H) then if not trig_flags.reset_h then Sequencer.pos_h = 16; trig_flags.reset_h = true end else trig_flags.reset_h = false end
      local dir_in = read_in(LogicOps.BUTTONS.DIR_H); if dir_in then if not trig_flags.dir_h then Sequencer.direction_h = Sequencer.direction_h * -1; trig_flags.dir_h = true end else trig_flags.dir_h = false end
      local is_held = read_in(LogicOps.BUTTONS.HOLD_H)
      local jump_in = read_in(LogicOps.BUTTONS.RND_JUMP); if jump_in then if not trig_flags.jump then if math.random(100) <= Sequencer.gens.jump.prob then local tgt = Sequencer.gens.jump.target; if tgt == 0 then Sequencer.pos_h = math.random(1, 16) else Sequencer.pos_h = util.clamp(tgt, 1, 16) end end; trig_flags.jump = true end else trig_flags.jump = false end
      if read_in(LogicOps.BUTTONS.RESET_V) then if not trig_flags.reset_v then Sequencer.pos_v = 1; trig_flags.reset_v = true end else trig_flags.reset_v = false end

      local clk_v_in = read_in(LogicOps.BUTTONS.CLOCK_V)
      if clk_v_in and not trig_flags.clk_v_prev then
         Sequencer.pos_v = Sequencer.pos_v + 1; if Sequencer.pos_v > 4 then Sequencer.pos_v = 1 end
         if Sequencer.visual.step_prob_result then 
            if Sequencer.steps[Sequencer.pos_h] and Sequencer.steps[Sequencer.pos_h].gate_active then 
               if MidiIORef then 
                  print("SEQ: VERT TRIGGER Step "..Sequencer.pos_h) -- DEBUG
                  MidiIORef.send_event(Sequencer.steps[Sequencer.pos_h], Sequencer.pos_v) 
               end
            end 
         end
         Sequencer.visual.last_trig_vertical = now
      end
      trig_flags.clk_v_prev = clk_v_in
      
      local clk_h_pulse = read_in(LogicOps.BUTTONS.CLOCK_H); local step_changed = false
      if clk_h_pulse and not Sequencer.clk_h_prev then
        if Sequencer.jam_active and Sequencer.jam_step then Sequencer.pos_h = Sequencer.jam_step
        elseif not is_held then
           local next_h = Sequencer.pos_h + Sequencer.direction_h
           if Sequencer.direction_h > 0 then if next_h > Sequencer.loop_end then next_h = Sequencer.loop_start end
           else if next_h < Sequencer.loop_start then next_h = Sequencer.loop_end end end
           if next_h < 1 then next_h = 16; if next_h > 16 then next_h = 1 end end
           Sequencer.pos_h = next_h
        end
        Sequencer.pos_v = 1 
        local curr_s = Sequencer.steps[Sequencer.pos_h]
        if curr_s then
           -- LOGICA DISPARO
           if curr_s.gate_active then
              local gprob = params:get("global_prob") or 100
              local combined_prob = (curr_s.gate_prob / 100) * (gprob / 100) * 100
              Sequencer.visual.step_prob_result = (math.random(100) <= combined_prob)
              
              if Sequencer.visual.step_prob_result then 
                 if MidiIORef then 
                    print("SEQ: BANG! Step " .. Sequencer.pos_h) -- DEBUG CRITICO
                    MidiIORef.send_event(curr_s, 1) 
                 else
                    print("SEQ ERROR: MidiIO Ref is Missing!")
                 end
              end
           else
              Sequencer.visual.step_prob_result = false
           end
        end
        step_changed = true
      end
      Sequencer.clk_h_prev = clk_h_pulse
      if Sequencer.on_step_change and step_changed then Sequencer.on_step_change() end
    end)
    
    if not status then print("SEQ ERROR: " .. tostring(err)) end
    clock.sleep(0.005)
  end
end
return Sequencer
