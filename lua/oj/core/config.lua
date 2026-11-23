local M = {}

local defaults = {
  root = "~/Algorithms",
  paths = { problems = "problems", templates = "templates", generators = "generators", config = "config" },
  template = "cpp.cpp",
  cpp = { compiler = "g++", flags = { "-std=c++20", "-O2", "-Wall", "-Wextra", "-fdiagnostics-color=never" } },
  python = "python3",
  limits = { wall_ms = 2000, cpu_seconds = 0, memory_mib = 512, output_kib = 1024, compile_ms = 30000 },
  stress = { iterations = 1000, seed = 1, generator = "auto" },
  compare = "lines",
  checker = nil,
  luogu = { dataset = nil, timeout_ms = 120000 },
  statement = "float",
}

local function string_value(value)
  return type(value) == "string" and value ~= "" and not value:find("[%z\r\n]")
end

local function basename(value)
  return string_value(value) and not value:find("[/\\]") and value ~= "." and value ~= ".."
end

local function choice(...)
  local choices = { ... }
  return function(value)
    return vim.tbl_contains(choices, value)
  end
end

function M.integer(value, min, max)
  return type(value) == "number" and value >= min and value <= max and value % 1 == 0
end

local function range(min, max)
  return function(value)
    return M.integer(value, min, max)
  end
end

local function argv(value)
  if type(value) ~= "table" or not vim.islist(value) then
    return false
  end
  for _, arg in ipairs(value) do
    if not string_value(arg) then
      return false
    end
  end
  return true
end

local schema = {
  root = string_value,
  paths = { problems = basename, templates = basename, generators = basename, config = basename },
  template = basename,
  cpp = { compiler = string_value, flags = argv },
  python = string_value,
  limits = {
    wall_ms = range(1, 3600000), cpu_seconds = range(0, 3600), memory_mib = range(0, 1048576),
    output_kib = range(1, 4096), compile_ms = range(1, 3600000),
  },
  stress = { iterations = range(1, 1000000), seed = range(0, 4294967295), generator = choice("auto", "gen.cpp", "gen.py") },
  compare = choice("exact", "lines", "tokens"),
  checker = function(value)
    return argv(value) and #value > 0
  end,
  luogu = { dataset = string_value, timeout_ms = range(1000, 600000) },
  statement = choice("float", "split"),
}

local function merge(dest, opts, rules, prefix)
  assert(type(opts) == "table", prefix .. "需要配置表")
  for key, value in pairs(opts) do
    local name = prefix .. tostring(key)
    local rule = rules[key]
    assert(rule, "未知配置项 " .. name)
    if type(rule) == "table" then
      merge(dest[key], value, rule, name .. ".")
    else
      assert(rule(value), "无效配置项 " .. name)
      dest[key] = vim.deepcopy(value)
    end
  end
end

function M.make(opts)
  local config = vim.deepcopy(defaults)
  merge(config, opts == nil and {} or opts, schema, "")
  local paths = {}
  for _, name in pairs(config.paths) do
    assert(not paths[name], "paths 中的目录名称必须互不相同")
    paths[name] = true
  end
  local function absolute(path)
    if path:sub(1, 1) == "~" then
      assert(path == "~" or path:sub(1, 2) == "~/", "请用 ~/ 或绝对路径指定目录")
      path = vim.uv.os_homedir() .. path:sub(2)
    end
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"), { expand_env = false })
  end
  config.root = absolute(config.root)
  assert(config.root ~= "/", "root 不能使用文件系统根目录")
  if config.luogu.dataset then
    config.luogu.dataset = absolute(config.luogu.dataset)
  end
  return config
end

return M
