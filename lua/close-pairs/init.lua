local ts_utils = require "nvim-treesitter.ts_utils"
local M = {}
M.inited = false

local table_print = function(table)
  for k, v in pairs(table) do
    print(k .. ": " .. v)
  end
end

local get_master_node = function()
  local node = ts_utils.get_node_at_cursor()
  if node == nil then
    print("No treesitter node found.")
  end

  local start_row = node:start()
  local parent = node:parent()
  local root = ts_utils.get_root_for_node(node)

  while (parent ~= nil and parent ~= root) do
    node = parent
    parent = node:parent()
  end

  return node
end

local get_root_node = function(node)
  -- local node = ts_utils.get_node_at_cursor()
  local root = ts_utils.get_root_for_node(node)
  return root
end

local init = function()
  local m_pairs = vim.bo.matchpairs
  local open_list = {}
  local close_list = {}

  for k, v in m_pairs:gmatch("([^,:]+):([^,:]+)") do
    open_list[k] = v
    close_list[v] = k
  end

  M.inited = true
  return open_list, close_list
end

M.select = function()
  local node = get_master_node():prev_sibling()
  local bufnr = vim.api.nvim_get_current_buf()
  for n in node:iter_children() do
    print(n)
  end
  ts_utils.update_selection(bufnr, node)
end

local find_open_pair = function(pairs_count, pairs_list, key)
  if pairs_list[key] ~= nil then
    if pairs_count[key] == nil or pairs_count[key] == 0 then
      return true
    else
      pairs_count[key] = pairs_count[key] - 1
    end
  end
  return false
end

local find_close_pair = function(pairs_count, pairs_list, key)
  if pairs_list[key] ~= nil then
    local value = pairs_list[key]
    if pairs_count[value] == nil then
      pairs_count[value] = 1
    else
      pairs_count[value] = pairs_count[value] + 1
    end
  end
end

local get_char = function()
  local node = ts_utils.get_node_at_cursor()
  local open_pairs_list, close_pairs_list = init()

  local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line_num = current_line_num
  local pairs_count = {}

  while line_num > 0 do
    local line = vim.call("getline", line_num)

    local last_pos = 0
    if line_num == current_line_num then
      last_pos = vim.call("col", ".") - 1
    else
      last_pos = vim.call("col", {line_num, "$"}) - 1
    end

    if last_pos == -1 then
      goto continue
    end

    for key in line:reverse():gmatch("(.)") do
      local found = find_open_pair(pairs_count, open_pairs_list, key)
      if found then
        print(open_pairs_list[key])
        return open_pairs_list[key]
      end
      find_close_pair(pairs_count, close_pairs_list, key)
    end

    ::continue::
    line_num = line_num - 1
  end
end

M.try_close = function()
  local char = get_char()

  return char
end

return M
