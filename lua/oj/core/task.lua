local M = {}
local active
local cancelled = {}

local function emit(pattern, data)
  local ok, message = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = pattern, data = data, modeline = false,
  })
  if not ok then
    vim.notify(tostring(message), vim.log.levels.WARN)
  end
end

function M.is_cancelled(reason)
  return reason == cancelled
end

function M.stop(kind)
  if not active or (kind and active.kind ~= kind) then
    return false
  end
  if not active.cancelled then
    active.cancelled = true
    if active.interrupt then
      active.interrupt()
    end
  end
  return true
end

function M.start(kind, run, done)
  assert(not active, "已有 OJ 任务运行。用 :OJStop 取消")
  local task = { kind = kind, cancelled = false, cleanup = {} }
  function task:check()
    if self.cancelled then
      error(cancelled, 0)
    end
  end
  function task:await(start)
    self:check()
    self.interrupt = start
    local value = coroutine.yield()
    self.interrupt = nil
    self:check()
    return value
  end
  function task:defer(fn)
    self.cleanup[#self.cleanup + 1] = fn
  end
  local thread = coroutine.create(function()
    task:check()
    return run(task)
  end)
  function task:resume(value)
    if active ~= self then
      return
    end
    local ok, result = coroutine.resume(thread, value)
    if not ok or coroutine.status(thread) == "dead" then
      active = nil
      for i = #self.cleanup, 1, -1 do
        local cleaned, message = pcall(self.cleanup[i])
        if not cleaned then
          vim.notify(tostring(message), vim.log.levels.WARN)
        end
      end
      done(ok, result)
      emit("OJTaskFinish", {
        kind = kind,
        status = ok and "completed" or (M.is_cancelled(result) and "cancelled" or "error"),
      })
    end
  end
  active = task
  emit("OJTaskStart", { kind = kind })
  vim.schedule(function()
    task:resume()
  end)
  return task
end

return M
