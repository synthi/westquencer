-- lib/LogicOps.lua
-- v0.58

local LogicOps = {}

LogicOps.BUTTONS = {
  SHIFT = 1,
  RND_GLOBAL = 2, -- Nuevo ID
  
  CLOCK_A = 3,
  CLOCK_B = 4,
  CHAOS = 5,
  COMPARATOR = 6,
  KEY_PULSE = 7,
  
  CLOCK_H = 10,
  RESET_H = 11,
  DIR_H   = 12,
  HOLD_H  = 13,
  RND_JUMP= 14,
  CLOCK_V = 15,
  RESET_V = 16
}

LogicOps.INPUTS = {10, 11, 12, 13, 14, 15, 16}
LogicOps.OUTPUTS = {3, 4, 5, 6, 7}
LogicOps.STEP_GATE_BASE_ID = 100

LogicOps.NAMES = {
  [2] = "RND GLOBAL",
  [3] = "CLOCK A",
  [4] = "CLOCK B",
  [5] = "CHAOS", 
  [6] = "COMPARATOR",
  [7] = "KEY PULSE",
  [10] = "CLOCK H",
  [11] = "RESET H",
  [12] = "DIR H",
  [13] = "HOLD H",
  [14] = "JUMP",
  [15] = "CLOCK V",
  [16] = "RESET V"
}

return LogicOps