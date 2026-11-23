local fs = require("oj.core.fs")
local model = require("oj.core.problem")
local text = require("oj.core.text")
local M = {}

function M.notify(message, level)
  vim.notify("oj.nvim · " .. message, level)
end

local function map(buf, key, action, description)
  vim.keymap.set("n", key, action, { buffer = buf, silent = true, nowait = true, desc = description })
end

function M.edit(path, split)
  fs.check(path, "file")
  local buf = vim.fn.bufadd(path)
  if split then
    vim.cmd("botright split")
  end
  vim.api.nvim_win_set_buf(0, buf)
  return buf
end

function M.panel(title, lines, filetype, split, parent)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modeline = false
  vim.b[buf].oj_dir = parent
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win
  if split then
    vim.cmd("botright vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    local columns, rows = vim.o.columns, vim.o.lines
    local width, height = math.max(1, math.min(112, columns - 6)), math.max(1, math.min(#lines, rows - 6))
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = width, height = height,
      col = math.max(0, math.floor((columns - width) / 2) - 1),
      row = math.max(0, math.floor((rows - height) / 2) - 1),
      style = "minimal", border = "rounded", title = " " .. title .. " ",
    })
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.bo[buf].filetype = filetype or "text"
  map(buf, "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end, "关闭 OJ 窗口")
  return buf
end

function M.statement(dir, split)
  local contents = fs.read(dir .. "/problem.md", model.max_markdown):gsub("\r\n", "\n")
  M.panel("题面", vim.split(contents, "\n", { plain = true }), "markdown", split, dir)
end

local function show(title, value, filetype, dir)
  M.panel(title, vim.split(value, "\n", { plain = true }), filetype, false, dir)
end

local function resources(run)
  if not run or not run.wall_ms then
    return ""
  end
  local result = string.format("  墙钟 %.1f ms", run.wall_ms)
  if run.cpu_user_ms and run.cpu_system_ms then
    result = result .. string.format("  CPU %.1f ms", run.cpu_user_ms + run.cpu_system_ms)
  end
  if run.peak_rss_kib then
    result = result .. string.format("  峰值 RSS %d KiB", run.peak_rss_kib)
  end
  if run.limit then
    result = result .. "  超时类型 " .. run.limit
  end
  return result
end

local function diagnostics(compile)
  local lines = vim.split(compile.stderr or "", "\n", { plain = true })
  local items = {}
  for _, line in ipairs(lines) do
    local path, row, col, message = line:match("^(.-):(%d+):(%d+):%s*(.+)$")
    if not path then
      path, row, message = line:match("^(.-):(%d+):%s*(.+)$")
    end
    if path then
      items[#items + 1] = { filename = path, lnum = tonumber(row), col = tonumber(col) or 1, text = message }
    end
  end
  if #items == 0 then
    M.notify("编译器未返回可跳转的诊断", vim.log.levels.WARN)
    return
  end
  vim.fn.setqflist({}, " ", { title = "OJ 编译诊断", items = items })
  vim.cmd("copen")
end

function M.results(dir, report)
  local lines = { report.kind .. "  " .. report.status .. "（本地）" }
  local rows = {}
  if report.id then
    lines[#lines + 1] = "记录 " .. report.id
  end
  if report.seed then
    lines[#lines + 1] = string.format("起始种子 %s  通过 %s / %s", report.seed, report.passed, report.iterations)
  end
  if report.compile then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "编译诊断 · c 打开 quickfix"
    vim.list_extend(lines, vim.split((report.compile.stderr or "") .. (report.compile.stdout or ""), "\n",
      { plain = true }))
  end
  if report.cases and #report.cases > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<Enter> 详情    d 差异    ]e / [e 失败测试    q 关闭"
    for _, case in ipairs(report.cases) do
      lines[#lines + 1] = string.format("%s  %s%s%s", case.status, case.name, resources(case.run),
        case.seed and ("  种子 " .. case.seed) or "")
      rows[#lines] = case
    end
  end
  if report.replay and report.id then
    lines[#lines + 1] = ""
    lines[#lines + 1] = ":OJReplay " .. report.id
  end
  if report.case_seed then
    lines[#lines + 1] = ":OJStress 1 " .. report.case_seed
  end
  local buf = M.panel("本地评测", lines, "text", false, dir)
  local function selected()
    return rows[vim.api.nvim_win_get_cursor(0)[1]]
  end
  map(buf, "<CR>", function()
    local case = selected()
    if not case then
      return
    end
    local run = case.run or {}
    local details = {
      case.status .. "  " .. case.name .. resources(run),
      "退出码 " .. tostring(run.code or "—") .. "    信号 " .. tostring(run.signal or "—"),
    }
    for _, item in ipairs({
      { "输入", case.input }, { "期望", case.expected }, { "实际", case.actual },
      { "stderr", run.stderr }, { "运行错误", run.error }, { "比较详情", case.diff },
    }) do
      if item[2] and item[2] ~= "" then
        vim.list_extend(details, { "", item[1], item[2] })
      end
    end
    if case.runs then
      for _, name in ipairs({ "generator", "main", "brute", "checker" }) do
        local executed = case.runs[name]
        if executed then
          vim.list_extend(details, {
            "", name .. "  " .. executed.status .. resources(executed),
            "退出码 " .. tostring(executed.code or "—") .. "    信号 " .. tostring(executed.signal or "—"),
            executed.stderr,
          })
        end
      end
    end
    show(case.name, table.concat(details, "\n"), "text", dir)
  end, "查看测试详情")
  map(buf, "d", function()
    local case = selected()
    if case and case.diff and case.diff ~= "" then
      show("输出差异", case.diff, "diff", dir)
    end
  end, "查看输出差异")
  local function jump(direction)
    local start = vim.api.nvim_win_get_cursor(0)[1]
    for i = 1, #lines do
      local row = (start - 1 + i * direction) % #lines + 1
      if rows[row] and rows[row].status ~= "AC" and rows[row].status ~= "OK" then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return
      end
    end
  end
  map(buf, "]e", function() jump(1) end, "下一个失败测试")
  map(buf, "[e", function() jump(-1) end, "上一个失败测试")
  if report.compile then
    map(buf, "c", function() diagnostics(report.compile) end, "打开编译诊断")
  end
  return buf
end

function M.select(entries, prompt, callback)
  if #entries == 0 then
    M.notify("没有匹配的记录", vim.log.levels.INFO)
    return
  end
  vim.ui.select(entries, { prompt = prompt, format_item = function(item)
    return text.display(item.label, 320)
  end }, function(item)
    if item then
      local ok, message = pcall(callback, item)
      if not ok then
        M.notify(tostring(message), vim.log.levels.ERROR)
      end
    end
  end)
end

return M
