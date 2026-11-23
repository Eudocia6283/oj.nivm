local text = require("oj.core.text")
local integer = require("oj.core.config").integer
local M = { version = 1, max_file = 8 * 1024 * 1024, max_markdown = 10 * 1024 * 1024 }

function M.component(value)
  return type(value) == "string" and #value <= 80 and value:match("^[A-Za-z0-9][A-Za-z0-9_.-]*$") ~= nil
end

local function optional(value)
  if value == vim.NIL then
    return nil
  end
  return value
end

local function field(value, name, max)
  value = optional(value)
  if value == nil then
    return ""
  end
  assert(type(value) == "string" and #value <= max and text.valid(value), "无效的题目字段 " .. name)
  return value
end

local function number(value, name)
  value = optional(value)
  assert(value == nil or integer(value, 1, 2 ^ 40), "无效的题目字段 " .. name)
  return value
end

function M.validate(raw)
  assert(type(raw) == "table", "题目必须是 JSON 对象")
  assert(M.component(raw.platform) and M.component(raw.id), "无效的平台或题号")
  assert(raw.cache_version == nil or raw.cache_version == M.version, "题目缓存版本不受支持")
  local title = field(raw.title, "title", 1024)
  assert(title:find("%S") and not title:find("[\r\n]"), "题目标题必须为非空单行文本")
  local normalized = {
    cache_version = M.version,
    platform = raw.platform,
    id = raw.id,
    title = title,
    time_limit_ms = number(raw.time_limit_ms, "time_limit_ms"),
    memory_limit_kib = number(raw.memory_limit_kib, "memory_limit_kib"),
    source_url = field(raw.source_url, "source_url", 2048),
    imported_at = field(raw.imported_at, "imported_at", 64),
    origin = field(raw.origin, "origin", 64),
    samples = {},
    tags = {},
  }
  for _, key in ipairs({ "background", "description", "input_format", "output_format", "hint", "translation" }) do
    normalized[key] = field(raw[key], key, 1024 * 1024)
  end
  assert(normalized.source_url == "" or normalized.source_url:match("^https://[^%s]+$"), "无效的题目来源 URL")
  if normalized.imported_at == "" then
    normalized.imported_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  end
  local function label(value, key)
    if type(value) == "number" then
      assert(integer(value, 0, 2 ^ 32), "无效的题目字段 " .. key)
      return tostring(value)
    end
    local result = field(value, key, 256)
    assert(not result:find("[\r\n]"), "无效的题目字段 " .. key)
    return result
  end
  normalized.difficulty = label(raw.difficulty, "difficulty")
  local tags = optional(raw.tags)
  if tags == nil then
    tags = {}
  end
  assert(type(tags) == "table" and vim.islist(tags) and #tags <= 256, "无效的题目标签")
  for _, tag in ipairs(tags) do
    local result = label(tag, "tags")
    assert(result ~= "", "题目标签不能为空")
    normalized.tags[#normalized.tags + 1] = result
  end
  local samples = optional(raw.samples)
  if samples == nil then
    samples = {}
  end
  assert(type(samples) == "table" and vim.islist(samples) and #samples <= 64, "无效的题目样例")
  local size = 0
  for i, sample in ipairs(samples) do
    assert(type(sample) == "table" and type(sample.input) == "string" and type(sample.output) == "string",
      "样例 " .. i .. " 需要成对的 input / output 字符串")
    local input = field(sample.input, "sample.input", 256 * 1024)
    local output = field(sample.output, "sample.output", 256 * 1024)
    size = size + #input + #output
    assert(size <= 2 * 1024 * 1024, "样例总大小超出上限")
    normalized.samples[i] = { input = input, output = output }
  end
  return normalized
end

local function block(value)
  local length = 2
  for run in value:gmatch("`+") do
    length = math.max(length, #run)
  end
  local fence = string.rep("`", length + 1)
  return fence .. "\n" .. value .. (value:sub(-1) == "\n" and "" or "\n") .. fence
end

function M.markdown(problem)
  local parts = { "# " .. problem.id .. " " .. problem.title }
  if problem.source_url ~= "" then
    parts[#parts + 1] = "<" .. problem.source_url .. ">"
  end
  local details = {}
  for _, spec in ipairs({
    { "时间上限", problem.time_limit_ms, " ms" }, { "内存上限", problem.memory_limit_kib, " KiB" },
    { "难度", problem.difficulty, "" }, { "标签", table.concat(problem.tags, "、"), "" },
  }) do
    if spec[2] and spec[2] ~= "" then
      details[#details + 1] = "- " .. spec[1] .. " " .. spec[2] .. spec[3]
    end
  end
  parts[#parts + 1] = table.concat(details, "\n")
  for _, section in ipairs({
    { "题目背景", "background" }, { "题目描述", "description" }, { "输入格式", "input_format" },
    { "输出格式", "output_format" }, { "题目大意", "translation" }, { "说明", "hint" },
  }) do
    if problem[section[2]] ~= "" then
      parts[#parts + 1] = "## " .. section[1] .. "\n\n" .. problem[section[2]]
    end
  end
  for i, sample in ipairs(problem.samples) do
    parts[#parts + 1] = string.format("## 样例 %d\n\n### 输入\n\n%s\n\n### 输出\n\n%s", i,
      block(sample.input), block(sample.output))
  end
  return table.concat(parts, "\n\n") .. "\n"
end

return M
