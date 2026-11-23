local fs = require("oj.core.fs")
local model = require("oj.core.problem")
local uv = vim.uv
local M = {}

M.default_template = [[#include <iostream>

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);

    return 0;
}
]]

function M.layout(config)
  local root = config.root
  vim.fn.mkdir(root, "p", 448)
  fs.check(root, "directory")
  local paths = {}
  for key, name in pairs(config.paths) do
    paths[key] = fs.mkdir(root .. "/" .. name)
  end
  return paths
end

function M.locate(config, platform, id)
  assert(model.component(platform) and model.component(id), "无效的平台或题号")
  local base = config.root .. "/" .. config.paths.problems .. "/" .. platform
  if fs.check(config.root, "directory", true)
    and fs.check(vim.fs.dirname(base), "directory", true)
    and fs.check(base, "directory", true)
  then
    fs.check(base .. "/" .. id, "directory", true)
  end
  return base .. "/" .. id
end

function M.problem(dir)
  local problem = model.validate(fs.json(dir .. "/metadata.json", model.max_file))
  assert(problem.id == vim.fs.basename(dir) and problem.platform == vim.fs.basename(vim.fs.dirname(dir)),
    "题目元数据与目录不匹配 " .. dir)
  return problem
end

function M.create(config, raw)
  local problem = model.validate(raw)
  local metadata = vim.json.encode(problem) .. "\n"
  assert(#metadata <= model.max_file, "题目元数据超出大小上限")
  local statement = model.markdown(problem)
  assert(#statement <= model.max_markdown, "题面超出大小上限")
  local paths = M.layout(config)
  local parent = fs.mkdir(paths.problems .. "/" .. problem.platform)
  local target = parent .. "/" .. problem.id
  assert(not fs.check(target, "directory", true), "题目工作区已存在 " .. target)
  local template = paths.templates .. "/" .. config.template
  local source = fs.check(template, "file", true) and fs.read(template, 1024 * 1024) or M.default_template
  return fs.stage(parent, problem.id, function(dir)
    fs.write_new(dir .. "/main.cpp", source)
    fs.write_new(dir .. "/problem.md", statement)
    fs.write_new(dir .. "/notes.md", "# " .. problem.id .. " 笔记\n")
    local tests = fs.mkdir(dir .. "/tests")
    for i, sample in ipairs(problem.samples) do
      M.add_test(dir, "sample" .. i, sample.input, sample.output, tests)
    end
    fs.write_new(dir .. "/metadata.json", metadata)
    assert(uv.fs_rename(dir, target))
    return target
  end)
end

function M.add_test(dir, name, input, output, tests)
  assert(model.component(name), "无效的测试名称")
  assert(type(input) == "string" and type(output) == "string", "测试需要输入和期望输出")
  tests = tests or dir .. "/tests"
  fs.check(tests, "directory")
  local in_path, out_path = tests .. "/" .. name .. ".in", tests .. "/" .. name .. ".out"
  assert(not fs.kind(in_path) and not fs.kind(out_path), "测试已存在 " .. name)
  -- Publish the input last; the test scanner treats inputs as the entry point.
  fs.write_new(out_path, output)
  local ok, message = pcall(fs.write_new, in_path, input)
  if not ok then
    uv.fs_unlink(out_path)
    error(message, 0)
  end
  return in_path
end

function M.tests(dir, selected)
  local path = dir .. "/tests"
  fs.check(path, "directory")
  local cases = {}
  for name, kind in fs.entries(path) do
    local key = name:match("^(.+)%.in$")
    if key and model.component(key) and (not selected or selected == key) then
      assert(kind == "file", "需要普通测试文件 " .. name)
      assert(#cases < 256, "一次最多评测 256 组测试，可按名称选择单组")
      cases[#cases + 1] = { name = key, input_path = path .. "/" .. name, expected_path = path .. "/" .. key .. ".out" }
    end
  end
  table.sort(cases, function(a, b)
    return a.name < b.name
  end)
  return cases
end

function M.scan(config, visit, yield_step)
  local base = config.root .. "/" .. config.paths.problems
  if not fs.check(config.root, "directory", true) or not fs.check(base, "directory", true) then
    return 0
  end
  local invalid, count = 0, 0
  for platform, kind in fs.entries(base) do
    if kind == "directory" and model.component(platform) then
      for id, entry_type in fs.entries(base .. "/" .. platform) do
        if entry_type == "directory" and model.component(id) then
          local dir = base .. "/" .. platform .. "/" .. id
          count = count + 1
          if yield_step and count % 8 == 0 then
            yield_step()
          end
          local ok, value = pcall(M.problem, dir)
          if ok then
            visit(dir, value)
          else
            invalid = invalid + 1
          end
        end
      end
    end
  end
  return invalid
end

function M.record(dir, report, artifacts)
  local history = fs.mkdir(dir .. "/history")
  return fs.stage(history, "record", function(stage)
    if artifacts then
      for name, data in pairs(artifacts) do
        assert(model.component(name), "无效的记录文件名")
        fs.write_new(stage .. "/" .. name, data)
      end
    end
    local seconds, micros = uv.gettimeofday()
    report.id = string.format("%s-%06d-%s", os.date("!%Y%m%dT%H%M%SZ", seconds), micros, stage:sub(-6))
    report.date = os.date("!%Y-%m-%dT%H:%M:%SZ", seconds)
    fs.write_json(stage .. "/result.json", report)
    fs.write_json(stage .. "/summary.json", { id = report.id, date = report.date, kind = report.kind, status = report.status })
    assert(uv.fs_rename(stage, history .. "/" .. report.id))
    return report.id
  end)
end

function M.history(dir)
  local base = dir .. "/history"
  local result = {}
  if fs.check(base, "directory", true) then
    for name, kind in fs.entries(base) do
      if kind == "directory" and name:match("^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%d%d%d%d%d%d%-%w+$") then
        local path = base .. "/" .. name .. "/summary.json"
        local ok, report = pcall(fs.json, path, 8192)
        if ok and report.id == name and type(report.status) == "string" and type(report.kind) == "string"
          and type(report.date) == "string" then
          result[#result + 1] = { id = name, label = report.date .. "  " .. report.kind .. "  " .. report.status }
        end
      end
    end
    table.sort(result, function(a, b)
      return a.id > b.id
    end)
  end
  return result
end

function M.record_path(dir, id)
  assert(model.component(id), "无效的评测记录 ID")
  fs.check(dir .. "/history", "directory")
  local path = dir .. "/history/" .. id
  fs.check(path, "directory")
  return path
end

return M
