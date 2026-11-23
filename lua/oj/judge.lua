local fs = require("oj.core.fs")
local runner = require("oj.runner")
local text = require("oj.core.text")
local M = {}

local function normalize(data, mode)
  if mode == "tokens" then
    return vim.trim(data:gsub("%s+", " "))
  end
  if mode == "lines" then
    return data:gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n"):gsub("[ \t]+$", ""):gsub("\n+$", "")
  end
  return data
end

local function diff(expected, actual)
  if expected == actual then
    return ""
  end
  local first = 1
  -- Skip equal chunks before locating a late mismatch.
  while first + 1023 <= math.min(#expected, #actual)
    and expected:sub(first, first + 1023) == actual:sub(first, first + 1023) do
    first = first + 1024
  end
  while first <= math.min(#expected, #actual) and expected:byte(first) == actual:byte(first) do
    first = first + 1
  end
  local start = first > 3000 and first - 100 or 1
  local old = text.display(expected:sub(start), 4096)
  local new = text.display(actual:sub(start), 4096)
  local patch = vim.diff(old, new, { result_type = "unified", ctxlen = 2 })
  return string.format("首个不同字节 %d\n--- 期望\n+++ 实际\n%s", first, patch ~= "" and patch
    or ("期望字节 " .. tostring(expected:byte(first)) .. "，实际字节 " .. tostring(actual:byte(first))))
end

function M.compare(task, ctx, config, input, expected, actual)
  if not config.checker then
    local want, got = normalize(expected, config.compare), normalize(actual, config.compare)
    return want == got and "AC" or "WA", diff(want, got)
  end
  local dir = assert(vim.uv.fs_mkdtemp(ctx.dir .. "/checker-XXXXXX"))
  local argv = vim.deepcopy(config.checker)
  for _, item in ipairs({ { "input", input }, { "expected", expected }, { "actual", actual } }) do
    local path = dir .. "/" .. item[1]
    fs.write_new(path, item[2])
    argv[#argv + 1] = path
  end
  local run = runner.run(task, ctx, argv, {})
  vim.fn.delete(dir, "rf")
  local diagnostic = text.display(run.stdout .. run.stderr, 4096)
  if run.status == "OK" then
    return "AC", diagnostic, run
  elseif run.status == "RE" and run.code == 1 and run.signal == 0 then
    return "WA", diagnostic .. "\n" .. diff(expected, actual), run
  end
  return "ERROR", "checker 执行失败 (" .. run.status .. ")\n" .. diagnostic, run
end

function M.summary(run, output)
  local result = {}
  if run then
    for _, key in ipairs({ "status", "code", "signal", "wall_ms", "cpu_user_ms", "cpu_system_ms",
      "peak_rss_kib", "limit", "setup_errno", "timed_out", "output_limited" }) do
      result[key] = run[key]
    end
    result.stderr = text.display(run.stderr)
    if output then
      result.stdout = text.display(run.stdout)
    end
    result.error = run.spawn_error or run.io_error
  end
  return result
end

function M.compile_failure(report, compile, path)
  report.status = compile.status == "RE" and "CE" or compile.status
  report.compile = M.summary(compile, true)
  report.source = path
  return report
end

function M.evaluate(task, ctx, config, program, input, expected)
  local run = runner.run(task, ctx, program, { stdin = input })
  local result = { status = run.status, run = M.summary(run), input = text.display(input) }
  if run.status == "OK" and expected ~= nil then
    local status, patch, checker = M.compare(task, ctx, config, input, expected, run.stdout)
    result.status, result.diff = status, patch
    result.checker = checker and M.summary(checker, true)
  end
  result.expected = expected and text.display(expected)
  result.actual = text.display(run.stdout)
  return result
end

function M.test(task, config, dir, cases, kind)
  local success = kind == "run" and "OK" or "AC"
  local report = { kind = kind or "test", status = success, cases = {} }
  assert(#cases > 0, "没有选中的测试。用 :OJTestAdd 添加 .in / .out")
  local ctx = runner.prepare(task, config)
  local path = dir .. "/main.cpp"
  local executable, compile = runner.program(task, ctx, path, "main")
  if not executable then
    return M.compile_failure(report, compile, path)
  end
  for _, case in ipairs(cases) do
    task:check()
    local result
    local ok, input, expected = pcall(function()
      local input = case.input_path and fs.read(case.input_path, 4 * 1024 * 1024) or ""
      local expected = case.expected_path and fs.read(case.expected_path, 4 * 1024 * 1024)
      return input, expected
    end)
    if ok then
      result = M.evaluate(task, ctx, config, executable, input, expected)
    else
      result = { status = "ERROR", diff = tostring(input) }
    end
    result.name = case.name
    report.cases[#report.cases + 1] = result
    if report.status == success then
      report.status = result.status
    end
  end
  return report
end

return M
