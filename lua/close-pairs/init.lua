local ts_utils = require "nvim-treesitter.ts_utils"
local pn = require("utils").print_node
local pt = require("utils").print_table

local M = {}

M.inited = false

local settings = {
  mapping = "€"
}

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

local get_master_node_range = function()
  local node = ts_utils.get_node_at_cursor()
  if node == nil then
    local start_line, start_col = 0, 0
    local end_line = vim.fn.line("$") - 1
    local end_col = vim.fn.col({end_line + 1, "$"}) - 1
    return nil, start_line, start_col, end_line, end_col
  end

  local parent = node:parent()
  local root = ts_utils.get_root_for_node(node)

  while (parent ~= nil and parent ~= root) do
    node = parent
    parent = node:parent()
  end

  return node, node:range()
end

M.check_string_node = function(node, curr_line, curr_col)
  for i = 0, node:child_count() - 1, 1 do
    local child = node:child(i)
    if child == nil then
      return nil
    end
    local type = child:type()
    pn(child, true)

    if type:match("string_content") then
      local start_line, start_col, end_line, end_col = child:range()
      local char = string.sub(vim.fn.getline(start_line + 1), start_col, start_col)

      if curr_line ~= end_line + 1 or curr_col - 1 ~= end_col then
        return char
      end
    elseif type:match('["\'`]') and ts_utils.get_previous_node(child, true, true) ~= nil then
      local start_line, start_col, end_line, end_col = child:range()

      if curr_line ~= end_line + 1 or curr_col - 1 ~= end_col then
        return ts_utils.get_node_text(child)[1]
      end
    end

    M.check_string_node(child, curr_line, curr_col)
  end
end

local get_lonely_quote = function(pre_node, curr_line, curr_col)
  -- When in insert mode, ts_utils.get_node_at_cursor() is not working properly.
  -- So we should get a column ahead by selecting from the parent node.
  local node = pre_node:named_descendant_for_range(curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1)
  local curr_type = node:type()

  local quote = M.check_string_node(node, curr_line, curr_col)

  if quote ~= nil then
    return quote
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

local prev_lonely_pair = function(node, curr_line, curr_col, start_line)
  local line_num = curr_line
  local pairs_count = {}

  while line_num > start_line do
    local line = vim.fn.getline(line_num)

    if line_num == curr_line then
      line = string.sub(line, 1, curr_col)
    end

    local off = 1
    for key in line:reverse():gmatch("(.)") do
      -- Check validity of '=' character
      -- when set mps+==:;
      if node ~= nil and key:match("=") then
        local col = 0
        if line_num == curr_line then
          col = curr_col - off
        else
          col = vim.fn.col({line_num, "$"}) - 1 - off
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
          col = curr_col - off
        else
          col = vim.fn.col({line_num, "$"}) - 1 - off
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

local get_char = function(curr_line, curr_col)
  local node, start_line = get_master_node_range()

  -- Check quote character
  if node ~= nil then
    local quote_char = get_lonely_quote(node, curr_line, curr_col)
    if quote_char ~= nil then
      return quote_char
    end
  end

  -- Check match pair
  local prev_lonely = prev_lonely_pair(node, curr_line, curr_col, start_line)
  if prev_lonely ~= nil then
    return prev_lonely
  else
    return nil
  end
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
end

M.try_close = function()
  if not M.inited then
    init()
  end

  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2]
  local char = get_char(curr_line, curr_col)
  local next_char = string.sub(vim.fn.getline(curr_line), curr_col + 1, curr_col + 1)

  if char ~= next_char then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col, curr_line - 1, curr_col, {char})
  end
  vim.api.nvim_win_set_cursor(0, {curr_line, curr_col + 1})
end

return M
