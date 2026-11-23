local fs = require("oj.core.fs")
local judge = require("oj.judge")
local runner = require("oj.runner")
local text = require("oj.core.text")
local M = {}

function M.generator(config, dir)
  local choice = config.stress.generator
  local names = choice == "auto" and { "gen.cpp", "gen.py" } or { choice }
  local shared = config.root .. "/" .. config.paths.generators
  for _, parent in ipairs({ dir, shared }) do
    if fs.check(parent, "directory", true) then
      for _, name in ipairs(names) do
        local path = parent .. "/" .. name
        if fs.check(path, "file", true) then
          return path
        end
      end
    end
  end
  error("找不到生成器。请在题目或生成器目录编写 gen.cpp / gen.py", 0)
end

local function failure(report, seed, status, stage, runs, patch)
  report.status, report.case_seed, report.stage = status, seed, stage
  local input = runs.generator.stdout
  local case = {
    name = "第 " .. (report.passed + 1) .. " 轮 · " .. stage, seed = seed, status = status,
    input = text.display(input), diff = patch, runs = {},
  }
  report.artifacts = { ["input.in"] = input }
  for _, name in ipairs({ "generator", "main", "brute", "checker" }) do
    local run = runs[name]
    if run then
      case.runs[name] = judge.summary(run, name == "checker")
      report.artifacts[name .. ".stderr"] = run.stderr
      if name ~= "generator" then
        report.artifacts[name .. ".out"] = run.stdout
      end
    end
  end
  case.run = case.runs[stage] or case.runs.main
  if runs.main then
    case.actual = text.display(runs.main.stdout)
  end
  if runs.brute then
    case.expected = text.display(runs.brute.stdout)
  end
  report.replay = runs.brute ~= nil and runs.brute.status == "OK"
  report.compare = report.replay and report.compare or nil
  report.cases = { case }
  return report
end

function M.run(task, config, dir, generator, progress)
  local stress = config.stress
  local report = {
    kind = "stress", status = "AC", seed = stress.seed, iterations = stress.iterations, passed = 0, cases = {},
    compare = config.compare, used_checker = config.checker ~= nil,
  }
  local ctx = runner.prepare(task, config)
  local programs = {}
  for _, item in ipairs({ { "main", dir .. "/main.cpp" }, { "brute", dir .. "/brute.cpp" }, { "generator", generator } }) do
    local name, file = item[1], item[2]
    local argv, compile = runner.program(task, ctx, file, name)
    if not argv then
      report.stage = name
      return judge.compile_failure(report, compile, file)
    end
    programs[name] = argv
  end
  for i = 1, stress.iterations do
    local seed = (stress.seed + i - 1) % 4294967296
    local gen = vim.deepcopy(programs.generator)
    gen[#gen + 1] = string.format("%.0f", seed)
    local runs = { generator = runner.run(task, ctx, gen, {}) }
    if runs.generator.status ~= "OK" then
      return failure(report, seed, "ERROR", "generator", runs, "生成器失败 " .. runs.generator.status)
    end
    local input = runs.generator.stdout
    runs.main = runner.run(task, ctx, programs.main, { stdin = input })
    runs.brute = runner.run(task, ctx, programs.brute, { stdin = input })
    if runs.brute.status ~= "OK" then
      return failure(report, seed, "ERROR", "brute", runs, "参考程序失败 " .. runs.brute.status)
    end
    if runs.main.status ~= "OK" then
      return failure(report, seed, runs.main.status, "main", runs, "待测程序失败 " .. runs.main.status)
    end
    local status, patch, checker = judge.compare(task, ctx, config, input, runs.brute.stdout, runs.main.stdout)
    runs.checker = checker
    if status ~= "AC" then
      return failure(report, seed, status, checker and "checker" or "compare", runs, patch)
    end
    report.passed = i
    if progress and i < stress.iterations and i % 250 == 0 then
      progress(i, stress.iterations)
    end
  end
  return report
end

return M
