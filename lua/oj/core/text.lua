local M = {}

-- LuaJIT patterns operate on bytes. Check canonical UTF-8 without replacing
-- invalid input, and preserve the original bytes of valid statements and tests.
local function utf8_size(s, i, byte)
  local second, third, fourth = s:byte(i + 1, i + 3)
  local function continuation(value)
    return value and value >= 128 and value <= 191
  end
  if byte >= 194 and byte <= 223 and continuation(second) then
    return 2
  end
  if not continuation(second) or not continuation(third) then
    return
  end
  if byte >= 224 and byte <= 239 then
    if (byte ~= 224 or second >= 160) and (byte ~= 237 or second <= 159) then
      return 3
    end
  elseif byte >= 240 and byte <= 244 and continuation(fourth) then
    if (byte ~= 240 or second >= 144) and (byte ~= 244 or second <= 143) then
      return 4
    end
  end
end

function M.valid(s)
  if s:find("[%z\1-\8\11\12\14-\31\127]") then
    return false
  end
  local i = s:find("[\128-\255]")
  while i do
    local size = utf8_size(s, i, s:byte(i))
    if not size then
      return false
    end
    i = s:find("[\128-\255]", i + size)
  end
  return true
end

function M.display(s, limit)
  s = s or ""
  limit = limit or 8192
  local chunks, start = {}, 1
  local i = 1
  while i <= math.min(#s, limit) do
    local byte = s:byte(i)
    local size = byte < 128 and 1 or utf8_size(s, i, byte)
    if size and i + size - 1 > limit then
      break
    end
    if not size or (byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13) or byte == 127 then
      chunks[#chunks + 1] = s:sub(start, i - 1)
      chunks[#chunks + 1] = string.format("\\x%02X", byte)
      start = i + 1
    end
    i = i + (size or 1)
  end
  chunks[#chunks + 1] = s:sub(start, i - 1)
  if i <= #s then
    chunks[#chunks + 1] = "\n[… 显示已截断 …]\n"
  end
  return table.concat(chunks):gsub("\r\n", "\n"):gsub("\r", "\\r")
end

return M
