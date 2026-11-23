local uv = vim.uv
local M = {}

-- Keep output pipes alive until EOF, including bytes written just before exit.
-- Each source has a bounded capture, or a caller-provided streaming consumer.
function M.run(task, argv, opts)
  task:check()
  local input = opts.stdin and assert(uv.new_pipe(false))
  local out, err = assert(uv.new_pipe(false)), assert(uv.new_pipe(false))
  local open_streams = 2
  local result = {}
  local chunks = { stdout = {}, stderr = {} }
  local handle, pid
  local timer = assert(uv.new_timer())
  local started = uv.hrtime()

  local function close(resource)
    if resource and not resource:is_closing() then
      resource:close()
    end
  end
  local function finish()
    if result.code == nil or open_streams > 0 then
      return
    end
    close(timer)
    result.wall_ms = (uv.hrtime() - started) / 1000000
    result.stdout = table.concat(chunks.stdout)
    result.stderr = table.concat(chunks.stderr)
    vim.schedule(function()
      task:resume(result)
    end)
  end
  local function terminate()
    if not handle or handle:is_closing() then
      return
    end
    if opts.supervised then
      handle:kill("sigterm")
    else
      if not uv.kill(-pid, 9) then
        handle:kill("sigkill")
      end
    end
  end
  local function read(pipe, key, consume)
    local remaining = opts.output_bytes or 65536
    pipe:read_start(function(read_error, data)
      if read_error then
        result.io_error = tostring(read_error)
        terminate()
      end
      if not data then
        close(pipe)
        open_streams = open_streams - 1
        finish()
        return
      end
      if consume then
        if not result.io_error then
          local ok, message = pcall(consume, data)
          if not ok then
            result.io_error = tostring(message)
            terminate()
          end
        end
      elseif remaining > 0 or not result.output_limited then
        if remaining > 0 then
          chunks[key][#chunks[key] + 1] = data:sub(1, remaining)
        end
        remaining = remaining - #data
        if remaining < 0 then
          result.output_limited = true
          terminate()
        end
      end
    end)
  end

  handle, pid = uv.spawn(argv[1], {
    args = vim.list_slice(argv, 2),
    cwd = opts.cwd,
    env = opts.env,
    stdio = { input or nil, out, err },
    detached = true,
  }, function(code, signal)
    result.code, result.signal = code, signal
    close(handle)
    close(input)
    finish()
  end)
  if not handle then
    close(input)
    close(out)
    close(err)
    close(timer)
    return { spawn_error = tostring(pid), stdout = "", stderr = "" }
  end
  read(out, "stdout", opts.consume_stdout)
  read(err, "stderr")
  if input then
    input:write(opts.stdin, function(write_error)
      if not input:is_closing() then
        if write_error then
          close(input)
        else
          input:shutdown(function()
            close(input)
          end)
        end
      end
    end)
  end
  local function stop()
    terminate()
    -- A lost pipe or an unresponsive supervisor must still release Nvim.
    if timer:is_closing() then
      return
    end
    timer:start(2000, 0, function()
      if handle and not handle:is_closing() then
        handle:kill("sigkill")
      end
      for _, pipe in ipairs({ out, err }) do
        if not pipe:is_closing() then
          close(pipe)
          open_streams = open_streams - 1
        end
      end
      finish()
    end)
  end
  timer:start(opts.timeout_ms, 0, function()
    result.timed_out = true
    stop()
  end)
  return task:await(stop)
end

return M
