-- westquencer.lua
-- v0.50 (SINGLE BRAIN ARCHITECTURE)

engine.name = 'None'

local Tables    = include('lib/Tables')
local LogicOps  = include('lib/LogicOps')
local Patchbay  = include('lib/Patchbay') -- Instancia Maestra
local Clock     = include('lib/Clock')
local MidiIO    = include('lib/MidiIO')
local Step      = include('lib/Step')
local Sequencer = include('lib/Sequencer')
local GridUI    = include('lib/GridUI')
local ScreenUI  = include('lib/ScreenUI')
local State     = include('lib/State')

local ui_metro
local FPS = 30

function init()
  print("Westquencer v0.50: System Start...")

  Tables.init()
  init_params()
  MidiIO.init()
  
  -- INYECCIÓN DE DEPENDENCIAS (CEREBRO ÚNICO)
  -- Pasamos la misma instancia de Patchbay a todos
  Sequencer.init(Patchbay)
  ScreenUI.init(Sequencer, Patchbay)
  GridUI.init(Sequencer, ScreenUI, Patchbay)
  State.init() -- State usa Sequencer y Patchbay internamente, revisar si necesita inyección futura
  
  Sequencer.on_step_change = function()
    ScreenUI.dirty = true
    GridUI.dirty = true
  end

  clock.run(Sequencer.clock_coroutine)

  ui_metro = metro.init()
  ui_metro.time = 1 / FPS
  ui_metro.event = function()
    if GridUI.dirty then GridUI.redraw() end
    if ScreenUI.dirty then 
      redraw() 
      ScreenUI.dirty = false 
    end
  end
  ui_metro:start()
  
  print("Westquencer: Ready.")
end

function redraw()
  screen.clear()
  ScreenUI.draw_view()
  screen.update()
end

function init_params()
  params:add_separator("WESTQUENCER")
  for i, row in ipairs({"A", "B", "C", "D"}) do
    params:add_group("ROW "..row.." SETUP", 5)
    params:add_option("row_"..row.."_type", "Type", {"Pitch", "CC", "Velocity", "Clock Mod", "Raw"}, 1)
    params:add_number("row_"..row.."_midi_ch", "MIDI Channel", 1, 16, 1)
    params:add_number("row_"..row.."_cc", "CC Number", 0, 127, 74)
    params:add_number("row_"..row.."_min", "Min Val", 0, 127, 0)
    params:add_number("row_"..row.."_max", "Max Val", 0, 127, 127)
  end
end

function key(n, z)
  if n == 1 then return end 
  ScreenUI.handle_key(n, z)
  ScreenUI.dirty = true
  redraw() 
end

function enc(n, d)
  -- 1. GRID VALUES
  if Sequencer.editor_focus.active then
    if n == 2 or n == 3 then
      Sequencer.modify_focused_value(d)
      ScreenUI.dirty = true
      redraw()
      return
    end
  end
  
  -- 2. CONTEXT MENUS
  if ScreenUI.context.active then
     local id = ScreenUI.context.id
     local gens = Sequencer.gens
     
     if id == LogicOps.BUTTONS.CLOCK_A or id == LogicOps.BUTTONS.CLOCK_B then
        local clk = (id==LogicOps.BUTTONS.CLOCK_A and Sequencer.clk_a or Sequencer.clk_b)
        if n==2 then clk.rate_index = util.clamp(clk.rate_index + d, 1, 31) end
        if n==3 then clk.swing = util.clamp(clk.swing + d, 0, 100) end
        if n==1 then clk.pw = util.clamp(clk.pw + d, 1, 99) end
        
     elseif id >= 100 then -- GATES
        local step = Sequencer.steps[id-100]
        if step then
          if n==2 then step.gate_prob = util.clamp(step.gate_prob + d, 0, 100) end
          if n==3 then step.gate_len  = util.clamp(step.gate_len + d, 1, 100) end
        end
        
     elseif id == LogicOps.BUTTONS.CHAOS then
        if n==2 or n==3 then gens.chaos.prob = util.clamp(gens.chaos.prob + d, 0, 100) end
        
     elseif id == LogicOps.BUTTONS.COMPARATOR then
        if n==1 then gens.comp.thresh = util.clamp(gens.comp.thresh + d, 0, 127) end
        if n==2 then gens.comp.src_a = util.clamp(gens.comp.src_a + d, 1, 4) end
        if n==3 then gens.comp.src_b = util.clamp(gens.comp.src_b + d, 1, 4) end
        
     elseif id == LogicOps.BUTTONS.RND_JUMP then
        if n==1 then gens.jump.target = util.clamp(gens.jump.target + d, 1, 16) end
        if n==2 then gens.jump.prob = util.clamp(gens.jump.prob + d, 0, 100) end
     end
     
     ScreenUI.dirty = true; redraw(); return
  end

  ScreenUI.handle_enc(n, d); ScreenUI.dirty = true; redraw()
end

function cleanup()
  if ui_metro then ui_metro:stop() end
  GridUI.cleanup()
  print("Bye.")
end