local fs = require("oj.core.fs")
local process = require("oj.runner.process")
local uv = vim.uv
local M = {}

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local source = vim.fn.fnamemodify(here .. "/../../../native/supervisor.cpp", ":p")

local function executable(name)
  local path = vim.fn.exepath(name)
  assert(path ~= "", "找不到可执行文件 " .. name)
  return vim.fn.fnamemodify(path, ":p")
end

local function environment(dir)
  local values = { "HOME=" .. dir, "TMPDIR=" .. dir }
  for _, key in ipairs({ "PATH", "LANG", "LC_ALL", "LC_CTYPE" }) do
    if vim.env[key] then
      values[#values + 1] = key .. "=" .. vim.env[key]
    end
  end
  return values
end

function M.prepare(task, config)
  assert(uv.os_uname().sysname == "Linux", "本地评测引擎需要 Linux")
  local compiler = executable(config.cpp.compiler)
  local dir = assert(uv.fs_mkdtemp(vim.fn.tempname() .. "-oj-XXXXXX"))
  task:defer(function()
    assert(vim.fn.delete(dir, "rf") == 0, "无法删除运行目录 " .. dir)
  end)
  local ctx = { dir = dir, helper = dir .. "/supervisor", compiler = compiler, config = config, serial = 0 }
  local built = process.run(task, {
    compiler, "-x", "c++", "-std=c++17", "-O2", source, "-o", ctx.helper,
  }, { cwd = dir, env = environment(dir), timeout_ms = math.max(config.limits.compile_ms, 10000) })
  assert(built.code == 0 and built.signal == 0 and not built.timed_out and not built.output_limited,
    "无法构建本地进程监督器\n" .. (built.spawn_error or built.stderr))
  return ctx
end

function M.run(task, ctx, argv, opts)
  local limits = ctx.config.limits
  local wall = opts.compile and limits.compile_ms or limits.wall_ms
  ctx.serial = ctx.serial + 1
  local run_dir = fs.mkdir(ctx.dir .. "/run-" .. ctx.serial)
  local metrics = run_dir .. "/metrics"
  local cwd = opts.cwd or fs.mkdir(run_dir .. "/work")
  local command = {
    ctx.helper, metrics, tostring(wall),
    tostring(opts.compile and 0 or limits.cpu_seconds),
    string.format("%.0f", opts.compile and 0 or limits.memory_mib * 1024 * 1024),
    tostring((opts.compile and 128 or 16) * 1024 * 1024), tostring(uv.os_getpid()),
  }
  vim.list_extend(command, argv)
  local result = process.run(task, command, {
    cwd = cwd, stdin = opts.stdin or "", output_bytes = limits.output_kib * 1024,
    env = environment(run_dir), timeout_ms = wall + 2500, supervised = true,
  })
  local data = fs.check(metrics, "file", true) and fs.read(metrics, 256) or ""
  vim.fn.delete(run_dir, "rf")
  local reason, elapsed, user, system, rss, code, signal, setup = data:match(
    "^(%a+) (%d+) (%d+) (%d+) (%d+) (-?%d+) (%d+) (%d+)\n$")
  if reason then
    result.wall_ms = tonumber(elapsed) / 1000
    result.cpu_user_ms = tonumber(user) / 1000
    result.cpu_system_ms = tonumber(system) / 1000
    result.peak_rss_kib = tonumber(rss)
    result.code = tonumber(code) >= 0 and tonumber(code) or nil
    result.signal = tonumber(signal)
    result.setup_errno = tonumber(setup)
  end
  if result.output_limited or reason == "file" then
    result.status = "OLE"
  elseif reason == "wall" or result.timed_out or reason == "cpu" then
    result.status = "TLE"
    result.limit = reason == "cpu" and "cpu" or "wall"
  elseif not reason or result.setup_errno ~= 0 or result.io_error or reason == "stop" then
    result.status = "ERROR"
  elseif result.code ~= 0 or result.signal ~= 0 then
    result.status = "RE"
  else
    result.status = "OK"
  end
  return result
end

function M.program(task, ctx, path, label)
  fs.check(path, "file")
  if path:sub(-4) == ".cpp" then
    local output = ctx.dir .. "/" .. label
    local argv = { ctx.compiler }
    vim.list_extend(argv, ctx.config.cpp.flags)
    vim.list_extend(argv, { path, "-o", output })
    local result = M.run(task, ctx, argv, { cwd = vim.fs.dirname(path), compile = true })
    if result.status == "OK" and (not fs.check(output, "file", true) or vim.fn.executable(output) ~= 1) then
      result.status = "ERROR"
      result.stderr = result.stderr .. "\n编译器没有产出可执行程序"
    end
    return result.status == "OK" and { output } or nil, result
  end
  assert(path:sub(-3) == ".py", "不支持的源文件类型 " .. path)
  return { executable(ctx.config.python), path }
end

return M
