local ts_utils = require "nvim-treesitter.ts_utils"
local M = {}

local get_master_node = function()
  local node = ts_utils.get_node_at_cursor()
  if node == nil then
    print("No treesitter node found.")
  end

  print(node)
  -- local start_row = node:start()
  -- local parent = node:parent()
  -- local root = ts_utils.get_root_for_node(node)

  -- while (parent ~= nil and parent ~= root and parent:start() == start_row) do
  -- node = parent
  -- parent = node:parent()
  -- end

  return node
end

-- M.select = function()
-- local node = get_master_node()
-- local bufnr = vim.api.nvim_get_current_buf()
-- -- ts_utils.update_selection(bufnr, node)
-- end

local init = function()
  for pairs in string.gmatch(vim.bo.matchpairs, "[^,]+") do
    for pp in string.gmatch(pairs, "[^:]+") do
      print(pp)
    end
  end
end

M.try_close = function()
  init()
  -- vim.opt.matchpairs
end

return M
