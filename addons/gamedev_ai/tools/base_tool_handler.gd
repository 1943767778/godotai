@tool
extends RefCounted
class_name BaseToolHandler

var executor: RefCounted

func setup(_executor: RefCounted):
	executor = _executor

func execute(tool_name: String, args: Dictionary) -> bool:
	# Override this method
	return false

# --- Helper Methods ---

func _emit_output(msg: String):
	if executor:
		executor.tool_output.emit(msg)

func _request_confirmation(msg: String, tool_name: String, args: Dictionary):
	if executor:
		executor._pending_confirm_tool = tool_name
		executor._pending_confirm_args = args
		executor.confirmation_needed.emit(msg, tool_name, args)

func _request_diff_preview(path: String, old_content: String, new_content: String, tool_name: String, args: Dictionary):
	if executor:
		executor._pending_diff_path = path
		executor._pending_diff_old_content = old_content
		executor._pending_diff_new_content = new_content
		executor._pending_confirm_tool = tool_name
		executor._pending_confirm_args = args
		executor.diff_preview_requested.emit(path, old_content, new_content, tool_name, args)

func _get_undo_redo() -> EditorUndoRedoManager:
	if executor and "_undo_redo" in executor:
		return executor._undo_redo
	return null

func _is_composite() -> bool:
	if executor and "_composite_action_name" in executor:
		return executor._composite_action_name != ""
	return false

func _has_undo() -> bool:
	return _get_undo_redo() != null


func _list_node_paths(root: Node, max_depth: int = 3) -> Array:
	var result: Array = []
	var stack: Array = [[root, 0]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var n: Node = item[0]
		var d: int = item[1]
		if d > 0:
			result.append(str(root.get_path_to(n)))
		if d < max_depth:
			for c in n.get_children():
				stack.append([c, d + 1])
	return result
