local uv = vim.uv
local M = {}

function M.kind(path)
  local stat, message, code = uv.fs_lstat(path)
  assert(stat or code == "ENOENT", message)
  return stat and stat.type
end

function M.check(path, kind, optional)
  local actual = M.kind(path)
  assert(actual == kind or (optional and actual == nil), "需要" .. (kind == "file" and "普通文件 " or "目录 ") .. path)
  return actual ~= nil
end

function M.mkdir(path)
  if not M.check(path, "directory", true) then
    local ok, message, code = uv.fs_mkdir(path, 448) -- 0700
    assert(ok or code == "EEXIST", message)
    M.check(path, "directory")
  end
  return path
end

function M.read(path, limit)
  M.check(path, "file")
  local fd = assert(uv.fs_open(path, "r", 0))
  local ok, result = pcall(function()
    assert(assert(uv.fs_fstat(fd)).type == "file", "需要普通文件 " .. path)
    local data = assert(uv.fs_read(fd, limit + 1, 0))
    assert(#data <= limit, "文件大小超出上限 " .. path)
    return data
  end)
  uv.fs_close(fd)
  if not ok then
    error(result, 0)
  end
  return result
end

function M.write_new(path, data)
  local fd, tmp = uv.fs_mkstemp(vim.fs.dirname(path) .. "/.write-XXXXXX")
  assert(fd, tmp)
  local ok, message = pcall(function()
    local offset = 0
    while offset < #data do
      local count = assert(uv.fs_write(fd, data:sub(offset + 1), offset))
      assert(count > 0, "写入失败 " .. path)
      offset = offset + count
    end
  end)
  local closed, close_error = uv.fs_close(fd)
  if ok and closed then
    ok, message = uv.fs_link(tmp, path)
  end
  uv.fs_unlink(tmp)
  assert(closed, close_error)
  assert(ok, message)
end

function M.stage(parent, prefix, build)
  local dir = assert(uv.fs_mkdtemp(parent .. "/." .. prefix .. "-XXXXXX"))
  local ok, result = xpcall(function()
    return build(dir)
  end, debug.traceback)
  if not ok then
    vim.fn.delete(dir, "rf")
    error(result, 0)
  end
  return result
end

function M.entries(dir)
  local scan = assert(uv.fs_scandir(dir))
  return function()
    return uv.fs_scandir_next(scan)
  end
end

function M.json(path, limit)
  local ok, value = pcall(vim.json.decode, M.read(path, limit))
  assert(ok and type(value) == "table", "无效的 JSON 文件 " .. path)
  return value
end

function M.write_json(path, value)
  M.write_new(path, vim.json.encode(value) .. "\n")
end

return M
