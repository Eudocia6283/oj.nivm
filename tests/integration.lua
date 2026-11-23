local oj = require("oj")
local fs = require("oj.core.fs")
local storage = require("oj.storage")
local uv = vim.uv
local root = vim.fn.tempname() .. " 算法 工作区"
local messages = {}
vim.notify = function(message, level)
  messages[#messages + 1] = { message, level }
end

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function replace(path, contents)
  if fs.check(path, "file", true) then
    assert(uv.fs_unlink(path))
  end
  fs.write_new(path, contents)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_get_current_buf() == buf then
    vim.cmd("silent edit!")
  end
end

local function wait_for(predicate, name, timeout)
  assert(vim.wait(timeout or 15000, predicate, 5), "timeout " .. name)
end

local function notice(after, needle, timeout)
  wait_for(function()
    for i = after + 1, #messages do
      if messages[i][1]:find(needle, 1, true) then
        return true
      end
    end
  end, needle, timeout)
end

local function report(dir, command, status, timeout)
  local start = #messages
  local before = #storage.history(dir)
  vim.cmd(command)
  notice(start, "（本地）", timeout)
  local history = storage.history(dir)
  eq(before + 1, #history)
  local folder = storage.record_path(dir, history[1].id)
  local result = fs.json(folder .. "/result.json", 1024 * 1024)
  eq(status, result.status)
  return result, folder
end

local function await_workspace(id, command)
  local dir = storage.locate(oj.config, "luogu", id)
  vim.cmd(command)
  wait_for(function() return fs.check(dir .. "/metadata.json", "file", true) end, id)
  vim.cmd("OJOpen " .. id)
  eq(dir .. "/main.cpp", vim.api.nvim_buf_get_name(0))
  return dir
end

local function assert_reaped(file)
  local contents = fs.read(file, 256)
  local count = 0
  for pid in contents:gmatch("%d+") do
    local ok, _, code = uv.kill(tonumber(pid), 0)
    assert(not ok and code == "ESRCH", "仍有存活或未回收的进程 " .. pid)
    count = count + 1
  end
  eq(2, count)
end

local function descendant_program(marker)
  return ([[
#include <fstream>
#include <unistd.h>

int main() {
    pid_t child = fork();
    if (child < 0) return 3;
    if (child == 0) {
        if (setsid() < 0) return 4;
        while (true) pause();
    }
    std::ofstream file(R"PID(%s)PID");
    file << getpid() << ' ' << child << '\n';
    file.close();
    while (true) pause();
}
]]):format(marker)
end

local function run()
  fs.mkdir(root)
  local dataset = root .. "/样例  官方导出结构.ndjson"
  local export = {
    pid = "P1001", title = "A+B Problem", background = "用于验收的本地数据",
    description = "求两个整数的和。范围是 $10^9$。\n\n```cpp\n// 代码块\n```",
    inputFormat = "两个整数", outputFormat = "一个整数", difficulty = 1, tags = { "入门", 12 },
    limits = { time = { 500, 1000 }, memory = { 32768, 65536 } }, samples = { { "20 30\n", "50\n" } },
  }
  -- Deliberately place the target across several UV reads and omit the last newline.
  local other = { pid = "P1024", title = "批处理", description = string.rep("x", 266000) }
  local extra = { pid = "P1026", title = "同步缓存入口" }
  fs.write_new(dataset, table.concat({ vim.json.encode(other), vim.json.encode(extra), vim.json.encode(export) }, "\n"))
  oj.setup({ root = root, luogu = { dataset = dataset }, limits = { wall_ms = 350 } })
  local dir = await_workspace("P1001", "OJOpen https://www.luogu.com.cn/problem/P1001?lang=zh-CN")
  local problem = storage.problem(dir)
  eq("luogu-open-export", problem.origin)
  eq(1000, problem.time_limit_ms)
  eq(65536, problem.memory_limit_kib)
  eq({ "入门", "12" }, problem.tags)
  eq("50\n", fs.read(dir .. "/tests/sample1.out", 1024))
  assert(fs.read(dir .. "/problem.md", 8192):find("```cpp\n// 代码块", 1, true))

  local archive = root .. "/中文  导出.ndjson.gz"
  local pack = vim.system({ "gzip", "-c", "--", dataset }):wait()
  eq(0, pack.code)
  fs.write_new(archive, pack.stdout)
  local other_dir = await_workspace("P1024", "OJImport 1024 " .. archive)
  eq(0, #storage.problem(other_dir).samples)

  local broken = root .. "/损坏.ndjson.gz"
  fs.write_new(broken, pack.stdout:sub(1, -5))
  local start = #messages
  vim.cmd("OJImport P1025 " .. broken)
  notice(start, "解压洛谷导出失败")
  assert(not fs.kind(storage.locate(oj.config, "luogu", "P1025")))
  -- Exercise the real command, gzip validation and atomic cache publish with
  -- a fixture-driven transport. The production command still pins the URL.
  local bin = fs.mkdir(root .. "/模拟下载")
  local curl = bin .. "/curl"
  fs.write_new(curl, [[#!/usr/bin/env python3
import os, shutil, sys
args = sys.argv[1:]
assert args[0] == "-q"
assert args[args.index("--url") + 1] == "https://cdn.luogu.com.cn/problemset-open/latest.ndjson.gz"
shutil.copyfile(os.environ["OJ_TEST_SYNC_SOURCE"], args[args.index("--output") + 1])
]])
  assert(uv.fs_chmod(curl, tonumber("700", 8)))
  local path = vim.env.PATH
  vim.env.PATH = bin .. ":" .. path
  vim.env.OJ_TEST_SYNC_SOURCE = archive
  start = #messages
  vim.cmd("OJLuoguSync")
  notice(start, "官方导出已缓存")
  local cached = root .. "/config/luogu-open.ndjson.gz"
  eq(pack.stdout, fs.read(cached, 1024 * 1024))
  vim.env.OJ_TEST_SYNC_SOURCE = broken
  start = #messages
  vim.cmd("OJLuoguSync")
  notice(start, "解压洛谷导出失败")
  eq(pack.stdout, fs.read(cached, 1024 * 1024))
  vim.env.PATH = path
  vim.env.OJ_TEST_SYNC_SOURCE = nil
  oj.setup({ root = root, limits = { wall_ms = 350 } })
  await_workspace("P1026", "OJOpen P1026")
  assert(uv.fs_unlink(cached))
  assert(uv.fs_unlink(dataset))
  assert(uv.fs_unlink(archive))

  vim.cmd("OJOpen P1001")
  local selected
  vim.ui.select = function(items, _, choose)
    selected = items
    choose(items[1])
  end
  vim.cmd("OJSearch 代码块")
  wait_for(function() return selected ~= nil end, "全文检索")
  eq(1, #selected)
  eq(dir, selected[1].dir)
  selected = nil
  vim.cmd("OJList")
  wait_for(function() return selected ~= nil end, "本地题库列表")
  eq(3, #selected)
  vim.cmd("OJNotes")
  eq(dir .. "/notes.md", vim.api.nvim_buf_get_name(0))
  vim.api.nvim_buf_set_lines(0, 1, -1, false, { "离线笔记" })
  vim.cmd("silent write")
  vim.api.nvim_win_close(0, false)
  assert(fs.read(dir .. "/notes.md", 1024):find("离线笔记", 1, true))
  local submitted_url
  vim.ui.open = function(url)
    submitted_url = url
    return {}
  end
  vim.cmd("OJSubmit")
  eq("https://www.luogu.com.cn/problem/P1001#submit", submitted_url)

  local input, output = root .. "/输入 空格.in", root .. "/输出 空格.out"
  fs.write_new(input, "-7 9\n")
  fs.write_new(output, "2\n")
  vim.cmd("OJTestAdd negative " .. vim.fn.fnameescape(input) .. " " .. vim.fn.fnameescape(output))
  eq("2\n", fs.read(dir .. "/tests/negative.out", 1024))
  for _, item in ipairs({ { "solution.cpp", "main.cpp" }, { "brute.cpp", "brute.cpp" }, { "gen.cpp", "gen.cpp" } }) do
    replace(dir .. "/" .. item[2], fs.read("tests/fixtures/" .. item[1], 4096))
  end
  local offline = report(dir, "OJTest", "AC")
  eq(2, #offline.cases)
  local direct = report(dir, "OJRun " .. vim.fn.fnameescape(input), "OK")
  eq("2\n", direct.cases[1].actual)
  eq(nil, direct.cases[1].expected)
  print("P1 NDJSON/gzip、模拟同步与失败回滚、Unicode、离线搜索和样例/自定义用例通过")

  local t = uv.hrtime()
  local pass = report(dir, "OJStress 1000 123456", "AC", 90000)
  eq(1000, pass.passed)
  print(string.format("P1 对拍 %d 次通过 · %.2f 秒", pass.passed, (uv.hrtime() - t) / 1e9))

  replace(dir .. "/main.cpp", [[#include <iostream>
int main() { std::cerr << "debug\n"; std::cout << "incorrect\n"; }
]])
  local fail, artifacts = report(dir, "OJStress 12 123456", "WA")
  eq(0, fail.passed)
  eq(123456, fail.case_seed)
  assert(fail.cases[1].diff:find("+incorrect", 1, true))
  eq("incorrect\n", fs.read(artifacts .. "/main.out", 1024))
  eq("debug\n", fs.read(artifacts .. "/main.stderr", 1024))
  eq("", fs.read(artifacts .. "/brute.stderr", 1024))
  eq(0, fail.cases[1].runs.main.code)
  eq(0, fail.cases[1].runs.brute.signal)
  assert(#fs.read(artifacts .. "/input.in", 1024) > 0)
  local repeated, repeated_files = report(dir, "OJStress 1 123456", "WA")
  eq(123456, repeated.case_seed)
  eq(fs.read(artifacts .. "/input.in", 1024), fs.read(repeated_files .. "/input.in", 1024))
  eq(fail.id, report(dir, "OJReplay " .. fail.id, "WA").replayed_id)
  print("P1 WA 首轮停止、保存原始输出和退出状态、同种子复现、归档输入重放通过")

  local timed_marker = root .. "/timeout.pids"
  replace(dir .. "/main.cpp", descendant_program(timed_marker))
  local tle = report(dir, "OJTest sample1", "TLE")
  eq("wall", tle.cases[1].run.limit)
  assert_reaped(timed_marker)

  local cancel_marker = root .. "/cancel.pids"
  replace(dir .. "/gen.cpp", descendant_program(cancel_marker))
  oj.setup({ root = root, limits = { wall_ms = 10000 } })
  local notifications = #messages
  vim.cmd("OJStress 1 12")
  wait_for(function() return fs.check(cancel_marker, "file", true)
    and fs.read(cancel_marker, 256):match("%d+ %d+") end, "进程派生")
  local edited = vim.api.nvim_create_buf(false, true)
  local editor_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(editor_win, edited)
  vim.defer_fn(function()
    local keys = vim.api.nvim_replace_termcodes("i评测期间仍可编辑<Esc>", true, false, true)
    vim.api.nvim_feedkeys(keys, "nx", false)
  end, 60)
  wait_for(function()
    local line = vim.api.nvim_buf_get_lines(edited, 0, 1, false)[1]
    return line == "评测期间仍可编辑"
  end, "编辑操作")
  for pid in fs.read(cancel_marker, 256):gmatch("%d+") do
    assert(uv.kill(tonumber(pid), 0), "异步编辑时进程应仍在运行")
  end
  vim.cmd("OJStressStop")
  notice(notifications, "任务已取消")
  assert_reaped(cancel_marker)
  eq("评测期间仍可编辑", vim.api.nvim_buf_get_lines(edited, 0, 1, false)[1])
  vim.bo[edited].modified = false
  vim.cmd("OJOpen P1001")
  print("P1 派生进程超时及取消回收、任务期间编辑通过")

  local settings = dir .. "/settings.json"
  replace(settings, '{"iterations":0}')
  start = #messages
  vim.cmd("OJStress")
  notice(start, "iterations 必须")
  replace(settings, '{"generator":"gen.py","seed":4294967295,"iterations":2,"compare":"tokens"}')
  fs.write_new(dir .. "/gen.py", "import sys\nprint(int(sys.argv[1]) % 17, -2)\n")
  replace(dir .. "/main.cpp", fs.read("tests/fixtures/solution.cpp", 4096))
  local py = report(dir, "OJStress", "AC")
  eq(2, py.passed)
  eq(4294967295, py.seed)

  local checker = root .. "/自定义 判题.py"
  fs.write_new(checker, [[import pathlib, sys
test, expected, actual = map(pathlib.Path, sys.argv[1:])
assert test.is_file() and expected.is_file() and actual.is_file()
sys.exit(0 if int(actual.read_text()) == int(expected.read_text()) + 1 else 1)
]])
  replace(dir .. "/main.cpp", [[#include <iostream>
int main() { std::cout << 51; }
]])
  oj.setup({ root = root, checker = { "python3", checker } })
  eq("OK", report(dir, "OJTest sample1", "AC").cases[1].checker.status)
  eq(1, report(dir, "OJTest negative", "WA").cases[1].checker.code)
  print("P2 Python 生成器、高位种子、题目配置校验、自定义 checker 通过")

  oj.setup({ root = root, limits = { wall_ms = 350, output_kib = 32 } })
  replace(dir .. "/main.cpp", [[#include <unistd.h>
int main() { char output[4096]{}; for (;;) write(1, output, sizeof output); }
]])
  assert(report(dir, "OJTest sample1", "OLE").cases[1].run.output_limited)
  oj.setup({ root = root, limits = { wall_ms = 3000, cpu_seconds = 1 } })
  replace(dir .. "/main.cpp", "int main() { volatile unsigned i=0; while (true) i = i + 1; }\n")
  eq("cpu", report(dir, "OJTest sample1", "TLE").cases[1].run.limit)

  replace(dir .. "/main.cpp", [[#include <cstdio>
#include <new>

int main() {
    auto bytes = new (std::nothrow) unsigned char[12 * 1024 * 1024];
    if (!bytes) return 7;
    volatile unsigned char* pages = bytes;
    for (int i = 0; i < 12 * 1024 * 1024; i += 4096) pages[i] = 50;
    std::printf("%u\n", static_cast<unsigned>(pages[0]));
    delete[] bytes;
}
]])
  oj.setup({ root = root, cpp = { flags = { "-std=c++17", "-O2" } }, limits = { memory_mib = 64 } })
  assert(report(dir, "OJTest sample1", "AC").cases[1].run.peak_rss_kib >= 9000)
  oj.setup({ root = root, limits = { memory_mib = 10 } })
  eq(7, report(dir, "OJTest sample1", "RE").cases[1].run.code)

  start = #messages
  vim.cmd("OJNew ../../P1002")
  notice(start, "无效的洛谷题号")
  start = #messages
  vim.cmd("OJOpen https://www.luogu.com.cn.example.org/problem/P1001")
  notice(start, "需要洛谷 HTTPS")
  start = #messages
  vim.cmd("OJTestAdd negative")
  notice(start, "测试已存在")
  local target = storage.locate(oj.config, "luogu", "P1002")
  assert(uv.fs_symlink(other_dir, target))
  start = #messages
  vim.cmd("OJOpen P1002")
  notice(start, "需要目录")
  eq("批处理", storage.problem(other_dir).title)
  oj.setup({ root = root, template = "我的模板.cpp" })
  fs.write_new(root .. "/templates/我的模板.cpp", "int main() { return 0; }\n")
  local fresh = await_workspace("P1003", "OJNew luogu P1003")
  eq("int main() { return 0; }\n", fs.read(fresh .. "/main.cpp", 1024))
  print("P1 输出/CPU/地址空间上限、峰值 RSS、路径遍历/恶意 URL/符号链接与覆盖检查通过")
end

local ok, message = xpcall(run, debug.traceback)
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(message .. "\n")
  for _, item in ipairs(messages) do
    io.stderr:write(item[1] .. "\n")
  end
  vim.cmd("cquit")
end
vim.cmd("qa!")
