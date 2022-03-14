local ts_utils = require "nvim-treesitter.ts_utils"

local M = {}

M.inited = false
local settings = {
  mapping = ";",
  mapping_original_key = "j;"
}

local open_pairs_list = {}
local close_pairs_list = {}

local print_table = function(table)
  for k, v in pairs(table) do
    print(k .. ": " .. v)
  end
end

local print_node = function(node, show_child)
  print("Current node type: " .. node:type())
  print_table(ts_utils.get_node_text(node, 0))
  if show_child then
    print("Child: ")
    for ch in node:iter_children() do
      print("Type: " .. ch:type())
      print_table(ts_utils.get_node_text(ch, 0))
    end
  end
end

local init = function()
  local m_pairs = vim.bo.matchpairs

  for k, v in m_pairs:gmatch("([^,:]+):([^,:]+)") do
    open_pairs_list[k] = v
    close_pairs_list[v] = k
  end

  M.inited = true
end

local get_master_node_range = function()
  local node = ts_utils.get_node_at_cursor()
  if node == nil then
    start_line, start_col = 0, 0
    end_line = vim.call("line", "$") - 1
    end_col = vim.call("col", {end_line + 1, "$"}) - 1
    return nil, start_line, start_col, end_line, end_col
  end

  local parent = node:parent()
  local start_row = node:start()
  local root = ts_utils.get_root_for_node(node)

  while (parent ~= nil and parent ~= root) do
    node = parent
    parent = node:parent()
  end

  return node, node:range()
end

local get_lonely_quote = function(pre_node, curr_line, curr_column)
  -- When in insert mode, ts_utils.get_node_at_cursor() is not working properly.
  -- So we should get a column ahead by selecting from the parent node.
  -- local parent = pre_node:parent()
  local node = pre_node:named_descendant_for_range(curr_line - 1, curr_column - 1, curr_line - 1, curr_column - 1)
  local curr_type = node:type()

  -- Get quote character if the type of current node has abnormal string content.
  if curr_type:match("string") or curr_type:match("ERROR") then
    for i = 0, node:child_count() - 1, 1 do
      local child = node:child(i)
      local type = child:type()

      local next_child = node:child(i + 1)

      local next_type
      local next_text
      if next_child ~= nil then
        next_type = next_child:type()
        next_text = ts_utils.get_node_text(next_child, 0)[1]
      end

      if type:match("string_content") then
        if next_type ~= "string_end" or (next_type == "string_end" and next_text == "") then
          local line, col = child:start()
          local char = string.sub(vim.call("getline", line + 1), col, col)
          return char
        end
      end
    end
  end
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

local prev_lonely_pair = function(node, curr_line, curr_column, start_line)
  local line_num = curr_line
  local pairs_count = {}

  while line_num > start_line do
    local line = vim.call("getline", line_num)

    if line_num == curr_line then
      line = string.sub(line, 1, curr_column)
    end

    local off = 1
    for key in line:reverse():gmatch("(.)") do
      -- Check validity of = character
      if node ~= nil and key:match("=") then
        local col = 0
        if line_num == curr_line then
          col = curr_column - off
        else
          col = vim.call("col", {line_num, "$"}) - 1 - off
        end
        local key_node = node:named_descendant_for_range(line_num - 1, col - 1, line_num - 1, col - 1)
        if key_node:type():match("assign") or key_node:type():match("declar") then
          goto found
        else
          off = off + 1
          goto continue
        end
      end

      -- Check validity of angled brace
      if node ~= nil and key:match("[<>]") then
        local col = 0
        if line_num == curr_line then
          col = curr_column - off
        else
          col = vim.call("col", {line_num, "$"}) - 1 - off
        end
        local key_node = node:named_descendant_for_range(line_num - 1, col - 1, line_num - 1, col - 1)
        if key_node:type() == "binary_expression" or key_node:type() == "string" then
          off = off + 1
          goto continue
        end
      end

      ::found::
      local found = find_open_pair(pairs_count, open_pairs_list, key)
      if found then
        return open_pairs_list[key]
      end
      find_close_pair(pairs_count, close_pairs_list, key)

      off = off + 1
      ::continue::
    end

    line_num = line_num - 1
  end
end

local get_char = function(curr_line, curr_column)
  local node, start_line, start_col, end_line, end_col = get_master_node_range()

  -- Check quote character
  if node ~= nil then
    local quote_char = get_lonely_quote(node, curr_line, curr_column)
    if quote_char ~= nil then
      return quote_char
    end
  end

  -- Check match pair
  local prev_lonely = prev_lonely_pair(node, curr_line, curr_column, start_line)
  if prev_lonely ~= nil then
    return prev_lonely
  else
    return ";"
  end
end

M.show_node = function()
  local node = ts_utils.get_node_at_cursor()
  print_node(node, true)
end

function M.setup(update)
  if vim.g.close_pairs_loaded then
    return
  end
  vim.g.close_pairs_loaded = true
  settings = vim.tbl_deep_extend("force", settings, update or {})
  vim.api.nvim_set_keymap(
    "i",
    settings.mapping,
    '<cmd>lua require"close-pairs".try_close()<cr>',
    {noremap = true, silent = true}
  )
  vim.api.nvim_set_keymap(
    "i",
    settings.mapping_original_key,
    '<cmd>lua require"close-pairs".send_original()<cr>',
    {noremap = true, silent = true}
  )
  vim.api.nvim_set_keymap(
    "n",
    "<C-f>",
    '<cmd>lua require"close-pairs".show_node()<cr>',
    {noremap = true, silent = true}
  )
end

M.send_original = function()
  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2]

  local mode = vim.api.nvim_get_mode()["mode"]
  if mode == "i" then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col, curr_line - 1, curr_col, {";"})
    vim.api.nvim_win_set_cursor(0, {curr_line, curr_col + 1})
  end
end

M.try_close = function()
  if not M.inited then
    init()
  end

  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2]
  local char = get_char(curr_line, curr_col)

  local mode = vim.api.nvim_get_mode()["mode"]
  if mode == "i" then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col, curr_line - 1, curr_col, {char})
    vim.api.nvim_win_set_cursor(0, {curr_line, curr_col + 1})
  end
end

return M
