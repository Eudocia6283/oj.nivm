local fs = require("oj.core.fs")
local integer = require("oj.core.config").integer
local model = require("oj.core.problem")
local process = require("oj.runner.process")
local uv = vim.uv
local M = {}

function M.identify(value)
  assert(type(value) == "string" and #value <= 2048, "请提供洛谷题号或题页 URL")
  local host, path = value:match("^https://([^/]+)(/[^?#]*)")
  if host then
    assert(host == "www.luogu.com.cn" or host == "luogu.com.cn" or host == "www.luogu.com" or host == "luogu.com",
      "需要洛谷 HTTPS 题页 URL")
    value = assert(path:match("^/problem/([A-Za-z0-9_-]+)/?$"), "需要洛谷题页 URL")
  end
  if value:match("^%d+$") then
    value = "P" .. value
  elseif value:match("^[pPbBuUtT]%d+$") then
    value = value:upper()
  end
  assert(#value <= 80 and (value:match("^[PBUT]%d+$") or value:match("^CF%d+[A-Za-z0-9]+$")
    or value:match("^AT[A-Za-z0-9_]+$") or value:match("^SP%d+$") or value:match("^UVA%d+$")),
    "无效的洛谷题号 " .. value)
  return value
end

function M.source_url(id)
  return "https://www.luogu.com.cn/problem/" .. M.identify(id)
end

function M.submission_url(id)
  return M.source_url(id) .. "#submit"
end

M.export_url = "https://cdn.luogu.com.cn/problemset-open/latest.ndjson.gz"
local max_export = 512 * 1024 * 1024
local max_archive = 100 * 1024 * 1024

local function maximum(values, field)
  if values == nil or values == vim.NIL then
    return
  end
  assert(type(values) == "table" and vim.islist(values) and #values <= 4096, "无效的洛谷限制 " .. field)
  local result
  for _, value in ipairs(values) do
    assert(integer(value, 1, 2 ^ 40), "无效的洛谷限制 " .. field)
    result = math.max(result or 0, value)
  end
  return result
end

function M.decode(raw, id)
  assert(type(raw) == "table" and raw.pid == id and type(raw.title) == "string", "洛谷导出记录的题号或标题无效")
  local limits = raw.limits
  if limits == nil or limits == vim.NIL then
    limits = {}
  end
  assert(type(limits) == "table", "无效的洛谷限制")
  local problem = {
    platform = "luogu", id = id, title = raw.title, source_url = M.source_url(id), origin = "luogu-open-export",
    background = raw.background, description = raw.description, input_format = raw.inputFormat,
    output_format = raw.outputFormat, hint = raw.hint, translation = raw.translation, difficulty = raw.difficulty,
    tags = raw.tags, time_limit_ms = maximum(limits.time, "time"), memory_limit_kib = maximum(limits.memory, "memory"),
    samples = {},
  }
  if raw.samples ~= nil and raw.samples ~= vim.NIL then
    assert(type(raw.samples) == "table" and vim.islist(raw.samples) and #raw.samples <= 64, "无效的洛谷样例数组")
    for i, pair in ipairs(raw.samples) do
      assert(type(pair) == "table" and vim.islist(pair) and #pair == 2, "无效的洛谷样例 " .. i)
      problem.samples[i] = { input = pair[1], output = pair[2] }
    end
  end
  return model.validate(problem)
end

function M.dataset(config)
  return config.luogu.dataset or (
    config.root .. "/" .. config.paths.config .. "/luogu-open.ndjson.gz")
end

function M.has_dataset(config)
  if not config.luogu.dataset and (
    not fs.check(config.root, "directory", true)
    or not fs.check(config.root .. "/" .. config.paths.config, "directory", true)
  ) then
    return false
  end
  return fs.check(M.dataset(config), "file", true)
end

local function verify_process(run, action)
  assert(run.code == 0 and run.signal == 0 and not run.timed_out and not run.output_limited and not run.io_error,
    action .. "失败 " .. (run.spawn_error or run.io_error or (run.timed_out and "操作超时") or run.stderr))
end

local function scan_file(task, path, consume)
  local fd = assert(uv.fs_open(path, "r", 0))
  task:defer(function()
    if fd then
      uv.fs_close(fd)
    end
  end)
  local offset = 0
  while true do
    local request, message = uv.fs_read(fd, 128 * 1024, offset, function(read_error, chunk)
      vim.schedule(function()
        task:resume({ error = read_error, chunk = chunk })
      end)
    end)
    assert(request, message)
    local step = task:await()
    assert(not step.error, step.error)
    if not step.chunk or step.chunk == "" then
      break
    end
    consume(step.chunk)
    offset = offset + #step.chunk
  end
  uv.fs_close(fd)
  fd = nil
end

function M.from_dataset(task, config, id, path)
  path = path or M.dataset(config)
  fs.check(path, "file")
  local gzip = path:sub(-3) == ".gz"
  local stat = assert(uv.fs_stat(path))
  assert(stat.size <= (gzip and max_archive or max_export), "洛谷导出文件超出大小上限")
  local total, tail, record = 0, "", nil
  local function inspect_line(line)
    if line:match('"pid"%s*:%s*"([^"]+)"') == id then
      assert(not record, "洛谷导出文件中存在重复题号 " .. id)
      record = line
    end
  end
  local function consume(chunk)
    total = total + #chunk
    assert(total <= max_export, "洛谷导出解压后超出大小上限")
    local buffer = tail .. chunk
    local start = 1
    while true do
      local newline = buffer:find("\n", start, true)
      if not newline then
        break
      end
      assert(newline - start <= model.max_file, "洛谷导出中的单行超出大小上限")
      inspect_line(buffer:sub(start, newline - 1))
      start = newline + 1
    end
    tail = buffer:sub(start)
    assert(#tail <= model.max_file, "洛谷导出中的单行超出大小上限")
  end
  if gzip then
    verify_process(process.run(task, { "gzip", "-dc", "--", path }, {
      timeout_ms = config.luogu.timeout_ms,
      consume_stdout = consume,
    }), "解压洛谷导出")
  else
    scan_file(task, path, consume)
  end
  if tail ~= "" then
    inspect_line(tail)
  end
  assert(record, "导出文件中没有 " .. id .. "。可用 :OJImport 导入手动整理的 JSON")
  local ok, raw = pcall(vim.json.decode, record)
  assert(ok, "洛谷导出记录不是有效 JSON")
  return M.decode(raw, id)
end

function M.sync(task, config, config_dir)
  local stage = assert(uv.fs_mkdtemp(config_dir .. "/.luogu-XXXXXX"))
  task:defer(function() vim.fn.delete(stage, "rf") end)
  local archive = stage .. "/export.ndjson.gz"
  local target = config_dir .. "/luogu-open.ndjson.gz"
  fs.check(target, "file", true)
  verify_process(process.run(task, {
    "curl", "-q", "--proto", "=https", "--fail", "--silent", "--show-error",
    "--max-time", tostring(math.ceil(config.luogu.timeout_ms / 1000)),
    "--max-filesize", tostring(max_archive), "--output", archive, "--url", M.export_url,
  }, { timeout_ms = config.luogu.timeout_ms }), "下载洛谷官方导出")
  M.from_dataset(task, config, "P1001", archive)
  assert(uv.fs_rename(archive, target))
  return target
end

return M
