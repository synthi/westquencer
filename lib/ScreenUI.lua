-- lib/ScreenUI.lua
-- v0.62 (OVERLAYS, HEADER & FULL LIST)

local ScreenUI = {}
local LogicOps = include('lib/LogicOps')
local Clock = include('lib/Clock')
local musicutil = require 'musicutil'
local EngineRef = nil
local PatchbayRef = nil

ScreenUI.dirty = true
ScreenUI.page = 1 
ScreenUI.settings_sel = 1
ScreenUI.settings_page = 1 

-- LISTA COMPLETA
ScreenUI.settings_list = {
  {id="voice_abcd", name="VOICE ABCD"},
  {id="voice_a", name="VOICE A"},
  {id="voice_b", name="VOICE B"},
  {id="voice_c", name="VOICE C"},
  {id="voice_d", name="VOICE D"},
  {id="root_note", name="ROOT NOTE"},
  {id="scale_mode", name="SCALE TYPE"},
  {id="pitch_range", name="PITCH RANGE"},
  {id="base_octave", name="BASE OCTAVE"},
  {id="tkb_quant", name="TKB QUANT"},
  {id="rnd_strength", name="RND STRENGTH"},
  {id="rnd_density", name="RND DENSITY"},
  {id="rnd_scope", name="RND SCOPE"},
  {id="global_prob", name="GLOBAL PROB"}
}

ScreenUI.popup = { active=false, name="", value="", deadline=0 }
ScreenUI.context = { active=false, id=nil, is_input=false, is_output=false }
ScreenUI.patching_view = { active=false, src=nil, dst=nil, connected=false }

function ScreenUI.init(seq, pb_ref) EngineRef = seq; PatchbayRef = pb_ref end
local function is_vis_active(last_time) return (util.time() - last_time) < 0.1 end

-- UTILS
function ScreenUI.set_patching_view(src, dst, is_conn) ScreenUI.patching_view.active=true; ScreenUI.patching_view.src=src; ScreenUI.patching_view.dst=dst; ScreenUI.patching_view.connected=is_conn; ScreenUI.dirty=true end
function ScreenUI.clear_patching_view() ScreenUI.patching_view.active=false; ScreenUI.dirty=true end
function ScreenUI.open_context_menu(id, is_in, is_out) ScreenUI.context.active=true; ScreenUI.context.id=id; ScreenUI.context.is_input=is_in; ScreenUI.context.is_output=is_out; ScreenUI.dirty=true end
function ScreenUI.close_context_menu() ScreenUI.context.active=false; ScreenUI.dirty=true end
function ScreenUI.trigger_message(msg) ScreenUI.popup.name=msg; ScreenUI.popup.value=""; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.0; ScreenUI.dirty=true end
function ScreenUI.handle_key(n, z) if z==1 then ScreenUI.popup.name="KEY "..n; ScreenUI.popup.value="PRESS"; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.5 end end

function ScreenUI.next_settings_page()
  local items_per_page = 4
  local total_pages = math.ceil(#ScreenUI.settings_list / items_per_page)
  ScreenUI.settings_page = ScreenUI.settings_page + 1
  if ScreenUI.settings_page > total_pages then ScreenUI.settings_page = 1 end
  ScreenUI.settings_sel = ((ScreenUI.settings_page - 1) * items_per_page) + 1
  ScreenUI.dirty = true
end

-- DRAWING FUNCTIONS (Scope, Context... same as before, abbreviated here)
function ScreenUI.draw_mini_scope(history, x, y, w, h)
  if not history then return end
  screen.level(2); screen.rect(x, y, w, h); screen.stroke(); screen.level(15)
  local samples_per_pixel = math.floor(#history / w); if samples_per_pixel < 1 then samples_per_pixel = 1 end
  local start_px = x + w
  for i=0, w-1 do
     local base_idx = #history - (i * samples_per_pixel); if base_idx < 1 then break end
     local has_trig = false
     for j=0, samples_per_pixel-1 do if history[base_idx - j] == 1 then has_trig = true; break end end
     if has_trig then local px = start_px - i; screen.move(px, y + h - 2); screen.line(px, y + 2) end
  end
  screen.stroke()
end

function ScreenUI.draw_context_menu()
  local id = ScreenUI.context.id; local gens = EngineRef.gens
  screen.level(0); screen.rect(6, 10, 116, 48); screen.fill(); screen.level(15); screen.rect(6, 10, 116, 48); screen.stroke()
  screen.move(10, 22); screen.font_size(8)
  local title = LogicOps.NAMES[id] or ("MODULE " .. id); if id >= 100 then title = "STEP " .. (id-100) .. " GATE" end
  screen.text(title)
  if ScreenUI.context.is_input and PatchbayRef then
     screen.move(10, 32); screen.font_size(8); screen.level(10); screen.text("CONNECTED:")
     local conns = PatchbayRef.connections[id]; if conns and #conns > 0 then local y_list = 42; for k, src_id in ipairs(conns) do if k > 3 then screen.move(10, y_list); screen.text("..."); break end; local name = LogicOps.NAMES[src_id] or ("SRC "..src_id); if src_id >= 100 then name = "STEP "..(src_id-100) end; screen.move(10, y_list); screen.text("- "..name); y_list = y_list + 8 end else screen.move(10, 42); screen.level(4); screen.text("(None)") end
     PatchbayRef.init_history(id); local sc_h = (id == LogicOps.BUTTONS.RND_JUMP) and 30 or 38; ScreenUI.draw_mini_scope(PatchbayRef.input_history[id], 80, 15, 38, sc_h)
     if id == LogicOps.BUTTONS.RND_JUMP then local j = gens.jump; screen.move(10, 56); screen.level(15); local tgt_txt = (j.target == 0) and "RND" or j.target; screen.text("E2: TGT " .. tgt_txt .. "  E3: PROB " .. j.prob .. "%") end
     return 
  end
  local history = nil
  if id==LogicOps.BUTTONS.CLOCK_A then history=EngineRef.gens.clk_a_hist.data elseif id==LogicOps.BUTTONS.CLOCK_B then history=EngineRef.gens.clk_b_hist.data elseif id==LogicOps.BUTTONS.CHAOS then history=gens.chaos.history elseif id==LogicOps.BUTTONS.COMPARATOR then history=gens.comp.history elseif id==LogicOps.BUTTONS.KEY_PULSE then history=gens.key.history end
  if history then ScreenUI.draw_mini_scope(history, 80, 15, 38, 38) end
  screen.move(10, 35)
  if id == LogicOps.BUTTONS.CLOCK_A or id == LogicOps.BUTTONS.CLOCK_B then local gen = (id==LogicOps.BUTTONS.CLOCK_A and EngineRef.clk_a or EngineRef.clk_b); screen.text("E2: RATE " .. (Clock.NAMES[gen.rate_index] or "?")); screen.move(10, 45); screen.text("E3: SWING " .. gen.swing .. "%"); screen.move(10, 55); screen.text("E1: PW " .. gen.pw .. "%")
  elseif id == LogicOps.BUTTONS.CHAOS then screen.text("E2: PROB " .. gens.chaos.prob .. "%")
  elseif id == LogicOps.BUTTONS.COMPARATOR then local r={"A","B","C","D"}; screen.text("E1: THR " .. gens.comp.thresh); screen.move(10, 45); screen.text("E2: A [" .. r[gens.comp.src_a] .. "]"); screen.move(70, 45); screen.text("E3: B [" .. r[gens.comp.src_b] .. "]")
  elseif id == LogicOps.BUTTONS.KEY_PULSE then screen.text("TOUCH KEYBOARD") 
  elseif id >= 100 then local s = EngineRef.steps[id-100]; screen.text("E1: TIE " .. (s.gate_tie and "ON" or "OFF")); screen.move(10, 45); screen.text("E2: PROB " .. s.gate_prob .. "%"); screen.move(10, 55); screen.text("E3: LEN " .. s.gate_len .. "%") end
end

function ScreenUI.draw_settings_page()
  screen.level(15); screen.font_size(8); screen.move(0, 10); screen.text("SETTINGS (K2)")
  local items_per_page = 4
  local start_idx = ((ScreenUI.settings_page - 1) * items_per_page) + 1
  local end_idx = start_idx + items_per_page - 1
  local total_pages = math.ceil(#ScreenUI.settings_list / items_per_page)
  screen.move(80, 10); screen.text_right(ScreenUI.settings_page .. "/" .. total_pages)
  screen.move(128, 10); screen.text_right("NEXT (K3)")
  local y = 25
  for i = start_idx, end_idx do
     local item = ScreenUI.settings_list[i]
     if not item then break end
     screen.move(10, y)
     if i == ScreenUI.settings_sel then screen.text("> ") else screen.text("  ") end
     local val = params:get(item.id)
     if item.id == "rnd_scope" then val = ({"VALS", "PATCH", "BOTH"})[val] end
     if item.id == "scale_mode" or item.id == "root_note" then val = params:string(item.id) end
     if item.id == "pitch_range" then val = params:string(item.id) end
     if item.id == "tkb_quant" then val = params:string(item.id) end
     if string.find(item.id, "voice_") then val = params:string(item.id) end
     screen.text(item.name .. ": " .. val)
     y = y + 10
  end
end

-- MAIN HEADER UPDATE (PERFORMANCE INFO)
function ScreenUI.draw_scope()
  screen.level(15); screen.move(0, 8); screen.font_size(8)
  if EngineRef then
     local r_note = params:string("root_note")
     local r_a = Clock.NAMES[EngineRef.clk_a.rate_index] or "?"
     local r_b = Clock.NAMES[EngineRef.clk_b.rate_index] or "?"
     screen.text("ROOT:"..r_note.."  A:"..r_a.."  B:"..r_b)
  end
  -- Drawing grid lines...
  if not EngineRef then return end
  local x_pos = (EngineRef.pos_h - 1) * 8
  screen.move(x_pos + 4, 62); screen.text_center("^")
  screen.level(3); local y_base = 20; local labels = {"A", "B", "C", "D"}
  for i=1, 4 do
    screen.move(0, y_base); screen.text(labels[i])
    for s=1, 16 do
      local step = EngineRef.steps[s]
      if step then
        local val = 0; if i==1 then val = step.vals.A elseif i==2 then val = step.vals.B elseif i==3 then val = step.vals.C elseif i==4 then val = step.vals.D end
        local h = math.floor((val/127)*6); screen.move(10 + (s*7), y_base); screen.line(10 + (s*7), y_base - h); screen.stroke()
      end
    end
    y_base = y_base + 12
  end
end

function ScreenUI.draw_view()
  -- LOGICA DE CAPAS (LAYERS)
  -- 1. Fondo (Page 1 or 2)
  if ScreenUI.page == 2 then ScreenUI.draw_settings_page()
  else ScreenUI.draw_scope() end
  
  -- 2. Overlays (Context / Patching) - SIEMPRE ENCIMA
  if ScreenUI.patching_view.active then ScreenUI.draw_patching_window()
  elseif EngineRef and EngineRef.selection.active then ScreenUI.draw_editor_overlay()
  elseif ScreenUI.context.active then ScreenUI.draw_context_menu()
  elseif ScreenUI.popup.active then ScreenUI.draw_popup_overlay() end
  
  -- 3. Indicators (Always visible)
  if EngineRef then
    local vis = EngineRef.visual
    if is_vis_active(vis.last_trig_a) then screen.level(15) else screen.level(2) end
    screen.rect(118, 2, 3, 3); screen.fill() 
    if is_vis_active(vis.last_trig_b) then screen.level(15) else screen.level(2) end
    screen.rect(123, 2, 3, 3); screen.fill() 
  end
end

function ScreenUI.draw_editor_overlay() 
  if not EngineRef.selection.active then return end
  local steps_txt = ""; local count = 0; local last_val = 0
  local indices = {}; for idx, _ in pairs(EngineRef.selection.steps) do table.insert(indices, idx) end; table.sort(indices)
  for _, idx in ipairs(indices) do if count < 5 then steps_txt = steps_txt .. idx .. ", " end; count = count + 1; last_val = EngineRef.steps[idx].vals[EngineRef.selection.row_id] end
  if count > 5 then steps_txt = steps_txt .. "..." else steps_txt = string.sub(steps_txt, 1, -3) end
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15); screen.rect(0,0,128,64); screen.stroke(); screen.move(64, 15); screen.font_size(8); screen.text_center("EDITING STEPS: " .. steps_txt); screen.move(10, 40); screen.font_size(16); screen.text("ROW " .. EngineRef.selection.row_id); screen.move(118, 40); screen.text_right(tostring(last_val)); screen.level(4); screen.rect(10, 50, 108, 6); screen.stroke(); screen.level(15); local bar_w = math.floor((last_val / 127) * 108); screen.rect(10, 50, bar_w, 6); screen.fill() 
end
function ScreenUI.draw_popup_overlay() if util.time() > ScreenUI.popup.deadline then ScreenUI.popup.active = false; ScreenUI.dirty = true; return end; screen.level(0); screen.rect(4, 16, 120, 36); screen.fill(); screen.level(15); screen.rect(4, 16, 120, 36); screen.stroke(); screen.move(64, 36); screen.font_size(16); screen.text_center(ScreenUI.popup.name); screen.font_size(8); screen.move(64, 46); screen.text_center(tostring(ScreenUI.popup.value)) end
return ScreenUI