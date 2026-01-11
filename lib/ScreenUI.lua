-- lib/ScreenUI.lua
-- v0.52 (NEW OSCILLOSCOPE & VISUALS)

local ScreenUI = {}
local LogicOps = include('lib/LogicOps')
local Clock = include('lib/Clock')
local EngineRef = nil
local PatchbayRef = nil

ScreenUI.dirty = true
ScreenUI.mode = "SCOPE" 
ScreenUI.popup = { active=false, name="", value="", deadline=0 }
ScreenUI.context = { active=false, id=nil, is_input=false, is_output=false }
ScreenUI.patching_view = { active=false, src=nil, dst=nil, connected=false }

function ScreenUI.init(seq, pb_ref) EngineRef = seq; PatchbayRef = pb_ref end

-- HELPERS TIME
local function is_vis_active(last_time) return (util.time() - last_time) < 0.1 end

-- PATCHING & CONTEXT (Igual que v0.50)
function ScreenUI.set_patching_view(src, dst, is_conn) ScreenUI.patching_view.active=true; ScreenUI.patching_view.src=src; ScreenUI.patching_view.dst=dst; ScreenUI.patching_view.connected=is_conn; ScreenUI.dirty=true end
function ScreenUI.clear_patching_view() ScreenUI.patching_view.active=false; ScreenUI.dirty=true end
function ScreenUI.open_context_menu(id, is_in, is_out) ScreenUI.context.active=true; ScreenUI.context.id=id; ScreenUI.context.is_input=is_in; ScreenUI.context.is_output=is_out; ScreenUI.dirty=true end
function ScreenUI.close_context_menu() ScreenUI.context.active=false; ScreenUI.dirty=true end
function ScreenUI.trigger_message(msg) ScreenUI.popup.name=msg; ScreenUI.popup.value=""; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.0; ScreenUI.dirty=true end
function ScreenUI.handle_enc(n, d) ScreenUI.popup.name="ENC "..n; ScreenUI.popup.value=d; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.5 end
function ScreenUI.handle_key(n, z) if z==1 then ScreenUI.popup.name="KEY "..n; ScreenUI.popup.value="PRESS"; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.5 end end

-- OSCILLOSCOPE V2: SMOOTH DRAWING
function ScreenUI.draw_mini_scope(history, x, y, w, h)
  if not history then return end
  screen.level(2); screen.rect(x, y, w, h); screen.stroke() -- Frame
  screen.level(15)
  
  -- Dibujamos de derecha a izquierda
  local step = w / 64
  local prev_val = history[#history] or 0
  local start_px = x + w
  
  screen.move(start_px, y + h - (prev_val * (h-2)) - 1)
  
  for i=0, 63 do
     local val = history[#history - i] or 0
     local px = start_px - (i * step)
     local py = y + h - (val * (h-4)) - 2 -- Escalar 0/1 a altura
     screen.line(px, py)
  end
  screen.stroke()
end

function ScreenUI.draw_context_menu()
  local id = ScreenUI.context.id
  local gens = EngineRef.gens
  
  screen.level(0); screen.rect(6, 10, 116, 48); screen.fill()
  screen.level(15); screen.rect(6, 10, 116, 48); screen.stroke()
  
  screen.move(10, 22); screen.font_size(8)
  local title = LogicOps.NAMES[id] or ("MODULE " .. id)
  if id >= 100 then title = "STEP " .. (id-100) .. " GATE" end
  screen.text(title)
  
  -- History Selection
  local history = nil
  if id==LogicOps.BUTTONS.CLOCK_A then history=EngineRef.clk_a.history
  elseif id==LogicOps.BUTTONS.CLOCK_B then history=EngineRef.clk_b.history
  elseif id==LogicOps.BUTTONS.CHAOS then history=gens.chaos.history
  elseif id==LogicOps.BUTTONS.COMPARATOR then history=gens.comp.history
  elseif ScreenUI.context.is_input and PatchbayRef then history=PatchbayRef.input_history[id]
  end
  
  if history then ScreenUI.draw_mini_scope(history, 80, 15, 38, 38) end

  screen.move(10, 35)
  if id == LogicOps.BUTTONS.CLOCK_A or id == LogicOps.BUTTONS.CLOCK_B then 
    local gen = (id==LogicOps.BUTTONS.CLOCK_A and EngineRef.clk_a or EngineRef.clk_b)
    screen.text("E2: RATE " .. (Clock.NAMES[gen.rate_index] or "?"))
    screen.move(10, 45); screen.text("E3: SWING " .. gen.swing .. "%")
    screen.move(10, 55); screen.text("E1: PW " .. gen.pw .. "%")
  elseif id == LogicOps.BUTTONS.CHAOS then screen.text("E2: PROB " .. gens.chaos.prob .. "%")
  elseif id == LogicOps.BUTTONS.COMPARATOR then
    local r={"A","B","C","D"}
    screen.text("E1: THR " .. gens.comp.thresh)
    screen.move(10, 45); screen.text("E2: A [" .. r[gens.comp.src_a] .. "]")
    screen.move(70, 45); screen.text("E3: B [" .. r[gens.comp.src_b] .. "]")
  elseif id >= 100 then
    local s = EngineRef.steps[id-100]
    screen.text("E2: PROB " .. s.gate_prob .. "%")
    screen.move(10, 45); screen.text("E3: LEN " .. s.gate_len .. "%")
  elseif id == LogicOps.BUTTONS.KEY_PULSE then screen.text("KEY ACTIVITY") end
end

function ScreenUI.draw_view()
  if ScreenUI.patching_view.active then ScreenUI.draw_patching_window()
  elseif EngineRef and EngineRef.editor_focus.active then ScreenUI.draw_editor_overlay()
  elseif ScreenUI.context.active then ScreenUI.draw_context_menu()
  else ScreenUI.draw_scope(); if ScreenUI.popup.active then ScreenUI.draw_popup_overlay() end end
  
  -- INDICADORES SUPERIORES (Cuadraditos)
  -- Usamos is_vis_active para que parpadeen a 30fps sin perderse
  if EngineRef then
    local vis = EngineRef.visual
    -- Clock A
    if is_vis_active(vis.last_trig_a) then screen.level(15) else screen.level(2) end
    screen.rect(118, 2, 3, 3); screen.fill() 
    -- Clock B
    if is_vis_active(vis.last_trig_b) then screen.level(15) else screen.level(2) end
    screen.rect(123, 2, 3, 3); screen.fill() 
  end
end

function ScreenUI.draw_patching_window()
  screen.level(0); screen.rect(0, 0, 128, 64); screen.fill()
  screen.level(15); screen.rect(2, 2, 124, 60); screen.stroke()
  local src = ScreenUI.patching_view.src; local dst = ScreenUI.patching_view.dst
  local src_name = (LogicOps.NAMES[src] or ("SRC "..src)); if src >= 100 then src_name = "STEP "..(src-100) end
  local dst_name = (LogicOps.NAMES[dst] or ("DST "..dst))
  screen.font_size(8); screen.move(64, 20); screen.text_center(src_name); screen.move(64, 30); screen.text_center("v")
  screen.move(64, 40); screen.text_center(dst_name); screen.font_size(16); screen.move(64, 58)
  if ScreenUI.patching_view.connected then screen.level(15); screen.text_center("CONNECTED") else screen.level(2); screen.text_center("DISCONNECTED") end
end

function ScreenUI.draw_scope()
  screen.level(15); screen.move(0, 8); screen.font_size(8); screen.text("WESTQUENCER v0.52")
  if not EngineRef then return end
  local x_pos = (EngineRef.pos_h - 1) * 8
  screen.move(x_pos + 4, 62); screen.text_center("^")
  screen.level(3); local y_base = 20; local labels = {"A", "B", "C", "D"}
  for i=1, 4 do
    screen.move(0, y_base); screen.text(labels[i])
    for s=1, 16 do
      local step = EngineRef.steps[s]
      if step then
        local val = 0
        if i==1 then val = step.vals.A elseif i==2 then val = step.vals.B elseif i==3 then val = step.vals.C elseif i==4 then val = step.vals.D end
        local h = math.floor((val/127)*6); screen.move(10 + (s*7), y_base); screen.line(10 + (s*7), y_base - h); screen.stroke()
      end
    end
    y_base = y_base + 12
  end
end
function ScreenUI.draw_editor_overlay() 
  local focus = EngineRef.editor_focus; local step = EngineRef.steps[focus.step_index]
  if not step then return end
  local val = step.vals[focus.row_id]
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15); screen.rect(0,0,128,64); screen.stroke()
  screen.move(64, 15); screen.font_size(8); screen.text_center("EDITING STEP " .. focus.step_index)
  screen.move(10, 40); screen.font_size(16); screen.text("ROW " .. focus.row_id)
  screen.move(118, 40); screen.text_right(tostring(val))
  screen.level(4); screen.rect(10, 50, 108, 6); screen.stroke()
  screen.level(15); local bar_w = math.floor((val / 127) * 108); screen.rect(10, 50, bar_w, 6); screen.fill()
end
function ScreenUI.draw_popup_overlay()
  if util.time() > ScreenUI.popup.deadline then ScreenUI.popup.active = false; ScreenUI.dirty = true; return end
  screen.level(0); screen.rect(4, 16, 120, 36); screen.fill(); screen.level(15); screen.rect(4, 16, 120, 36); screen.stroke()
  screen.move(64, 36); screen.font_size(16); screen.text_center(ScreenUI.popup.name)
  screen.font_size(8); screen.move(64, 46); screen.text_center(tostring(ScreenUI.popup.value))
end
return ScreenUI