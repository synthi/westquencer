-- lib/ScreenUI.lua
-- v0.58 (PAGE SYSTEM & 1PX SCOPE)

local ScreenUI = {}
local LogicOps = include('lib/LogicOps')
local Clock = include('lib/Clock')
local EngineRef = nil
local PatchbayRef = nil

ScreenUI.dirty = true
ScreenUI.page = 1 -- 1=Scope, 2=Settings
ScreenUI.settings_sel = 1
ScreenUI.settings_list = {
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

-- CONTEXT & PATCHING
function ScreenUI.set_patching_view(src, dst, is_conn) ScreenUI.patching_view.active=true; ScreenUI.patching_view.src=src; ScreenUI.patching_view.dst=dst; ScreenUI.patching_view.connected=is_conn; ScreenUI.dirty=true end
function ScreenUI.clear_patching_view() ScreenUI.patching_view.active=false; ScreenUI.dirty=true end
function ScreenUI.open_context_menu(id, is_in, is_out) ScreenUI.context.active=true; ScreenUI.context.id=id; ScreenUI.context.is_input=is_in; ScreenUI.context.is_output=is_out; ScreenUI.dirty=true end
function ScreenUI.close_context_menu() ScreenUI.context.active=false; ScreenUI.dirty=true end
function ScreenUI.trigger_message(msg) ScreenUI.popup.name=msg; ScreenUI.popup.value=""; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.0; ScreenUI.dirty=true end
function ScreenUI.handle_enc(n, d) ScreenUI.popup.name="ENC "..n; ScreenUI.popup.value=d; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.5 end
function ScreenUI.handle_key(n, z) if z==1 then ScreenUI.popup.name="KEY "..n; ScreenUI.popup.value="PRESS"; ScreenUI.popup.active=true; ScreenUI.popup.deadline=util.time()+1.5 end end

-- OSCILLOSCOPE V7: 1PX CLEAN LINES (300 samples)
function ScreenUI.draw_mini_scope(history, x, y, w, h)
  if not history then return end
  screen.level(2); screen.rect(x, y, w, h); screen.stroke(); screen.level(15)
  
  -- Buffer 300. Width 40. Ratio ~7.5
  local samples_per_pixel = math.floor(#history / w)
  if samples_per_pixel < 1 then samples_per_pixel = 1 end
  local start_px = x + w
  
  for i=0, w-1 do
     local base_idx = #history - (i * samples_per_pixel)
     if base_idx < 1 then break end
     
     -- Detectar si hay Trigger (1) en el bloque
     local has_trig = false
     for j=0, samples_per_pixel-1 do
        if history[base_idx - j] == 1 then has_trig = true; break end
     end
     
     if has_trig then
        local px = start_px - i
        -- Linea vertical completa de altura variable o fija?
        -- Trigger es binario, asi que linea completa
        screen.move(px, y + h - 2)
        screen.line(px, y + 2)
     end
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
  
  if ScreenUI.context.is_input and PatchbayRef then
     screen.move(10, 32); screen.font_size(8); screen.level(10); screen.text("CONNECTED:")
     local conns = PatchbayRef.connections[id]
     if conns and #conns > 0 then
        local y_list = 42
        for k, src_id in ipairs(conns) do
           if k > 3 then screen.move(10, y_list); screen.text("..."); break end 
           local name = LogicOps.NAMES[src_id] or ("SRC "..src_id)
           if src_id >= 100 then name = "STEP "..(src_id-100) end
           screen.move(10, y_list); screen.text("- "..name); y_list = y_list + 8
        end
     else screen.move(10, 42); screen.level(4); screen.text("(None)") end
     PatchbayRef.init_history(id); local sc_h = (id == LogicOps.BUTTONS.RND_JUMP) and 30 or 38
     ScreenUI.draw_mini_scope(PatchbayRef.input_history[id], 80, 15, 38, sc_h)
     if id == LogicOps.BUTTONS.RND_JUMP then
        local j = gens.jump; screen.move(10, 56); screen.level(15)
        local tgt_txt = (j.target == 0) and "RND" or j.target
        screen.text("E2: TGT " .. tgt_txt .. "  E3: PROB " .. j.prob .. "%")
     end
     return 
  end

  local history = nil
  if id==LogicOps.BUTTONS.CLOCK_A then history=EngineRef.gens.clk_a_hist.data
  elseif id==LogicOps.BUTTONS.CLOCK_B then history=EngineRef.gens.clk_b_hist.data
  elseif id==LogicOps.BUTTONS.CHAOS then history=gens.chaos.history
  elseif id==LogicOps.BUTTONS.COMPARATOR then history=gens.comp.history
  elseif id==LogicOps.BUTTONS.KEY_PULSE then history=gens.key.history
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
  elseif id == LogicOps.BUTTONS.KEY_PULSE then screen.text("TOUCH KEYBOARD") end
end

function ScreenUI.draw_settings_page()
  screen.level(15); screen.font_size(8); screen.move(0, 10); screen.text("SETTINGS (K2)")
  local y = 25
  for i, item in ipairs(ScreenUI.settings_list) do
     screen.move(10, y)
     if i == ScreenUI.settings_sel then screen.text("> ") else screen.text("  ") end
     
     -- Get val
     local val = params:get(item.id)
     if item.id == "rnd_scope" then
        local opts = {"VALS", "PATCH", "BOTH"}
        val = opts[val]
     end
     screen.text(item.name .. ": " .. val)
     y = y + 10
  end
end

function ScreenUI.draw_view()
  if ScreenUI.page == 2 then
     ScreenUI.draw_settings_page()
     return
  end

  if ScreenUI.patching_view.active then ScreenUI.draw_patching_window()
  elseif EngineRef and EngineRef.editor_focus.active then ScreenUI.draw_editor_overlay()
  elseif ScreenUI.context.active then ScreenUI.draw_context_menu()
  else ScreenUI.draw_scope(); if ScreenUI.popup.active then ScreenUI.draw_popup_overlay() end end
  
  if EngineRef then
    local vis = EngineRef.visual
    if is_vis_active(vis.last_trig_a) then screen.level(15) else screen.level(2) end
    screen.rect(118, 2, 3, 3); screen.fill() 
    if is_vis_active(vis.last_trig_b) then screen.level(15) else screen.level(2) end
    screen.rect(123, 2, 3, 3); screen.fill() 
  end
end

function ScreenUI.draw_patching_window()
  screen.level(0); screen.rect(0, 0, 128, 64); screen.fill(); screen.level(15); screen.rect(2, 2, 124, 60); screen.stroke()
  local src = ScreenUI.patching_view.src; local dst = ScreenUI.patching_view.dst
  local src_name = (LogicOps.NAMES[src] or ("SRC "..src)); if src >= 100 then src_name = "STEP "..(src-100) end
  local dst_name = (LogicOps.NAMES[dst] or ("DST "..dst))
  screen.font_size(8); screen.move(64, 20); screen.text_center(src_name); screen.move(64, 30); screen.text_center("v")
  screen.move(64, 40); screen.text_center(dst_name); screen.font_size(16); screen.move(64, 58)
  if ScreenUI.patching_view.connected then screen.level(15); screen.text_center("CONNECTED") else screen.level(2); screen.text_center("DISCONNECTED") end
end
function ScreenUI.draw_scope()
  screen.level(15); screen.move(0, 8); screen.font_size(8); screen.text("WESTQUENCER v0.58")
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
function ScreenUI.draw_editor_overlay() local focus = EngineRef.editor_focus; local step = EngineRef.steps[focus.step_index]; if not step then return end; local val = step.vals[focus.row_id]; screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15); screen.rect(0,0,128,64); screen.stroke(); screen.move(64, 15); screen.font_size(8); screen.text_center("EDITING STEP " .. focus.step_index); screen.move(10, 40); screen.font_size(16); screen.text("ROW " .. focus.row_id); screen.move(118, 40); screen.text_right(tostring(val)); screen.level(4); screen.rect(10, 50, 108, 6); screen.stroke(); screen.level(15); local bar_w = math.floor((val / 127) * 108); screen.rect(10, 50, bar_w, 6); screen.fill() end
function ScreenUI.draw_popup_overlay() if util.time() > ScreenUI.popup.deadline then ScreenUI.popup.active = false; ScreenUI.dirty = true; return end; screen.level(0); screen.rect(4, 16, 120, 36); screen.fill(); screen.level(15); screen.rect(4, 16, 120, 36); screen.stroke(); screen.move(64, 36); screen.font_size(16); screen.text_center(ScreenUI.popup.name); screen.font_size(8); screen.move(64, 46); screen.text_center(tostring(ScreenUI.popup.value)) end
return ScreenUI