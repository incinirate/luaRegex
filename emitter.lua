local emitter = {}

-- local counter = 0
-- local function makeName()
--   counter = counter + 1
--   return "n" .. counter
-- end

--[[

local states = {
  s1 = function(nextChar) ... end,
  ...
}

local acceptStates = {s1 = true, ...}

return function match(str)
  local strlen = #str
  local state = s1
  local allMatches, ai = {}, 1

  for startChar = 1, strlen do -- Conditional upon properties.clampStart
    local ci = 0
    while state and ci <= strlen do
      if acceptStates[state] then
        if ci == strlen then -- Conditional upon properties.clampEnd
          allMatches[ai] = {str:sub(1, ci), startChar, ci + startChar - 1}
        end
      end

      state = states[state](str:sub(ci + 1, ci + 1))

      ci = ci + 1
    end
  end

  return unpack(allMatches)
end

]]

local function generateFunction(state)
  if #state.edges == 0 then
    return "function() end"
  end

  local output = "function(char)"

  local dests = {}
  for i = 1, #state.edges do
    local edge = state.edges[i]
    local dest = edge.dest
    dests[dest] = dests[dest] or {}
    dests[dest][#dests[dest] + 1] = edge.condition
  end

  local prefix = "if"
  for dest, conds in pairs(dests) do
    output = output .. "\n    " .. prefix .. " char:match(\"["
    
    table.sort(conds)
    local ranges = {}
    local singles = {}

    while #conds > 0 do
      if #conds == 1 then
        singles[#singles + 1] = conds[1]
        break
      elseif #conds == 2 then
        singles[#singles + 1] = conds[1]
        singles[#singles + 1] = conds[2]
        break
      end

      local val, index = conds[1]:byte(), 2
      while conds[index]:byte() - index + 1 == val do
        index = index + 1
        if index > #conds then
          break
        end
      end

      index = index - 1

      if index == 1 then
        singles[#singles + 1] = table.remove(conds, 1)
      elseif index == 2 then
        singles[#singles + 1] = table.remove(conds, 1)
        singles[#singles + 1] = table.remove(conds, 1)
      else
        ranges[#ranges + 1] = {string.char(val), string.char(val + index - 1)}
        for i = 1, index do
          table.remove(conds, 1)
        end
      end
    end

    for i = 1, #ranges do
      local range = ranges[i]

      if range[1] == "]" then
        output = output .. "%]"
      elseif range[1]:match("[a-zA-Z]") then
        output = output .. range[1]
      else
        output = output .. "\\" .. range[1]:byte()
      end

      output = output .. "-"

      if range[2] == "]" then
        output = output .. "%]"
      elseif range[2]:match("[a-zA-Z]") then
        output = output .. range[2]
      else
        output = output .. "\\" .. range[2]:byte()
      end
    end

    for i = 1, #singles do
      if singles[i]:match("[a-zA-Z]") then
        output = output .. singles[i]
      else
        output = output .. "%\\" .. singles[i]:byte()
      end
    end

    output = output .. "]\") then return \"" .. dest .. "\""

    prefix = "elseif"
  end

  output = output .. " end\n  end"

  return output
end

function emitter.generateLua(dfa)
  local output = [[
local unpack = unpack or table.unpack

local states = {
]]

  for stateName, state in pairs(dfa.states) do
    output = output .. "  " .. stateName .. " = " .. generateFunction(state) .. ",\n"
  end

  output = output .. [[}

local acceptStates = {]]

  for state in pairs(dfa.acceptStates) do
    output = output .. state .." = true,"
  end

  output = output .. [[}
return function match(str)
  local strlen = #str
  local allMatches, ai = {}, 1
  
  ]]

  if dfa.properties.clampStart then
    output = output .. "local startChar = 1 do\n"
  else
    output = output .. "for startChar = 1, strlen do\n"
  end

  output = output .. [[
    local state = "]]
  
  output = output .. dfa.startState

  output = output .. [["
    local ci = startChar - 1
    while state and ci <= strlen do
      if acceptStates[state] then
]]

  if dfa.properties.clampEnd then
    output = output .. [[
        if ci == strlen then
          ]]
  else
    output = output .. [[
        do
          ]]
  end

  output = output .. [[allMatches[ai] = {str:sub(startChar, ci), startChar, ci}
          ai = ai + 1
        end
      end

      state = states[state](str:sub(ci + 1, ci + 1))

      ci = ci + 1
    end
  end

  local result
  for i = 1, #allMatches do
    if (not result) or #allMatches[i][1] > #result[1] then
      result = allMatches[i]
    end
  end

  if result then
    return unpack(result)
  end
end
]]

  return output
end

return emitter