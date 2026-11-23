local fs = require("oj.core.fs")
local model = require("oj.core.problem")
local integer = require("oj.core.config").integer
local task = require("oj.core.task")
local providers = require("oj.providers")
local storage = require("oj.storage")
local settings = require("oj.core.settings")
local stress = require("oj.stress")
local judge = require("oj.judge")
local ui = require("oj.ui")
local M = {}

local function config()
  return require("oj").config
end

local function current()
  local cfg = config()
  local prefix = cfg.root .. "/" .. cfg.paths.problems .. "/"
  local dir = vim.b.oj_dir
  local path = dir and (dir .. "/") or vim.api.nvim_buf_get_name(0)
  assert(path:sub(1, #prefix) == prefix, "请先用 :OJOpen 或 :OJNew 打开题目")
  local platform, id = path:sub(#prefix + 1):match("^([^/]+)/([^/]+)/")
  assert(platform and id, "当前缓冲区不属于题目工作区")
  dir = storage.locate(cfg, platform, id)
  return dir, storage.problem(dir)
end

local function parse(args)
  local platform, id, index = providers.identify(args)
  return platform, id, index, providers.get(platform)
end

local function editing(dir)
  return ui.edit(dir .. "/main.cpp")
end

local function absolute(path)
  assert(not path:find("[%z\r\n]"), "无效文件路径")
  return vim.fn.fnamemodify(path, ":p")
end

local function unsaved(path)
  local buf = vim.fn.bufnr(path)
  assert(buf == -1 or not vim.bo[buf].modified, "请先保存 " .. path)
end

local function task_error(reason)
  if task.is_cancelled(reason) then
    ui.notify("任务已取消")
  else
    ui.notify(tostring(reason), vim.log.levels.ERROR)
  end
end

local function run_report(kind, dir, fn)
  task.start(kind, fn, function(ok, report)
    if not ok then
      task_error(report)
      return
    end
    local artifacts = report.artifacts
    report.artifacts = nil
    local saved, message = pcall(storage.record, dir, report, artifacts)
    if not saved then
      ui.notify("结果保存失败 " .. tostring(message), vim.log.levels.ERROR)
      return
    end
    ui.notify(report.kind .. " " .. report.status .. "（本地）。:OJResults 查看详情")
  end)
end

local function read_report(dir, id)
  return fs.json(storage.record_path(dir, id) .. "/result.json", 32 * 1024 * 1024)
end

local function create_manual(platform, id, adapter, path)
  local problem = path and fs.json(absolute(path), model.max_file) or { title = id }
  assert(not problem.platform or problem.platform == platform, "导入文件的平台与参数不符")
  assert(not problem.id or problem.id == id, "导入文件的题号与参数不符")
  problem.platform, problem.id = platform, id
  problem.source_url = adapter.source_url(id)
  problem.imported_at, problem.origin = nil, "manual"
  editing(storage.create(config(), problem))
end

local handlers = {}

local function import_dataset(cfg, adapter, id, pathname)
  assert(adapter.from_dataset, "该平台未提供导出文件导入")
  local original_win, original_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  task.start("import", function(job)
    local problem = adapter.from_dataset(job, cfg, id, pathname)
    job:check()
    return storage.create(cfg, problem)
  end, function(ok, dir)
    if not ok then
      task_error(dir)
    elseif vim.api.nvim_get_current_win() == original_win and vim.api.nvim_get_current_buf() == original_buf
      and vim.fn.mode() == "n" and not vim.bo[original_buf].modified then
      local opened, message = pcall(editing, dir)
      if not opened then
        ui.notify("题目已缓存，打开解法失败 " .. tostring(message), vim.log.levels.WARN)
      end
    else
      ui.notify("题目已缓存。:OJOpen " .. id .. " 打开")
    end
  end)
end

function handlers.OJOpen(opts)
  local platform, id, index, adapter = parse(opts.fargs)
  assert(#opts.fargs == index, "用法 :OJOpen [平台] 题号或 URL")
  local cfg = config()
  local dir = storage.locate(cfg, platform, id)
  if fs.check(dir, "directory", true) then
    storage.problem(dir)
    editing(dir)
    return
  end
  assert(adapter.has_dataset and adapter.has_dataset(cfg),
    "题目未缓存且找不到导出文件。用 :OJImport 导入，或用 :OJNew 创建")
  import_dataset(cfg, adapter, id)
end

function handlers.OJNew(opts)
  local platform, id, index, adapter = parse(opts.fargs)
  assert(#opts.fargs == index, "用法 :OJNew [平台] 题号或 URL")
  create_manual(platform, id, adapter)
end

function handlers.OJImport(opts)
  local platform, id, index, adapter = parse(opts.fargs)
  local path = opts.args
  for _ = 1, index do
    path = path:match("^%s*%S+%s+(.*)$") or ""
  end
  path = path:gsub("\\([ \t])", "%1")
  if path == "" then
    assert(adapter.has_dataset and adapter.has_dataset(config()),
      "用法 :OJImport [平台] 题号或 URL [题目.json 或导出文件]")
    import_dataset(config(), adapter, id)
  elseif path:match("%.ndjson$") or path:match("%.ndjson%.gz$") then
    import_dataset(config(), adapter, id, absolute(path))
  else
    create_manual(platform, id, adapter, path)
  end
end

function handlers.OJLuoguSync()
  local cfg = config()
  task.start("sync", function(job)
    return providers.get("luogu").sync(job, cfg, storage.layout(cfg).config)
  end, function(ok, result)
    if ok then
      ui.notify("官方导出已缓存 " .. result)
    else
      task_error(result)
    end
  end)
end

function handlers.OJStatement()
  ui.statement(current(), config().statement == "split")
end

function handlers.OJNotes()
  local dir = current()
  ui.edit(dir .. "/notes.md", true)
end

function handlers.OJTest(opts)
  local dir = current()
  local selected = opts.fargs[1]
  assert(not selected or model.component(selected), "无效测试名称")
  local cases = storage.tests(dir, selected)
  unsaved(dir .. "/main.cpp")
  for _, case in ipairs(cases) do
    unsaved(case.input_path)
    unsaved(case.expected_path)
  end
  unsaved(dir .. "/settings.json")
  local cfg = settings.read(config(), dir)
  run_report("test", dir, function(job)
    return judge.test(job, cfg, dir, cases)
  end)
end

function handlers.OJRun(opts)
  local dir = current()
  local input = opts.fargs[1]
  if input then
    input = absolute(input)
    unsaved(input)
  end
  unsaved(dir .. "/main.cpp")
  local cfg = config()
  run_report("run", dir, function(job)
    return judge.test(job, cfg, dir, { { name = "运行", input_path = input } }, "run")
  end)
end

local function edit_pair(dir, name)
  assert(model.component(name), "无效测试名称")
  fs.check(dir .. "/tests", "directory")
  local path = dir .. "/tests/" .. name
  fs.check(path .. ".in", "file")
  fs.check(path .. ".out", "file")
  ui.edit(path .. ".in", true)
  ui.edit(path .. ".out", true)
end

function handlers.OJTestAdd(opts)
  local dir = current()
  local name = opts.fargs[1]
  assert(#opts.fargs == 1 or #opts.fargs == 3, "用法 :OJTestAdd 名称 [输入文件 期望输出文件]")
  if #opts.fargs == 3 then
    local input = fs.read(absolute(opts.fargs[2]), 4 * 1024 * 1024)
    local output = fs.read(absolute(opts.fargs[3]), 4 * 1024 * 1024)
    storage.add_test(dir, name, input, output)
    ui.notify("已添加测试 " .. name)
  else
    storage.add_test(dir, name, "", "")
    edit_pair(dir, name)
  end
end

function handlers.OJTestEdit(opts)
  edit_pair(current(), opts.fargs[1])
end

function handlers.OJStressConfig()
  local dir = current()
  ui.edit(settings.open(config(), dir), true)
end

function handlers.OJStress(opts)
  assert(#opts.fargs <= 2, "用法 :OJStress [次数 [种子]]")
  local dir = current()
  for _, name in ipairs({ "main.cpp", "brute.cpp", "settings.json" }) do
    unsaved(dir .. "/" .. name)
  end
  fs.check(dir .. "/brute.cpp", "file")
  local cfg = settings.read(config(), dir)
  for index, name in ipairs({ "iterations", "seed" }) do
    if opts.fargs[index] then
      local value = opts.fargs[index]
      local maximum = name == "iterations" and 1000000 or 4294967295
      assert(value:match("^%d+$") and integer(tonumber(value),
        name == "iterations" and 1 or 0, maximum), "无效的对拍参数 " .. name)
      cfg.stress[name] = tonumber(value)
    end
  end
  local generator = stress.generator(cfg, dir)
  unsaved(generator)
  run_report("stress", dir, function(job)
    return stress.run(job, cfg, dir, generator, function(passed, iterations)
      ui.notify(string.format("对拍通过 %d / %d", passed, iterations))
    end)
  end)
end

function handlers.OJStressStop()
  if not task.stop("stress") then
    ui.notify("没有正在运行的对拍")
  end
end

local function latest(dir)
  local records = storage.history(dir)
  return records[1] and records[1].id
end

function handlers.OJReplay(opts)
  local dir = current()
  local id = opts.fargs[1] or latest(dir)
  assert(id, "没有可复现的对拍记录")
  local report = read_report(dir, id)
  assert(report.kind == "stress" and report.replay == true, "该记录缺少有效的参考输出")
  local path = storage.record_path(dir, id)
  unsaved(dir .. "/main.cpp")
  unsaved(dir .. "/settings.json")
  local cfg = settings.read(config(), dir)
  assert(not report.used_checker or cfg.checker, "这条记录使用了 checker，请先恢复对应的 checker 配置")
  if not report.used_checker then
    cfg.checker = nil
  end
  if vim.tbl_contains({ "exact", "lines", "tokens" }, report.compare) then
    cfg.compare = report.compare
  end
  run_report("replay", dir, function(job)
    local result = judge.test(job, cfg, dir, {
      { name = "重放 " .. id, input_path = path .. "/input.in", expected_path = path .. "/brute.out" },
    }, "replay")
    result.replayed_id = id
    return result
  end)
end

local function list(query)
  local cfg = config()
  task.start("search", function(job)
    local result = {}
    local needle = vim.fn.tolower(query)
    local invalid = storage.scan(cfg, function(dir, p)
      local metadata = table.concat({ p.platform, p.id, p.title, p.difficulty, table.concat(p.tags, " ") }, " ")
      local matches = query == "" or vim.fn.tolower(metadata):find(needle, 1, true)
      if not matches then
        for _, key in ipairs({ "description", "background", "input_format", "output_format", "hint", "translation" }) do
          if vim.fn.tolower(p[key]):find(needle, 1, true) then
            matches = true
            break
          end
        end
      end
      if matches then
        result[#result + 1] = { dir = dir, label = table.concat({ p.platform, p.id, p.title, p.difficulty }, "  ") }
      end
    end, function()
      vim.schedule(function() job:resume() end)
      job:await()
    end)
    table.sort(result, function(a, b) return a.label < b.label end)
    return { entries = result, invalid = invalid }
  end, function(ok, result)
    if not ok then
      task_error(result)
      return
    end
    if result.invalid > 0 then
      ui.notify(string.format("跳过 %d 个无效题目目录", result.invalid), vim.log.levels.WARN)
    end
    ui.select(result.entries, "本地题库", function(item) editing(item.dir) end)
  end)
end

function handlers.OJList()
  list("")
end

function handlers.OJSearch(opts)
  if opts.args ~= "" then
    list(opts.args)
    return
  end
  vim.ui.input({ prompt = "本地题库搜索 " }, function(query)
    if query then
      local ok, message = pcall(list, query)
      if not ok then
        task_error(message)
      end
    end
  end)
end

function handlers.OJHistory()
  local dir = current()
  ui.select(storage.history(dir), "本题评测历史", function(item)
    ui.results(dir, read_report(dir, item.id))
  end)
end

function handlers.OJResults(opts)
  local dir = current()
  local id = opts.fargs[1] or latest(dir)
  assert(id, "当前题目还没有评测记录")
  ui.results(dir, read_report(dir, id))
end

function handlers.OJStop()
  if not task.stop() then
    ui.notify("没有正在运行的任务")
  end
end

function handlers.OJSubmit()
  local _, problem = current()
  require("oj.submission").open(problem)
end

local commands = {
  OJOpen = { "+", "打开题目解法" }, OJNew = { "+", "创建空的题目工作区" },
  OJImport = { "+", "导入题面与样例", "file" }, OJStatement = { 0, "显示题面" },
  OJNotes = { 0, "编辑个人笔记" }, OJTest = { "?", "运行本地测试" },
  OJRun = { "?", "单独编译并运行解法", "file" },
  OJResults = { "?", "显示本地评测结果" }, OJStop = { 0, "取消当前任务" },
  OJSubmit = { 0, "打开浏览器提交入口" }, OJLuoguSync = { 0, "下载洛谷开放平台题库导出" },
  OJTestAdd = { "+", "添加自定义测试" }, OJTestEdit = { 1, "编辑测试输入和期望输出" },
  OJStress = { "*", "运行对拍" }, OJStressStop = { 0, "取消对拍" }, OJStressConfig = { 0, "编辑题目对拍设置" },
  OJReplay = { "?", "重放对拍失败输入" }, OJList = { 0, "列出缓存题目" }, OJSearch = { "?", "搜索本地题库" },
  OJHistory = { 0, "选择历史评测结果" },
}

function M.register()
  if M.registered then
    return
  end
  for name, spec in pairs(commands) do
    local handler = handlers[name]
    vim.api.nvim_create_user_command(name, function(opts)
      local ok, message = pcall(handler, opts)
      if not ok then
        ui.notify(tostring(message), vim.log.levels.ERROR)
      end
    end, { nargs = spec[1], desc = spec[2], complete = spec[3] })
  end
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("OjNvimTasks", { clear = true }),
    callback = function() task.stop() end,
  })
  M.registered = true
end

return M
