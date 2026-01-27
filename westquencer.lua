-- westquencer.lua
-- v0.60.2 (MIDI INJECTION FIX)

engine.name = 'None'

local nb        = require 'nb/lib/nb'
local musicutil = require 'musicutil'

local Tables    = include('lib/Tables')
local LogicOps  = include('lib/LogicOps')
local Patchbay  = include('lib/Patchbay')
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
  print("Westquencer v0.60.2: System Start...")

  Tables.init()
  nb:init() 
  init_params()
  
  MidiIO.init(nb) -- Inicializamos MIDI
  
  -- INYECCION CRITICA: Pasamos MidiIO al Sequencer
  State.init(Sequencer, Patchbay)
  Sequencer.init(Patchbay, MidiIO) 
  
  ScreenUI.init(Sequencer, Patchbay)
  GridUI.init(Sequencer, ScreenUI, Patchbay, State)
  
  params:set("global_prob", 100)
  params:set("rnd_density", 100)
  params:set("rnd_strength", 50)
  
  Sequencer.on_step_change = function()
    ScreenUI.dirty = true
    GridUI.dirty = true
  end

  clock.run(Sequencer.clock_coroutine)

  ui_metro = metro.init()
  ui_metro.time = 1 / FPS
  ui_metro.event = function()
    if Sequencer.running or GridUI.dirty then GridUI.redraw() end
    if Sequencer.running or ScreenUI.dirty then 
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
  
  -- NB VOICES
  params:add_separator("VOICE ROUTING")
  nb:add_param("voice_abcd", "ABCD (Main)") 
  nb:add_param("voice_a", "Row A Voice")
  nb:add_param("voice_b", "Row B Voice")
  nb:add_param("voice_c", "Row C Voice")
  nb:add_param("voice_d", "Row D Voice")

  -- RANDOMIZER
  params:add_group("RANDOMIZER", 4)
  params:add_number("rnd_strength", "RND Strength", 0, 100, 50)
  params:add_number("rnd_density", "RND Density", 0, 100, 100)
  params:add_option("rnd_scope", "RND Scope", {"Values", "Patch", "Both"}, 1)
  params:add_number("global_prob", "Global Prob", 0, 100, 100)

  -- SCALES
  params:add_group("SCALES", 2)
  local scale_names = {}
  for i = 1, #musicutil.SCALES do table.insert(scale_names, musicutil.SCALES[i].name) end
  params:add_option("root_note", "Root Note", musicutil.NOTE_NAMES, 1)
  params:add_option("scale_mode", "Scale Type", scale_names, 5) 

  -- ROW SETUP
  for i, row in ipairs({"A", "B", "C", "D"}) do
    params:add_group("ROW "..row.." SETUP", 4) 
    params:add_option("row_"..row.."_role", "Role", {"Pitch", "Velocity", "CC", "Mod"}, 1)
    params:add_number("row_"..row.."_cc", "CC Number", 0, 127, 74)
    params:add_number("row_"..row.."_min", "Min Val", 0, 127, 0)
    params:add_number("row_"..row.."_max", "Max Val", 0, 127, 127)
  end
  
  params.action_write = function(filename, name, number) State.save_to_disk(number) end
  params.action_read = function(filename, silent, number) State.load_from_disk(number) end
end

function key(n, z)
  if n == 1 then return end 
  if n == 2 and z == 1 then
     if ScreenUI.page == 1 then ScreenUI.page = 2 else ScreenUI.page = 1 end
     ScreenUI.dirty = true; redraw(); return
  end
  if n == 3 and z == 1 then
     if ScreenUI.page == 1 then ScreenUI.page = 2 else ScreenUI.next_settings_page() end
     ScreenUI.dirty = true; redraw(); return
  end
  ScreenUI.handle_key(n, z); redraw() 
end

function enc(n, d)
  if ScreenUI.page == 2 then
     if n == 2 then ScreenUI.settings_sel = util.clamp(ScreenUI.settings_sel + d, 1, #ScreenUI.settings_list)
     elseif n == 3 then
        local item = ScreenUI.settings_list[ScreenUI.settings_sel]
        if item then params:delta(item.id, d) end
     end
     ScreenUI.dirty = true; redraw(); return
  end

  if Sequencer.selection.active then
    if n == 2 or n == 3 then
      Sequencer.modify_focused_value(d)
      redraw()
      return
    end
  end
  
  if ScreenUI.context.active then
     local id = ScreenUI.context.id
     local gens = Sequencer.gens
     if id == LogicOps.BUTTONS.CLOCK_A or id == LogicOps.BUTTONS.CLOCK_B then
        local clk = (id==LogicOps.BUTTONS.CLOCK_A and Sequencer.clk_a or Sequencer.clk_b)
        if n==2 then clk.rate_index = util.clamp(clk.rate_index + d, 1, 31) end
        if n==3 then clk.swing = util.clamp(clk.swing + d, 0, 100) end
        if n==1 then clk.pw = util.clamp(clk.pw + d, 1, 99) end
     elseif id >= 100 then
        local step = Sequencer.steps[id-100]
        if step then
          if n==1 then step.gate_tie = not step.gate_tie end 
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
        if n==2 then gens.jump.target = util.clamp(gens.jump.target + d, 0, 16) end
        if n==3 then gens.jump.prob = util.clamp(gens.jump.prob + d, 0, 100) end
     end
     redraw(); return
  end
  ScreenUI.handle_enc(n, d); redraw()
end

function cleanup()
  if ui_metro then ui_metro:stop() end
  GridUI.cleanup()
  print("Bye.")
end
