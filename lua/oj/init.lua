local config = require("oj.core.config")
local M = {}

function M.setup(opts)
  assert(vim.fn.has("nvim-0.10") == 1, "oj.nvim 需要 Neovim 0.10 或更高版本")
  local validated = config.make(opts)
  require("oj.commands").register()
  M.config = validated
end

return M
