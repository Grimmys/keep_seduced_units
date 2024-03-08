local LOG_PREFIX = "[KeepSeducedUnits] "

function log(message)
  out(LOG_PREFIX .. message)
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