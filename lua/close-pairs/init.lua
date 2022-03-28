local ts_utils = require "nvim-treesitter.ts_utils"
local pn = require("utils").print_node
local pt = require("utils").print_table

local M = {}

M.inited = false

local settings = {
  mapping = "<C-j>",
  default_key = ";"
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

M.remove_pairs = function(str)
  local prev_str = str
  str = str:gsub("<>", "")
  str = str:gsub("%(%)", "")
  str = str:gsub("%{%}", "")
  str = str:gsub("%[%]", "")

  if prev_str == str then
    return str
  end

  return M.remove_pairs(str)
end

local find_lonely_pairs = function(str)
  str = str:gsub('\\["\'`]', "")
  str = str:gsub("[%s%-=][<>]", "")
  str = str:gsub("[<>][%-=]", "")
  str = str:gsub('[%d%a%s%%%-%~%^.,;:&!?_=+"\'`]', "")
  str = M.remove_pairs(str)
  return str
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

local divide = function(master, curr_line, curr_col)
  local m_sl, m_sc, m_el, m_ec = master:range()

  local front_content = get_content(m_sl + 1, m_sc, curr_line, curr_col - 1)
  local back_content = get_content(curr_line, curr_col + 1, m_el + 1, m_ec)

  return front_content, back_content
end

M.recur = function(master, curr_line, curr_col)
  local front_content, back_content = divide(master, curr_line, curr_col)
  local front = find_lonely_pairs(front_content)
  local back = find_lonely_pairs(back_content)

  -- print("Front: ", front, "\nBack: ", back)
  if front ~= nil and front ~= "" then
    for open in front:reverse():gmatch("(.)") do
      if back == nil or back == "" then
        return pairs_list[open]
      end

      for close in back:gmatch("(.)") do
        if pairs_list[open] ~= close then
          return pairs_list[open]
        end
      end
    end
  end
end

M.try_close = function()
  if not M.inited then
    init()
  end

  local curr_line = vim.api.nvim_win_get_cursor(0)[1]
  local curr_col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local curr_node = ts_utils.get_node_at_cursor(0)
  local node = curr_node:descendant_for_range(curr_line - 1, curr_col - 2, curr_line - 1, curr_col - 2)
  local master = get_master_node(node)

  local char
  if node == nil then
    print("node is nil!")
    return nil
  elseif node:type() == "string_content" then
    char = ts_utils.get_node_text(node:prev_sibling())[1]
  else
    char = M.recur(master, curr_line, curr_col)
  end

  local next_char = get_line(curr_line, curr_col, curr_col)

  if char == nil then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1, {settings.default_key})
  elseif char ~= next_char then
    vim.api.nvim_buf_set_text(0, curr_line - 1, curr_col - 1, curr_line - 1, curr_col - 1, {char})
  end
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
end

return M
