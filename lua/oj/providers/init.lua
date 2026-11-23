local M = {}
local adapters = { luogu = require("oj.providers.luogu") }

-- An adapter supplies identify(ref) and source_url(id). Import capabilities
-- are optional and receive an async task, never an editor window.
function M.get(name)
  return assert(adapters[name], "未知题目平台 " .. tostring(name))
end

function M.identify(arguments)
  local explicit = arguments[1] and adapters[arguments[1]] ~= nil
  local platform = explicit and arguments[1] or "luogu"
  local index = explicit and 2 or 1
  return platform, M.get(platform).identify(arguments[index]), index
end

function M.register(name, adapter)
  assert(require("oj.core.problem").component(name), "无效的平台名")
  assert(type(adapter) == "table" and type(adapter.identify) == "function" and type(adapter.source_url) == "function",
    "Provider 需要 identify 和 source_url")
  assert(not adapters[name], "平台已注册 " .. name)
  adapters[name] = adapter
end

return M
