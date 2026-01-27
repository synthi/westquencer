-- lib/GridUI.lua
-- v0.59.2 (ANCHOR SELECTION & RND FIX)

local GridUI = {}
local LogicOps = include('lib/LogicOps')
-- State inyectado

local EngineRef = nil 
local ScreenRef = nil
local PatchbayRef = nil
local StateRef = nil

GridUI.device = nil
GridUI.connected = false
GridUI.dirty = true
GridUI.cache = {} 
GridUI.shift_held = false
GridUI.patching_src = nil
GridUI.patching_dst = nil
GridUI.tkb_fingers = {}
GridUI.held_keys = {}

-- CONTADOR DE DEDOS (Para logica de Ancla)
GridUI.fingers_down = 0

-- TABLA DE BRILLOS
local B_MUTE = 1
local B_OFF  = 2
local B_IN   = 5  
local B_SRC  = 8  
local B_HEAD = 9  
local B_TRIG = 12 
local B_VERT = 14 
local B_MAX  = 15 

local VISUAL_HOLD_TIME = 0.08 

function GridUI.init(seq, screen_ui, pb_ref, st_ref)
  print("GridUI v0.59.2: Init...")
  EngineRef = seq
  ScreenRef = screen_ui
  PatchbayRef = pb_ref
  StateRef = st_ref
  GridUI.device = grid.connect()
  if GridUI.device then GridUI.connected = true; GridUI.device.key = GridUI.key_event end
  for x=1, 16 do GridUI.cache[x] = {}; for y=1, 8 do GridUI.cache[x][y] = -1 end end
end

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

-- HELPER ID UNICO
local function get_key_id(x, y) return (y * 16) + x end

function GridUI.key_event(x, y, z)
  local now = util.time()
  local kid = get_key_id(x, y)
  
  -- SHIFT
  if x==1 and y==1 then GridUI.shift_held=(z==1); GridUI.dirty=true; if z==0 then update_tkb_logic() end; return end
  if not EngineRef or not PatchbayRef then return end
  
  -- FILA 1
  if y == 1 then
    -- RND GLOBAL
    if x == LogicOps.BUTTONS.RND_GLOBAL and GridUI.shift_held and z == 1 then
       EngineRef.randomize_global()
       if ScreenRef then ScreenRef.trigger_message("GLOBAL RND") end
       GridUI.dirty = true; return
    end
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
  
  -- FILAS 3-7 (RND + EDIT)
  if y >= 3 and y <= 7 then
     -- A. RND LOGIC (SHIFT)
     if GridUI.shift_held then
        if z == 1 then
           GridUI.held_keys[kid] = now
           if x > 1 then EngineRef.randomize_step_values(x); GridUI.dirty = true end
        else
           if x == 1 then
              local dur = now - (GridUI.held_keys[kid] or 0)
              if dur > 1.0 then
                 local rmap = {[3]="GATE", [4]="A", [5]="B", [6]="C", [7]="D"}
                 EngineRef.randomize_row(rmap[y])
                 if ScreenRef then ScreenRef.trigger_message("RND ROW "..rmap[y]) end
              end
           end
        end
        return
     end
     
     -- B. MULTI-EDIT LOGIC (ANCHOR)
     if y >= 4 and y <= 7 then
        local rmap = {[4]="A", [5]="B", [6]="C", [7]="D"}
        if z == 1 then
           GridUI.fingers_down = GridUI.fingers_down + 1
           -- Toggle logic: Si ya estaba, lo quita. Si no, lo pone.
           if EngineRef.selection.steps[x] then
              EngineRef.remove_selection(x)
           else
              EngineRef.add_selection(x, rmap[y])
           end
        else
           GridUI.fingers_down = GridUI.fingers_down - 1
           if GridUI.fingers_down < 0 then GridUI.fingers_down = 0 end
           
           -- Solo limpiar si soltamos el ultimo dedo
           if GridUI.fingers_down == 0 then
              EngineRef.clear_selection()
           end
        end
        GridUI.dirty = true
        return
     end
     
     -- ROW 3 (GATE)
     if y == 3 then
        if z == 1 then GridUI.held_keys[kid] = now; GridUI.patching_src = LogicOps.STEP_GATE_BASE_ID + x; if ScreenRef then ScreenRef.open_context_menu(GridUI.patching_src, false, true) end
        else
           if (now - (GridUI.held_keys[kid] or 0)) < 0.25 then local step = EngineRef.steps[x]; if step then step.gate_active = not step.gate_active end end
           if GridUI.patching_src == (LogicOps.STEP_GATE_BASE_ID + x) then GridUI.patching_src = nil; if ScreenRef then ScreenRef.close_context_menu(); ScreenRef.clear_patching_view() end end
        end
        GridUI.dirty = true; return
     end
  end
  
  -- FILA 8 (SNAPSHOTS)
  if y == 8 then 
     if GridUI.shift_held then
        if z == 1 then GridUI.held_keys[kid] = now
        else
           local duration = now - (GridUI.held_keys[kid] or 0)
           if duration > 1.0 then 
              if StateRef then StateRef.clear_snapshot(x); if ScreenRef then ScreenRef.trigger_message("CLEAR SNAP "..x) end end
           else 
              if StateRef then
                  if StateRef.session_data.snapshots[x] then StateRef.load_snapshot(x); if ScreenRef then ScreenRef.trigger_message("LOAD SNAP "..x) end
                  else StateRef.save_snapshot(x); if ScreenRef then ScreenRef.trigger_message("SAVE SNAP "..x) end end
              end
           end
           GridUI.dirty = true 
        end
     else GridUI.tkb_fingers[x] = (z==1); update_tkb_logic() end
  end
  if z==1 then GridUI.dirty = true end
end

local function is_vis(last, now, hold) return (now - last) < (hold or VISUAL_HOLD_TIME) end

function GridUI.redraw()
  if not GridUI.connected or not GridUI.device or not PatchbayRef then return end
  if not EngineRef or not EngineRef.visual then return end
  local dev = GridUI.device; local buffer = {}; local cursor = EngineRef.pos_h or 0; local visual = EngineRef.visual; local now = util.time()
  
  for x=1, 16 do
    buffer[x] = {}
    for y=1, 8 do
      local b = 0
      
      if y == 1 then
        if x==1 then b = GridUI.shift_held and B_MAX or B_OFF
        elseif x==2 then b = GridUI.shift_held and B_MAX or B_MUTE
        elseif x==8 or x==9 then b = 0
        else
          local is_out=false; for _,id in ipairs(LogicOps.OUTPUTS) do if x==id then is_out=true end end
          local is_in=false; for _,id in ipairs(LogicOps.INPUTS) do if x==id then is_in=true end end
          if is_out then
             local is_trig = false; local muted = false
             if x==LogicOps.BUTTONS.CLOCK_A then is_trig = is_vis(visual.last_trig_a, now); muted = EngineRef.clk_a.muted
             elseif x==LogicOps.BUTTONS.CLOCK_B then is_trig = is_vis(visual.last_trig_b, now); muted = EngineRef.clk_b.muted
             elseif x==LogicOps.BUTTONS.CHAOS then is_trig = is_vis(visual.last_trig_chaos, now); muted = EngineRef.gens.chaos.muted
             elseif x==LogicOps.BUTTONS.COMPARATOR then is_trig = is_vis(visual.last_trig_comp, now); muted = EngineRef.gens.comp.muted
             elseif x==LogicOps.BUTTONS.KEY_PULSE then is_trig = is_vis(visual.last_trig_key, now) end 
             if muted then b = B_MUTE else b = is_trig and B_TRIG or B_SRC end 
             if GridUI.patching_src == x then b=B_MAX end
             if GridUI.patching_dst and PatchbayRef.is_connected(x, GridUI.patching_dst) then b=B_MAX end
          elseif is_in then
             local active = PatchbayRef.get_input_active(x)
             b = active and B_IN or B_OFF
             if GridUI.patching_src then if PatchbayRef.is_connected(GridUI.patching_src, x) then b=B_MAX else b=6 end end
             if GridUI.patching_dst == x then b=B_MAX end
          end
        end
        
      elseif y == 2 then if x==cursor then b=B_HEAD else b=0 end
      
      elseif y == 3 then
         local s = EngineRef.steps[x]
         if s then
            if s.gate_active then b = math.floor((s.gate_len/100)*4) + 3 else b=B_MUTE end
            if x==cursor and visual.step_prob_result then b = B_TRIG end
            if GridUI.patching_src==(LogicOps.STEP_GATE_BASE_ID+x) then b=B_MAX end
            if GridUI.patching_dst and PatchbayRef.is_connected(LogicOps.STEP_GATE_BASE_ID + x, GridUI.patching_dst) then b=B_MAX end
         end
         
      elseif y>=4 and y<=7 then
         local s=EngineRef.steps[x]
         if s then 
            local v=0; if y==4 then v=s.vals.A elseif y==5 then v=s.vals.B elseif y==6 then v=s.vals.C else v=s.vals.D end
            b = math.floor((v/127)*5) + 2
            if x==cursor then
               local cursor_bright = 8 
               if is_vis(visual.last_trig_vertical, now, 0.15) then
                  local active_row = EngineRef.pos_v + 3 
                  if y == active_row then cursor_bright = B_VERT end
               end
               b = math.max(b, cursor_bright)
            end
            -- SELECCION
            if EngineRef.selection.active and EngineRef.selection.steps[x] then b=B_MAX end 
         end
      
      elseif y==8 then
         if GridUI.shift_held and StateRef then 
            if StateRef.session_data.snapshots[x] then b=10 else b=B_OFF end
         else 
            if GridUI.tkb_fingers[x] then b=B_MAX else b=1 end 
         end
      end
      buffer[x][y] = b or 0
    end
  end
  for x=1,16 do for y=1,8 do if GridUI.cache[x][y] ~= buffer[x][y] then dev:led(x,y,buffer[x][y]); GridUI.cache[x][y]=buffer[x][y] end end end
  dev:refresh(); GridUI.dirty = false
end
function GridUI.cleanup() if GridUI.device and GridUI.connected then GridUI.device:all(0); GridUI.device:refresh() end end
return GridUI
