local ts_utils = require "nvim-treesitter.ts_utils"
-- local pn = require("utils").print_node
-- local pt = require("utils").print_table

local M = {}

M.inited = false

local settings = {
  mapping = ";",
  send_original_key = "j;"
}

local pairs_list = {}

local init = function()
  local m_pairs = vim.bo.matchpairs

  for k, v in m_pairs:gmatch("([^,:]+):([^,:]+)") do
    pairs_list[k] = v
  end

  M.inited = true
end

local get_line = function(line, start_col, end_col)
  if start_col == nil then
    return vim.fn.getline(line)
  else
    return vim.fn.getline(line):sub(start_col, end_col)
  end
end

local line_content = function(line, start_line, start_col, end_line, end_col)
  local line_content
  if line == start_line and line == end_line then
    line_content = get_line(line, start_col, end_col)
  elseif line == start_line then
    line_content = get_line(line, start_col)
  elseif line == end_line then
    line_content = get_line(line, 1, end_col)
  else
    line_content = get_line(line)
  end
  return line_content
end

local get_master_node = function(node)
  local parent = node:parent()
  local root = ts_utils.get_root_for_node(node)

  while (parent ~= nil and parent ~= root) do
    node = parent
    parent = node:parent()
  end

  return node
end

local get_content = function(start_line, start_col, end_line, end_col)
  local contents = ""

  local line_num = start_line
  while line_num <= end_line do
    local line = line_content(line_num, start_line, start_col, end_line, end_col)
    contents = contents .. line

    line_num = line_num + 1
  end

  return contents
end

local cut_master_by_cursor = function(master, curr_line, curr_col)
  local m_sl, m_sc, m_el, m_ec = master:range()

  local front_content = get_content(m_sl + 1, m_sc, curr_line, curr_col - 1)
  local back_content = get_content(curr_line, curr_col + 1, m_el + 1, m_ec)

  return front_content, back_content
end

M.remove_coupled_pairs = function(str)
  local prev_str = str
  if pairs_list["<"] ~= nil then
    str = str:gsub("<>", "")
  end
  str = str:gsub("%(%)", "")
  str = str:gsub("%{%}", "")
  str = str:gsub("%[%]", "")

  if prev_str == str then
    return str
  end

  return M.remove_coupled_pairs(str)
end

local find_pairs = function(str)
  str = str:gsub('\\["\'`]', "")
  str = str:gsub("%s[<>]%s", "")
  if pairs_list["<"] ~= nil then
    str = str:gsub("%s[%-=][<>]%s", "")
    str = str:gsub("%s[<>][%-=]%s", "")
    str = str:gsub("%s+>>", "")
    str = str:gsub("<<%s+", "")
  else
    str = str:gsub("[<>]", "")
  end
  str = str:gsub("[^%[%]%{%}%(%)<>]", "")
  str = M.remove_coupled_pairs(str)
  return str
end

local find_lonely_pair = function(master, curr_line, curr_col)
  local front_content, back_content = cut_master_by_cursor(master, curr_line, curr_col)
  local front = find_pairs(front_content):reverse()
  local back = find_pairs(back_content)
  if #front > #back then
    back = string.rep(" ", #front - #back) .. back
  end

  -- print("Front: ", front, "\nBack: ", back)
  if front ~= nil and front ~= "" then
    for i = 1, #front, 1 do
      local f_char = front:sub(i, i)
      local b_char = back:sub(i, i)
      if pairs_list[f_char] ~= b_char then
        return pairs_list[f_char]
      end
    end
  end
end

M.find_last_pair = function(curr_line, curr_col)
  local line = get_line(curr_line, 1, curr_col):reverse()
  local pair = line:find("[%[%(%{]")
  if pair == nil then
    curr_line = curr_line - 1
    curr_col = vim.fn.col({curr_line, "$"})
    return M.find_last_pair(curr_line)
  else
    return pairs_list[line:sub(pair, pair)]
  end
end

local get_char = function(curr_line, curr_col)
  local node
  local curr_node = ts_utils.get_node_at_cursor(0)
  if curr_node == nil then
    return nil
  else
    node = curr_node:descendant_for_range(curr_line - 1, curr_col - 2, curr_line - 1, curr_col - 2)
  end

  local master = get_master_node(node)
  -- pn(node, true)

  local char
  local type = node:type()
  if type == "string_content" then
    local start_line, start_col = node:range()
    char = get_line(start_line + 1, start_col, start_col)
  elseif type:match("string") and type ~= "string_end" then
    char = ts_utils.get_node_text(node:child(0))[1]
  elseif type == "ERROR" then
    char = M.find_last_pair(curr_line, curr_col)
    return char
  else
    char = find_lonely_pair(master, curr_line, curr_col)
  end

  return char
end

M.try_close = function()
  if not M.inited then
    init()
  end

  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2] + 1

  local char = get_char(curr_line, curr_col)
  local next_char = get_line(curr_line, curr_col, curr_col)
  -- print(char, next_char)

  if char == nil then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1, {settings.mapping})
  elseif char ~= next_char then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1, {char})
  end
  vim.api.nvim_win_set_cursor(0, {curr_line, curr_col})
end

M.send_original = function()
  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2] + 1

  vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1, {settings.mapping})
  vim.api.nvim_win_set_cursor(0, {curr_line, curr_col})
end

function M.setup()
  if vim.g.close_pairs_loaded then
    return
  end
  vim.g.close_pairs_loaded = true

  vim.api.nvim_set_keymap(
    "i",
    settings.mapping,
    '<cmd>lua require"close-pairs".try_close()<cr>',
    {noremap = true, silent = true}
  )
  if settings.send_original_key ~= nil then
    vim.api.nvim_set_keymap(
      "i",
      settings.send_original_key,
      '<cmd>lua require"close-pairs".send_original()<cr>',
      {noremap = true, silent = true}
    )
  end
end

return M
