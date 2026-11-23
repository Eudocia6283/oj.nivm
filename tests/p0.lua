local oj = require("oj")
local fs = require("oj.core.fs")
local storage = require("oj.storage")
local task = require("oj.core.task")
local root = vim.fn.tempname() .. " 算法 训练"
local messages = {}
vim.notify = function(message)
  messages[#messages + 1] = message
end

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function run()
  -- A failed setup leaves the previous valid configuration available.
  oj.setup({ root = root, limits = { wall_ms = 120 } })
  local events = {}
  vim.api.nvim_create_autocmd("User", {
    pattern = { "OJTaskStart", "OJTaskFinish" },
    callback = function(event)
      events[#events + 1] = { event.match, event.data.kind, event.data.status }
    end,
  })
  assert(not pcall(oj.setup, { root = root, limits = { wall_ms = -2 } }))
  assert(not pcall(oj.setup, { cpp = { flags = "-std=c++20" } }))
  assert(not pcall(oj.setup, false))
  eq(root, oj.config.root)
  vim.cmd("OJImport luogu P1001 " .. vim.fn.getcwd() .. "/tests/fixtures/p1001.json")
  local dir = storage.locate(oj.config, "luogu", "P1001")
  eq(dir .. "/main.cpp", vim.api.nvim_buf_get_name(0))
  eq("A+B Problem", storage.problem(dir).title)
  eq("20 30\n", fs.read(dir .. "/tests/sample1.in", 1024))
  vim.cmd("OJStatement")
  eq("markdown", vim.bo.filetype)
  assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("$a$", 1, true))
  vim.api.nvim_win_close(0, false)

  local function test(source, want)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(source, "\n", { plain = true, trimempty = true }))
    vim.cmd("write")
    local before = #storage.history(dir)
    local message_count = #messages
    vim.cmd("OJTest")
    assert(vim.wait(12000, function()
      return #messages > message_count
    end), table.concat(messages, "\n"))
    local history = storage.history(dir)
    assert(#history == before + 1, table.concat(messages, "\n"))
    local report = fs.json(storage.record_path(dir, history[1].id) .. "/result.json", 1024 * 1024)
    eq(want, report.status)
    print("P0 " .. want)
    return report
  end

  local ac = test([[#include <iostream>
int main() { long long a, b; std::cin >> a >> b; std::cout << a + b << '\n'; }
]], "AC")
  assert(ac.cases[1].run.wall_ms >= 0 and ac.cases[1].run.cpu_user_ms >= 0)
  assert(ac.cases[1].run.peak_rss_kib >= 0)
  local wa = test([[#include <iostream>
int main() { std::cout << 51 << '\n'; }
]], "WA")
  assert(wa.cases[1].diff:find("-50", 1, true) and wa.cases[1].diff:find("+51", 1, true))
  vim.cmd("OJResults")
  local results = vim.api.nvim_get_current_buf()
  assert(vim.fn.maparg("]e", "n", false, true).buffer == 1)
  vim.fn.maparg("]e", "n", false, true).callback()
  vim.fn.maparg("d", "n", false, true).callback()
  eq("diff", vim.bo.filetype)
  vim.api.nvim_win_close(0, false)
  eq(results, vim.api.nvim_get_current_buf())
  vim.api.nvim_win_close(0, false)
  test([[#include <unistd.h>
int main() { while (true) pause(); }
]], "TLE")
  local re = test([[#include <cstdlib>
int main() { std::abort(); }
]], "RE")
  eq(6, re.cases[1].run.signal)
  local ce = test("int main() { return missing_name; }", "CE")
  assert(ce.compile.stderr:find("missing_name", 1, true))
  vim.cmd("OJResults")
  vim.fn.maparg("c", "n", false, true).callback()
  local diagnostics = vim.fn.getqflist()
  assert(#diagnostics > 0)
  eq(dir .. "/main.cpp", vim.api.nvim_buf_get_name(diagnostics[1].bufnr))
  eq(1, diagnostics[1].lnum)
  assert(not task.stop())
  eq(10, #events)
  eq({ "OJTaskStart", "test" }, events[1])
  eq({ "OJTaskFinish", "test", "completed" }, events[10])
end

local ok, message = xpcall(run, debug.traceback)
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(message .. "\n" .. table.concat(messages, "\n") .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
