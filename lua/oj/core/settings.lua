local config = require("oj.core.config")
local fs = require("oj.core.fs")
local M = {}

function M.read(base, dir)
  local settings = vim.deepcopy(base)
  local file = dir .. "/settings.json"
  if not fs.check(file, "file", true) then
    return settings
  end
  local raw = fs.json(file, 8192)
  for key in pairs(raw) do
    assert(key == "iterations" or key == "seed" or key == "generator" or key == "compare",
      "未知题目设置 " .. tostring(key))
  end
  if raw.iterations ~= nil then
    assert(config.integer(raw.iterations, 1, 1000000), "iterations 必须是 1 到 1000000 的整数")
    settings.stress.iterations = raw.iterations
  end
  if raw.seed ~= nil then
    assert(config.integer(raw.seed, 0, 4294967295), "seed 必须是 0 到 4294967295 的整数")
    settings.stress.seed = raw.seed
  end
  if raw.generator ~= nil then
    assert(vim.tbl_contains({ "auto", "gen.cpp", "gen.py" }, raw.generator), "generator 需要 auto、gen.cpp 或 gen.py")
    settings.stress.generator = raw.generator
  end
  if raw.compare ~= nil then
    assert(vim.tbl_contains({ "exact", "lines", "tokens" }, raw.compare), "compare 需要 exact、lines 或 tokens")
    settings.compare = raw.compare
  end
  return settings
end

function M.open(base, dir)
  local file = dir .. "/settings.json"
  if not fs.check(file, "file", true) then
    fs.write_new(file, string.format(
      '{\n  "iterations": %d,\n  "seed": %.0f,\n  "generator": "%s",\n  "compare": "%s"\n}\n',
      base.stress.iterations, base.stress.seed, base.stress.generator, base.compare))
  end
  return file
end

return M
