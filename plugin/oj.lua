if vim.g.loaded_oj_nvim or vim.fn.has("nvim-0.10") == 0 then
  return
end
vim.g.loaded_oj_nvim = true
local oj = require("oj")
if not oj.config then
  oj.setup()
end
