local nf = {}

local util = require("util")

nf.epsilon = {type = "epsilon"} -- Special value for epsilon transition

local nameCounter = 0
local function genName()
  nameCounter = nameCounter + 1
  return "s" .. nameCounter
end

local function emptyMachine(noAccept)
  local sName = genName()
  local machine = {
    states = {
      [sName] = {edges = {}}
    },
    startState = sName,
    acceptStates = {[sName] = true}
  }

  if noAccept then
    machine.acceptStates = {}
  end

  return machine
end

local function addEnter(state, value)
  state.enter = state.enter or {}
  state.enter[#state.enter + 1] = value
end

function nf.concatMachines(first, second)
  local newMachine = util.deepClone(first)

  for k, v in pairs(second.states) do
    newMachine.states[k] = v
  end

  for k in pairs(first.acceptStates) do
    local xs = newMachine.states[k].edges
    xs[#xs + 1] = {condition = nf.epsilon, dest = second.startState}
  end

  newMachine.acceptStates = {}
  for k, v in pairs(second.acceptStates) do
    newMachine.acceptStates[k] = v
  end

  return newMachine
end

function nf.unionMachines(first, second)
  local newMachine = util.deepClone(first)

  for k, v in pairs(second.states) do
    newMachine.states[k] = v
  end

  for k, v in pairs(second.acceptStates) do
    newMachine.acceptStates[k] = v
  end

  -- Link start state
  local xs = newMachine.states[newMachine.startState].edges
  xs[#xs + 1] = {condition = nf.epsilon, dest = second.startState}

  return newMachine
end

function nf.generateFromCapture(atom)
  local capture = atom[1]

  local machine
  if capture.type == "char" then
    local sName, cName = genName(), genName()
    machine = {
      states = {
        [sName] = {edges = {{condition = capture.value, dest = cName}}},
        [cName] = {edges = {}}
      },
      startState = sName,
      acceptStates = {[cName] = true}
    }
  elseif capture.type == "any" then
    local sName, cName = genName(), genName()
    machine = {
      states = {
        [sName] = {edges = {}},
        [cName] = {edges = {}}
      },
      startState = sName,
      acceptStates = {[cName] = true}
    }

    local sEdges = machine.states[sName].edges
    for i = 1, 255 do
      sEdges[#sEdges + 1] = {condition = string.char(i), dest = cName}
    end
  elseif capture.type == "set" or capture.type == "negset" then
    local sName, cName = genName(), genName()
    machine = {
      states = {
        [sName] = {edges = {}},
        [cName] = {edges = {}}
      },
      startState = sName,
      acceptStates = {[cName] = true}
    }

    local tState = {}
    for i = 1, #capture do
      local match = capture[i]
      if match.type == "char" then
        tState[match.value] = true
      elseif match.type == "range" then
        local dir = match.finish:byte() - match.start:byte()
        dir = dir / math.abs(dir)

        for j = match.start:byte(), match.finish:byte(), dir do
          tState[string.char(j)] = true
        end
      end
    end

    local sEdges = machine.states[sName].edges
    if capture.type == "set" then
      for k in pairs(tState) do
        sEdges[#sEdges + 1] = {condition = k, dest = cName}
      end
    else
      for i = 1, 255 do
        if not tState[string.char(i)] then
          sEdges[#sEdges + 1] = {condition = string.char(i), dest = cName}
        end
      end
    end
  elseif capture.type == "group" then
    machine = nf.generateNFA(capture[1])
    addEnter(machine.states[machine.startState], "begin-group")
    for k in pairs(machine.acceptStates) do
      addEnter(machine.states[k], "end-group")
    end
  else
    error("Unimplemented capture: '" .. capture.type .. "'")
  end

  if atom.type == "atom" then
    return machine
  elseif atom.type == "plus" then
    addEnter(machine.states[machine.startState], "begin-sort")

    for k in pairs(machine.acceptStates) do
      local es = machine.states[k].edges
      es[#es + 1] = {condition = nf.epsilon, dest = machine.startState}

      -- Mark the state for recording, used for path reduction later
      addEnter(machine.states[k], "maximize")
    end

    return machine
  elseif atom.type == "ng-plus" then
    addEnter(machine.states[machine.startState], "begin-sort")

    for k in pairs(machine.acceptStates) do
      local es = machine.states[k].edges
      es[#es + 1] = {condition = nf.epsilon, priority = "low", dest = machine.startState}

      -- Mark the state for recording
      addEnter(machine.states[k], "minimize")
    end

    return machine
  elseif atom.type == "star" then
    addEnter(machine.states[machine.startState], "begin-sort")

    local needStart = true
    for k in pairs(machine.acceptStates) do
      local es = machine.states[k].edges
      es[#es + 1] = {condition = nf.epsilon, dest = machine.startState}
      if k == machine.startState then
        needStart = false
      end

      -- Mark the state for recording
      addEnter(machine.states[k], "maximize")
    end

    if needStart then
      machine.acceptStates[machine.startState] = true
    end

    return machine
  elseif atom.type == "ng-star" then
    addEnter(machine.states[machine.startState], "begin-sort")

    local needStart = true
    for k in pairs(machine.acceptStates) do
      local es = machine.states[k].edges
      es[#es + 1] = {condition = nf.epsilon, priority = "low", dest = machine.startState}
      if k == machine.startState then
        needStart = false
      end

      -- Mark the state for recording
      addEnter(machine.states[k], "minimize")
    end

    if needStart then
      machine.acceptStates[machine.startState] = true
    end

    return machine
  end
end

function nf.generateNFA(parsedRegex)
  local machine = emptyMachine(true)
  machine.properties = parsedRegex.properties

  for i = 1, #parsedRegex do
    -- Different branches
    local branch = parsedRegex[i]
    local tempMachine = emptyMachine()

    for j = 1, #branch do
      local capture = branch[j]
      tempMachine = nf.concatMachines(tempMachine, nf.generateFromCapture(capture))
    end

    machine = nf.unionMachines(machine, tempMachine)
  end

  return machine
end

return nf