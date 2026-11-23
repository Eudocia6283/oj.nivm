local providers = require("oj.providers")
local ui = require("oj.ui")
local M = {}

function M.open(problem)
  local adapter = providers.get(problem.platform)
  assert(adapter.submission_url, "该平台未配置浏览器提交入口")
  local url = adapter.submission_url(problem.id)
  local process, message = vim.ui.open(url)
  if process then
    ui.notify("请在浏览器登录并提交。该平台的自动提交未启用")
  else
    ui.notify("打开浏览器失败 " .. tostring(message) .. "。提交入口 " .. url, vim.log.levels.WARN)
  end
end

return M
