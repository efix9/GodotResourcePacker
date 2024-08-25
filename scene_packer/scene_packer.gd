@tool
extends EditorPlugin

const SEARCH_MODE_TITLE = "Dependency Search Mode"
const SEARCH_MODE_PARAMS = [
	"Recursive", 
	"Scenes & Dependencies", 
	"Scenes & Root Dependencies", 
	"Root & Dependencies", 
	"None"
]
enum SearchMode {
	Recursive,
	ScenesAndDependencies,
	ScenesAndRootDependencies,
	RootAndDependencies,
	None
}

enum PreviewingType {
	Pack,
	Unpack,
	None
}

func _enter_tree() -> void:
	add_tool_menu_item("Pack Scene", Callable(_on_pack_scene))
	add_tool_menu_item("Unpack Scene", Callable(_on_unpack_scene))

func _exit_tree() -> void:
	remove_tool_menu_item("Pack Scene")
	remove_tool_menu_item("Unpack Scene")

var previewing_type: PreviewingType = PreviewingType.None
var file_to_preview: String = ""
var dependency_search_mode_preview: SearchMode
var dialog_to_preview: EditorFileDialog
var preview_tree: Tree
var tree_item_states: Dictionary
# used to detect changes in the selected file and preview tree
func _process(_delta: float) -> void:
	if previewing_type == PreviewingType.None:
		file_to_preview = ""
		return
	
	# propagate check changes
	for item: TreeItem in tree_item_states:
		var old_state: bool = tree_item_states[item]
		if item.is_checked(0) != old_state:
			tree_item_states[item] = item.is_checked(0)
			# update the state of all the descendants
			var children: Array[TreeItem] = item.get_children()
			while !children.is_empty():
				var child: TreeItem = children.front()
				child.set_checked(0, item.is_checked(0))
				tree_item_states[child] = child.is_checked(0)
				children.append_array(child.get_children())
				children.remove_at(0)
	
	var files_to_show = {}
	if previewing_type == PreviewingType.Pack:
		var dependency_search_mode: SearchMode = SearchMode.values()[dialog_to_preview.get_selected_options()[SEARCH_MODE_TITLE]]
		# return if the file and search mode didn't change
		if dependency_search_mode == dependency_search_mode_preview && file_to_preview == dialog_to_preview.current_path: return
		dependency_search_mode_preview = dependency_search_mode
		file_to_preview = dialog_to_preview.current_path
		# return if the file isn't valid
		if !file_to_preview.validate_filename() || file_to_preview.get_extension().is_empty(): return
		
		# search the scene
		var scene: PackedScene = load(file_to_preview)
		find_dependencies(scene, files_to_show, dependency_search_mode)
		
	elif previewing_type == PreviewingType.Unpack:
		# return if the file didn't change
		if file_to_preview == dialog_to_preview.current_path: return
		file_to_preview = dialog_to_preview.current_path
		# return if the file isn't valid
		if !file_to_preview.validate_filename() || file_to_preview.get_extension().is_empty(): return
		
		# search the file
		var reader := ZIPReader.new()
		var err := reader.open(file_to_preview)
		if err != OK: return
		files_to_show = reader.get_files()
		reader.close()
	
	# update the tree to display whatever paths we have
	
	preview_tree.clear()
	tree_item_states.clear()
	var created_nodes: Dictionary = {}
	var root: TreeItem = preview_tree.create_item()
	root.set_selectable(0, false)
	root.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	root.set_checked(0, true)
	root.set_editable(0, true)
	root.set_text(0, "root")
	tree_item_states[root] = root.is_checked(0)
	
	# create the tree items
	for path: String in files_to_show:
		var writepath: String = path.substr("res://".length(), path.length()-"res://".length()) if path.begins_with("res://") else path
		var path_nodes: PackedStringArray = writepath.split("/")
		var parent = root
		
		# make all tree items required to reach the path
		var current_path: String = ""
		for name: String in path_nodes:
			current_path += name + "/"
			if created_nodes.has(current_path):
				parent = created_nodes[current_path]
			else:
				created_nodes[current_path] = preview_tree.create_item(parent)
				parent = created_nodes[current_path]
				parent.set_selectable(0, false)
				parent.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
				parent.set_checked(0, true)
				parent.set_editable(0, true)
				parent.set_text(0, name)
				parent.set_tooltip_text(0, "res://"+current_path)
				tree_item_states[parent] = parent.is_checked(0)
		
		# give the last node on the path a tooltip showing its full path
		parent.set_tooltip_text(0, "res://"+writepath)

func process_value(value, found: Dictionary) -> void:
	if value:
		if typeof(value) == TYPE_OBJECT && value.has_method("get_path"):
			found[value.get_path()] = null
		elif typeof(value) == TYPE_ARRAY:
			for member in value:
				process_value(member, found)

func find_dependencies(packed_scene: PackedScene, found: Dictionary, search_mode: SearchMode) -> void:
	if !packed_scene: return
	found[packed_scene.resource_path] = null
	if search_mode == SearchMode.None: return
	var scene_state: SceneState = packed_scene.get_state()
	if !scene_state: return
	for instance_idx in scene_state.get_node_count():
		if search_mode == SearchMode.RootAndDependencies && instance_idx > 0: break
		
		# search the nodes recursively if asked
		var instance: PackedScene = scene_state.get_node_instance(instance_idx)
		if instance && !found.has(instance.resource_path):
			if search_mode == SearchMode.Recursive:
				find_dependencies(instance, found, search_mode)
			elif search_mode == SearchMode.ScenesAndDependencies:
				find_dependencies(instance, found, SearchMode.RootAndDependencies)
			elif search_mode == SearchMode.ScenesAndRootDependencies:
				find_dependencies(instance, found, SearchMode.None)
		
		# don't check the properties if it's not the root and search mode is Scene & Root Dependencies
		if search_mode == SearchMode.ScenesAndRootDependencies && instance_idx > 0: continue
		
		# search the properties
		for property_idx in scene_state.get_node_property_count(instance_idx):
			var value = scene_state.get_node_property_value(instance_idx, property_idx)
			process_value(value, found)
		
	
	# remove invalid dependencies
	var keys = found.keys()
	for file: String in keys:
		if file.begins_with(packed_scene.resource_path) && file != packed_scene.resource_path:
			found.erase(file)

func write_file(write_path: String, content: PackedByteArray) -> void:
	var writer = FileAccess.open(write_path, FileAccess.WRITE_READ)
	writer.store_buffer(content)
	writer.close()

func refresh_file_system() -> void:
	get_editor_interface().get_resource_filesystem().scan()

func step_read(filepath: String, i: int, force_overwrite: bool = false, ignore_paths: Dictionary = {}) -> void:
	# would've passed it by reference to keep it out of this function's scope, but gdscript can't do that :(
	var reader := ZIPReader.new()
	var err := reader.open(filepath)
	if err != OK: return
	
	var file_paths: PackedStringArray = reader.get_files()
	if i >= file_paths.size(): return
	var path = file_paths[i]
	
	var write_path = "res://" + path
	if ignore_paths.has(write_path): return step_read(filepath, i+1, force_overwrite, ignore_paths)
	
	DirAccess.make_dir_recursive_absolute(write_path.get_base_dir())
	if !force_overwrite && FileAccess.file_exists(write_path):
		var dialog := ConfirmationDialog.new()
		dialog.dialog_text = write_path + " already exists, would you like to overwrite it?"
		dialog.ok_button_text = "Overwrite"
		dialog.cancel_button_text = "Skip"
		dialog.add_button("Overwrite Remaining", true, "overwrite_remaining")
		dialog.add_button("Skip Remaining", true, "skip_remaining")
		
		# if the user selects confirm, write the file and go to the next one
		dialog.confirmed.connect(func():
			dialog.queue_free()
			write_file(write_path, reader.read_file(path))
			step_read(filepath, i+1, force_overwrite, ignore_paths)
		)
		# if the user selects cancel or closes the dialog, just go to the next file
		dialog.canceled.connect(func():
			dialog.queue_free()
			step_read(filepath, i+1, force_overwrite, ignore_paths)
		)
		# if the user presses another button
		dialog.custom_action.connect(func(action: String):
			dialog.queue_free()
			if action == "overwrite_remaining":
				write_file(write_path, reader.read_file(path))
				step_read(filepath, i+1, true, ignore_paths)
			elif action == "skip_remaining":
				return # explicit return, just don't continue the read/write chain
		)
		
		add_child(dialog)
		dialog.popup_centered()
	else:
		write_file(write_path, reader.read_file(path))
		step_read(filepath, i+1, force_overwrite, ignore_paths)

func _on_unpack_scene() -> void:
	# request a file to load
	dialog_to_preview = EditorFileDialog.new()
	dialog_to_preview.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog_to_preview.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog_to_preview.title = "Select File to Unpack"
	dialog_to_preview.add_filter("*.gdpck")
	dialog_to_preview.add_option("Force Overwrite on Load", [], 0)
	add_child(dialog_to_preview)
	while !dialog_to_preview.is_inside_tree(): pass
	dialog_to_preview.popup_centered(Vector2(1500, 1000))
	
	# make a new tree
	preview_tree = Tree.new()
	dialog_to_preview.add_side_menu(preview_tree, "Preview Tree")
	previewing_type = PreviewingType.Unpack
	
	dialog_to_preview.canceled.connect(func():
		previewing_type = PreviewingType.None
		preview_tree.queue_free()
		dialog_to_preview.queue_free()
	)
	
	dialog_to_preview.file_selected.connect(func(filepath: String):
		previewing_type = PreviewingType.None
		var force_overwrite: bool = dialog_to_preview.get_selected_options()["Force Overwrite on Load"]
		preview_tree.queue_free()
		dialog_to_preview.queue_free()
		
		# remember unselected paths
		var ignore_paths: Dictionary = {}
		var nodes: Array[TreeItem] = preview_tree.get_root().get_children()
		while !nodes.is_empty():
			var node: TreeItem = nodes.front()
			if !node.get_tooltip_text(0).is_empty() && !node.is_checked(0):
				ignore_paths[node.get_tooltip_text(0)] = null
			nodes.append_array(node.get_children())
			nodes.remove_at(0)
		
		# begin the step read
		step_read(filepath, 0, force_overwrite, ignore_paths)
		
		# wait a little before refreshing the file system
		await get_tree().create_timer(0.5).timeout
		refresh_file_system()
	)

func _on_pack_scene() -> void:
	# request a file to export
	dialog_to_preview = EditorFileDialog.new()
	dialog_to_preview.access = EditorFileDialog.ACCESS_RESOURCES
	dialog_to_preview.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog_to_preview.title = "Select Scene to Pack"
	dialog_to_preview.add_filter("*.tscn")
	dialog_to_preview.add_option(SEARCH_MODE_TITLE, SEARCH_MODE_PARAMS, 0)
	add_child(dialog_to_preview)
	dialog_to_preview.popup_centered(Vector2(1500, 1000))
	
	# make a new tree
	preview_tree = Tree.new()
	dialog_to_preview.add_side_menu(preview_tree, "Preview Tree")
	previewing_type = PreviewingType.Pack
	
	# prepare to request a location to export the file
	var savefile = EditorFileDialog.new()
	savefile.access = EditorFileDialog.ACCESS_FILESYSTEM
	savefile.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	savefile.title = "Packing Location"
	savefile.add_filter("*.gdpck")
	savefile.add_option("Ignore File Structure (Breaks Dependencies)", [], 0)
	add_child(savefile)
	
	dialog_to_preview.canceled.connect(func():
		previewing_type = PreviewingType.None
		preview_tree.queue_free()
		dialog_to_preview.queue_free()
		savefile.queue_free()
	)
	
	dialog_to_preview.file_selected.connect(func(filepath: String):
		previewing_type = PreviewingType.None
		var dependency_search_mode: SearchMode = SearchMode.values()[dialog_to_preview.get_selected_options()[SEARCH_MODE_TITLE]]
		preview_tree.queue_free()
		dialog_to_preview.queue_free()
		var filename = filepath.get_file().get_basename()
		
		# search the scene
		var scene: PackedScene = load(filepath)
		var files_to_save = {}
		find_dependencies(scene, files_to_save, dependency_search_mode)
		
		# remove unselected paths (the full paths are stored in the tooltips)
		var nodes: Array[TreeItem] = preview_tree.get_root().get_children()
		while !nodes.is_empty():
			var node: TreeItem = nodes.front()
			if !node.get_tooltip_text(0).is_empty() && !node.is_checked(0):
				if files_to_save.has(node.get_tooltip_text(0)):
					files_to_save.erase(node.get_tooltip_text(0))
			nodes.append_array(node.get_children())
			nodes.remove_at(0)
		
		# request the save path
		savefile.current_file = filename + ".gdpck"
		savefile.popup_centered(Vector2(1200, 1000))
		
		var savepath = await savefile.file_selected
		var ignore_file_structure: bool = savefile.get_selected_options()["Ignore File Structure (Breaks Dependencies)"]
		savefile.queue_free()
		
		# prepare to write
		var writer := ZIPPacker.new()
		var err := writer.open(savepath)
		if err != OK: return
		
		# write the scene and its requirements in a .gdexp file
		for path in files_to_save:
			var writepath: String = path.substr("res://".length(), path.length()-"res://".length())
			if ignore_file_structure: writepath = writepath.get_file()
			writer.start_file(writepath)
			writer.write_file(FileAccess.get_file_as_bytes(path))
			writer.close_file()
		
		writer.close()
	)
