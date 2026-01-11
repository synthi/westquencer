-- lib/GridUI.lua
-- v0.52 (BALANCED BRIGHTNESS & TIME-BASED RENDERING)

local GridUI = {}
local LogicOps = include('lib/LogicOps')
local State = include('lib/State') 

local EngineRef = nil 
local ScreenRef = nil
local PatchbayRef = nil

GridUI.device = nil
GridUI.connected = false
GridUI.dirty = true
GridUI.cache = {} 
GridUI.shift_held = false
GridUI.patching_src = nil
GridUI.patching_dst = nil
GridUI.tkb_fingers = {}
GridUI.held_keys = {}

-- TABLA DE BRILLOS V0.52
local B_OFF = 0
local B_BG  = 1  
local B_DIM = 2  
local B_SRC = 5  -- Sources Activity (Bajado de 9/10 para no molestar)
local B_IN  = 5  -- Input Activity
local B_VAL_MAX = 7 
local B_HORZ = 8 
local B_HEAD = 9 
local B_TRIG = 10 -- Gate Trigger
local B_VERT = 12 
local B_MAX  = 15 -- Patching / Reverse Look (Solo aqui es maximo)

-- CONSTANTE DE PERSISTENCIA VISUAL (Segundos)
-- Asegura que un trigger se ve al menos durante 3 cuadros de UI (100ms)
local VISUAL_HOLD_TIME = 0.08

function GridUI.init(seq, screen_ui, pb_ref)
  print("GridUI v0.52: Init...")
  EngineRef = seq
  ScreenRef = screen_ui
  PatchbayRef = pb_ref
  
  GridUI.device = grid.connect()
  if GridUI.device then 
    GridUI.connected = true
    GridUI.device.key = GridUI.key_event
  end
  for x=1, 16 do GridUI.cache[x] = {}; for y=1, 8 do GridUI.cache[x][y] = -1 end end
end

-- Update TKB logic (Igual que antes)
local function update_tkb_logic()
  if not EngineRef then return end
  local fingers = {}
  for x=1, 16 do if GridUI.tkb_fingers[x] then table.insert(fingers, x) end end
  table.sort(fingers)
  if GridUI.shift_held then return end
  if #fingers == 0 then EngineRef.jam_active = false; EngineRef.reset_loop_window()
  elseif #fingers == 1 then EngineRef.jam_active = true; EngineRef.jam_step = fingers[1]; EngineRef.reset_loop_window()
  elseif #fingers >= 2 then EngineRef.jam_active = false; EngineRef.set_loop_window(fingers[1], fingers[#fingers]) end
end

function GridUI.key_event(x, y, z)
  local now = util.time()
  if x==1 and y==1 then GridUI.shift_held=(z==1); GridUI.dirty=true; if z==0 then update_tkb_logic() end; return end
  if not EngineRef or not PatchbayRef then return end
  
  -- FILA 1
  if y == 1 then
    if x==2 or x==8 or x==9 then return end
    local is_in=false; for _,id in ipairs(LogicOps.INPUTS) do if x==id then is_in=true end end
    local is_out=false; for _,id in ipairs(LogicOps.OUTPUTS) do if x==id then is_out=true end end
    
    if z == 1 then
      if is_in then
        GridUI.patching_dst = x
        if GridUI.patching_src then
           local s = PatchbayRef.toggle_connection(GridUI.patching_src, x)
           if ScreenRef then ScreenRef.set_patching_view(GridUI.patching_src, x, s) end
           GridUI.dirty = true; return 
        end
        if ScreenRef then ScreenRef.open_context_menu(x, is_in, is_out) end
      elseif is_out then
        if GridUI.shift_held then
           local gens = EngineRef.gens
           if x==LogicOps.BUTTONS.CLOCK_A then EngineRef.clk_a.muted = not EngineRef.clk_a.muted
           elseif x==LogicOps.BUTTONS.CLOCK_B then EngineRef.clk_b.muted = not EngineRef.clk_b.muted 
           elseif x==LogicOps.BUTTONS.CHAOS then gens.chaos.muted = not gens.chaos.muted
           elseif x==LogicOps.BUTTONS.COMPARATOR then gens.comp.muted = not gens.comp.muted
           end
        else 
           GridUI.patching_src = x 
           if ScreenRef then ScreenRef.open_context_menu(x, is_in, is_out) end
        end
      end
    else
      if is_out and GridUI.patching_src==x then GridUI.patching_src=nil; if ScreenRef then ScreenRef.close_context_menu(); ScreenRef.clear_patching_view() end end
      if is_in then GridUI.patching_dst=nil; if not GridUI.patching_src and ScreenRef then ScreenRef.close_context_menu() end end
    end
    GridUI.dirty = true; return
  end
  
  -- FILA 3, 4-7, 8 (Sin cambios logicos, solo brillos en redraw)
  if y == 3 then
    if z == 1 then GridUI.held_keys[x] = now; GridUI.patching_src = LogicOps.STEP_GATE_BASE_ID + x; if ScreenRef then ScreenRef.open_context_menu(GridUI.patching_src, false, true) end
    else
      if (now - (GridUI.held_keys[x] or 0)) < 0.25 then local step = EngineRef.steps[x]; if step then step.gate_active = not step.gate_active end end
      if GridUI.patching_src == (LogicOps.STEP_GATE_BASE_ID + x) then GridUI.patching_src = nil; if ScreenRef then ScreenRef.close_context_menu(); ScreenRef.clear_patching_view() end end
    end
    GridUI.dirty = true; return
  end
  if y >= 4 and y <= 7 then
    local rmap = {[4]="A", [5]="B", [6]="C", [7]="D"}
    if z == 1 then EngineRef.set_focus(x, rmap[y]) else if EngineRef.editor_focus.step_index==x and EngineRef.editor_focus.row_id==rmap[y] then EngineRef.clear_focus() end end
  elseif y == 8 then 
     if GridUI.shift_held then
        if z == 1 then GridUI.held_keys[x] = now
        else
           local duration = now - (GridUI.held_keys[x] or 0)
           if duration > 1.0 then State.clear_snapshot(x); if ScreenRef then ScreenRef.trigger_message("CLEAR SNAP "..x) end
           else if State.session_data.snapshots[x] then State.load_snapshot(x); if ScreenRef then ScreenRef.trigger_message("LOAD SNAP "..x) end
                else State.save_snapshot(x); if ScreenRef then ScreenRef.trigger_message("SAVE SNAP "..x) end end
           end
           GridUI.dirty = true
        end
     else GridUI.tkb_fingers[x] = (z==1); update_tkb_logic() end
  end
  if z==1 then GridUI.dirty = true end
end

-- HELPER: Check visual trigger based on time
local function is_vis_active(last_time, now)
  return (now - last_time) < VISUAL_HOLD_TIME
end

function GridUI.redraw()
  if not GridUI.connected or not GridUI.device or not PatchbayRef then return end
  local dev = GridUI.device; local buffer = {}; local cursor = EngineRef and EngineRef.pos_h or 0
  local visual = EngineRef.visual
  local now = util.time()
  
  for x=1, 16 do
    buffer[x] = {}
    for y=1, 8 do
      local b = 0
      
      -- FILA 1
      if y == 1 then
        if x==1 then b=GridUI.shift_held and B_MAX or B_DIM
        elseif x==2 or x==8 or x==9 then b=0
        else
          local is_out=false; for _,id in ipairs(LogicOps.OUTPUTS) do if x==id then is_out=true end end
          local is_in=false; for _,id in ipairs(LogicOps.INPUTS) do if x==id then is_in=true end end
          
          if is_out and EngineRef then
             local is_trig = false; local muted = false
             
             -- TIME BASED CHECK
             if x==LogicOps.BUTTONS.CLOCK_A then is_trig = is_vis_active(visual.last_trig_a, now); muted = EngineRef.clk_a.muted
             elseif x==LogicOps.BUTTONS.CLOCK_B then is_trig = is_vis_active(visual.last_trig_b, now); muted = EngineRef.clk_b.muted
             elseif x==LogicOps.BUTTONS.CHAOS then is_trig = is_vis_active(visual.last_trig_chaos, now); muted = EngineRef.gens.chaos.muted
             elseif x==LogicOps.BUTTONS.COMPARATOR then is_trig = is_vis_active(visual.last_trig_comp, now); muted = EngineRef.gens.comp.muted
             elseif x==LogicOps.BUTTONS.KEY_PULSE then is_trig = EngineRef.jam_active end -- Key is Gate (Manual)
             
             -- Brillo bajado a B_SRC (5) para actividad normal
             if muted then b = is_trig and 4 or 1 else b = is_trig and B_SRC or B_DIM end
             
             if GridUI.patching_src == x then b=B_MAX end
             if GridUI.patching_dst and PatchbayRef.is_connected(x, GridUI.patching_dst) then b=B_MAX end
             
          elseif is_in then
             local active = PatchbayRef.get_input_active(x)
             b = active and B_IN or B_DIM
             if GridUI.patching_src then if PatchbayRef.is_connected(GridUI.patching_src, x) then b=B_MAX else b=6 end end
             if GridUI.patching_dst == x then b=B_MAX end
          end
        end
        
      -- FILA 2
      elseif y == 2 then if x==cursor then b=B_HEAD else b=0 end
      
      -- FILA 3
      elseif y == 3 then
         local s = EngineRef and EngineRef.steps[x]
         if s then
            if s.gate_active then b = math.floor((s.gate_len/100)*4) + 3 else b=B_BG end -- Rango 3-7
            if x==cursor and visual.step_prob_result then b = B_TRIG end
            if GridUI.patching_src==(LogicOps.STEP_GATE_BASE_ID+x) then b=B_MAX end
            if GridUI.patching_dst and PatchbayRef.is_connected(LogicOps.STEP_GATE_BASE_ID + x, GridUI.patching_dst) then b=B_MAX end
         end
         
      -- FILAS 4-7
      elseif y>=4 and y<=7 then
         local s=EngineRef and EngineRef.steps[x]
         if s then 
            local v=0; if y==4 then v=s.vals.A elseif y==5 then v=s.vals.B elseif y==6 then v=s.vals.C else v=s.vals.D end
            b = math.floor((v/127)*5) + 2
            
            if x==cursor then
               if is_vis_active(visual.last_trig_vertical, now) then
                  local active_row = EngineRef.pos_v + 3 
                  if y == active_row then b = B_VERT end
               else
                  b = B_HORZ
               end
            end
            if EngineRef.editor_focus.active and EngineRef.editor_focus.step_index==x then b=B_MAX end 
         end
      
      -- FILA 8
      elseif y==8 then
         if GridUI.shift_held then if State.session_data.snapshots[x] then b=10 else b=2 end
         else if GridUI.tkb_fingers[x] then b=B_MAX else b=1 end end
      end
      buffer[x][y] = b
    end
  end
  -- Diffing
  for x=1,16 do for y=1,8 do if GridUI.cache[x][y] ~= buffer[x][y] then dev:led(x,y,buffer[x][y]); GridUI.cache[x][y]=buffer[x][y] end end end
  dev:refresh()
  
  -- Truco de optimización: Si no estamos editando ni pacheando, dirty depende solo de reloj
  -- Pero como animamos timers, seguimos redibujando a 30fps desde el metro
  GridUI.dirty = false
end

function GridUI.cleanup() if GridUI.device and GridUI.connected then GridUI.device:all(0); GridUI.device:refresh() end end
return GridUI