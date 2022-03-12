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

local open_pairs_list = {}
local close_pairs_list = {}

local init = function()
  local m_pairs = vim.bo.matchpairs

  for k, v in m_pairs:gmatch("([^,:]+):([^,:]+)") do
    open_pairs_list[k] = v
    close_pairs_list[v] = k
  end

  M.inited = true
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

local prev_lonely_pair = function(start_line, start_column, end_line, end_column)
  local line_num = start_line
  local pairs_count = {}

  while line_num > end_line do
    local line = vim.call("getline", line_num)

    if line_num == start_line then
      line = string.sub(line, 1, start_column)
    end

    for key in line:reverse():gmatch("(.)") do
      local found = find_open_pair(pairs_count, open_pairs_list, key)
      if found then
        return open_pairs_list[key]
      end
      find_close_pair(pairs_count, close_pairs_list, key)
    end

    line_num = line_num - 1
  end
end

local next_lonely_pair = function(start_line, start_column, end_line, end_column)
  local line_num = start_line
  local pairs_count = {}

  while line_num < end_line do
    local line = vim.call("getline", line_num)

    if line_num == start_line then
      line = string.sub(line, start_column + 2)
    end

    for key in line:gmatch("(.)") do
      local found = find_open_pair(pairs_count, close_pairs_list, key)
      if found then
        return close_pairs_list[key]
      end
      find_close_pair(pairs_count, open_pairs_list, key)
    end

    line_num = line_num + 1
  end
end

local get_char = function()
  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2]
  local node = ts_utils.get_node_at_cursor()

  -- Get quote character if the type of current node is 'string'.
  if node:type():match("string") then
    local start_line, start_col = node:start()
    local quote_char = string.sub(vim.call("getline", start_line + 1), start_col + 1, start_col + 1)
    return quote_char
  end

  local prev_lonely = prev_lonely_pair(curr_line, curr_col, 1, 0)
  local next_lonely = next_lonely_pair(curr_line, curr_col, curr_line + 3, 0)
  if close_pairs_list[prev_lonely] ~= next_lonely then
    return prev_lonely
  end
end

M.try_close = function()
  if not M.inited then
    init()
    print("Initialize closing pairs")
  end

  local char = get_char()
  print(char)

  return char
end

return M
