local LOG_PREFIX = "[KeepSeducedUnits] "
local LOG_LEVELS = {
  DEBUG = 0,
  INFO = 1,
  WARNING = 2,
  ERROR = 3
}

local active_log_level = "ERROR"

function set_log_level(level)
  active_log_level = level
end

function log(message, level)
  level = level or "DEBUG"

  if LOG_LEVELS[level] >= LOG_LEVELS[active_log_level] then
    out(LOG_PREFIX .. message)
  end
end

function table.find_index_with_key(list, search_value, entry_key)
  for index, value in ipairs(list) do
    if value[entry_key] == search_value then
      return index
    end
  end
  return -1
end

function table.clone(original)
  return {unpack(original)}
end