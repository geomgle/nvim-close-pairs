local M = {}

M.print_table = function(table)
  for k, v in pairs(table) do
    print(k .. ": " .. v)
  end
end

M.print_node = function(node, show_child)
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

return M
