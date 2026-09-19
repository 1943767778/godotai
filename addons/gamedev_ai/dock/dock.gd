@tool
extends VBoxContainer

var gemini_client
var context_manager
var _tool_executor
var _memory_manager
var locale_manager
var magic_actions_btn: MenuButton = null

# Scene node references (unique names from dock.tscn)
@onready var chat_scroll: ScrollContainer = %ChatScrollContainer
@onready var chat_vbox: VBoxContainer = %ChatVBox
var _current_bubble: RichTextLabel = null
var _current_role: String = ""
var _bubble_map: Dictionary = {}
@onready var input_field: TextEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var prompt_settings_btn: MenuButton = %PromptSettingsBtn
@onready var selection_status: Label = null  # tscn 无此节点，_ready 里补
@onready var summarize_btn: Button = %SummarizeBtn
var watch_mode_enabled: bool = false
var plan_first_enabled: bool = false
var context_enabled: bool = true
var screenshot_enabled: bool = false
@onready var execute_plan_btn: Button = %ExecutePlanBtn
@onready var chat_preset_selector: OptionButton = %ChatPresetSelector
@onready var font_size_minus_btn: Button = %FontSizeMinusBtn
@onready var font_size_plus_btn: Button = %FontSizePlusBtn
@onready var _image_preview_scroll: ScrollContainer = %ImagePreviewScroll
@onready var _thumbnail_list: HBoxContainer = %ThumbnailList
@onready var add_file_btn: Button = %AddFileBtn
@onready var _add_file_dialog: FileDialog = %AddFileDialog
@onready var _image_popup_dialog: AcceptDialog = %ImagePopupDialog
@onready var _popup_texture_rect: TextureRect = %PopupTextureRect
@onready var preset_selector: OptionButton = %PresetSelector
@onready var preset_name_input: LineEdit = %PresetNameInput
@onready var provider_selector: OptionButton = %ProviderSelector
@onready var preset_edit_panel: VBoxContainer = %PresetEditPanel
@onready var edit_preset_btn: Button = %EditPresetBtn
@onready var close_edit_btn: Button = %CloseEditBtn
@onready var settings_bar: HBoxContainer = %SettingsBar
@onready var api_input: LineEdit = %ApiInput
@onready var url_input: LineEdit = %UrlInput
@onready var model_input: LineEdit = %ModelInput
@onready var _file_preview_container: HBoxContainer = %FilePreviewContainer
@onready var _file_preview_label: RichTextLabel = %FilePreviewLabel
@onready var _file_clear_btn: Button = %FileClearBtn
@onready var custom_prompt_input: TextEdit = %CustomPromptInput
@onready var _diff_preview_panel: VBoxContainer = %DiffPreviewPanel
@onready var _diff_display: RichTextLabel = %DiffDisplay
@onready var _apply_diff_btn: Button = %ApplyDiffBtn
@onready var _skip_diff_btn: Button = %SkipDiffBtn
@onready var language_selector: OptionButton = %LanguageSelector
@onready var language_label: Label = %LanguageSelector.get_parent().get_child(0)


@onready var vector_db_file_list: RichTextLabel = null
@onready var scan_changes_btn: Button = null
@onready var index_codebase_btn: Button = null
@onready var index_confirm_dialog: ConfirmationDialog = null
@onready var index_result_dialog: AcceptDialog = null
@onready var enhance_prompt_btn: Button = null
@onready var enhance_preview_dialog: ConfirmationDialog = null
@onready var enhance_preview_label: RichTextLabel = null

var _card_titles: Array[Label] = []
var _enhance_http: HTTPRequest
var _enhanced_text: String = ""

var _attached_files: Array[Dictionary] = []
var _dropped_files: Array[String] = []

var _pending_history_entries: Array = []
var _load_more_btn: Button = null
var _conversation_list: VBoxContainer = null
var _active_toasts: Array = []
var _session_file_id: String = ""
var _pending_delete_path: String = ""
var _rename_target_path: String = ""
var _delete_confirm_dialog: ConfirmationDialog = null
var _pending_delete_session_id = null
var _last_reasoning_full: String = ""

var _next_block_id: int = 0
var _block_data: Dictionary = {}
var _chat_log_bbcode: String = ""

var presets: Dictionary = {}
var active_preset_name: String = ""
var _local_hint_label: Label = null

var _last_log_size: int = 0
var _ignore_next_error: bool = false
var _watch_fix_count: int = 0
var _watch_cooldown_until: float = 0.0
const _WATCH_MAX_FIXES: int = 3
const _WATCH_COOLDOWN_SECS: float = 30.0

var batch_queue: Array = []
var batch_results: Array = []
var current_tool_context: Dictionary = {}
var _is_stopped: bool = false
var _confirm_dialog: ConfirmationDialog
var _batch_total: int = 0
var _plan_pending: bool = false

# Precompiled regex for markdown parser
var _regex_bold_italic: RegEx
var _regex_bold: RegEx
var _regex_italic: RegEx
var _regex_code: RegEx
var _regex_suggest: RegEx

var _copy_popup: PopupMenu
var _floating_copy_btn: Button
var command_popup: PopupMenu
var _current_font_size: int = 14

# --- 消息编辑 / 删除 ---
var _edit_dialog: AcceptDialog = null
var _edit_input: TextEdit = null
var _edit_target_bubble: PanelContainer = null

# --- 对话重命名 ---
var _rename_dialog: AcceptDialog = null
var _rename_input: LineEdit = null
var _rename_session_id = null

# --- AI 请求重试 ---
var _retry_count: int = 0
var _is_retrying: bool = false
var _last_send_payload: Dictionary = {}
const _MAX_RETRIES: int = 5
const _RETRY_DELAY_STEP: float = 3.0

signal preset_changed(config)
signal settings_updated()

func _ready():
	# 保证 selection_status 有效，避免 Nil 报错
	if selection_status == null or not is_instance_valid(selection_status):
		selection_status = Label.new()
		selection_status.visible = false
		add_child(selection_status)
	pass
	# Initialize locale manager FIRST before any UI updates
	var settings = EditorInterface.get_editor_settings()
	var LocaleMgr = preload("res://addons/gamedev_ai/locale_manager.gd")
	locale_manager = LocaleMgr.new()
	var saved_locale = ""
	if settings.has_setting("gamedev_ai/language"):
		saved_locale = settings.get_setting("gamedev_ai/language")
	if saved_locale != "":
		locale_manager.set_locale(saved_locale)
	
	# Connect scene node signals
	prompt_settings_btn.get_popup().id_pressed.connect(_on_prompt_setting_id_pressed)
	
	%ExecutePlanBtn.pressed.connect(_on_execute_plan_pressed)
	
	send_button.pressed.connect(_on_send_pressed)
	input_field.gui_input.connect(_on_input_gui_input)
	input_field.text_changed.connect(_on_input_text_changed)
	
	command_popup = PopupMenu.new()
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.12, 0.15, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.5, 0.9, 0.6)
	panel_style.border_blend = true
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 12
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	command_popup.add_theme_stylebox_override("panel", panel_style)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.3, 0.5, 0.8)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	command_popup.add_theme_stylebox_override("hover", hover_style)
	
	command_popup.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	command_popup.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	command_popup.transparent_bg = true
	
	add_child(command_popup)
	command_popup.id_pressed.connect(_on_command_selected)
	
	add_file_btn.pressed.connect(func(): _add_file_dialog.popup_centered())
	_add_file_dialog.file_selected.connect(_on_add_file_selected)
	_file_clear_btn.pressed.connect(_on_clear_dropped_files)
	_apply_diff_btn.pressed.connect(_on_apply_diff_pressed)
	_skip_diff_btn.pressed.connect(_on_skip_diff_pressed)
	
	# Enable drag and drop across the main chat interface
	input_field.set_drag_forwarding(Callable(), _can_drop_data_fw, _drop_data_fw)
	chat_scroll.set_drag_forwarding(Callable(), _can_drop_data_fw, _drop_data_fw)
	
	chat_preset_selector.item_selected.connect(_on_chat_preset_selected)
	font_size_minus_btn.pressed.connect(_on_font_minus_pressed)
	font_size_plus_btn.pressed.connect(_on_font_plus_pressed)
	
	preset_selector.item_selected.connect(_on_preset_selected)
	find_child("AddPresetBtn", true, false).pressed.connect(_on_add_preset_pressed)
	edit_preset_btn.pressed.connect(_on_edit_preset_pressed)
	find_child("DelPresetBtn", true, false).pressed.connect(_on_delete_preset_pressed)
	close_edit_btn.pressed.connect(_on_close_edit_pressed)
	preset_name_input.text_submitted.connect(_on_rename_preset)
	preset_name_input.focus_exited.connect(func(): _on_rename_preset(preset_name_input.text))
	provider_selector.item_selected.connect(_on_provider_type_changed)
	api_input.text_changed.connect(_on_config_changed)
	model_input.text_changed.connect(_on_config_changed)
	url_input.text_changed.connect(_on_config_changed)
	
	summarize_btn.pressed.connect(_on_summarize_pressed)
	
	# Add provider options
	provider_selector.add_item("Gemini", 0)
	provider_selector.add_item("OpenAI / OpenRouter", 1)
	provider_selector.add_item("Local (Ollama / LM Studio)", 2)
	
	# Polling timer
	$PollTimer.timeout.connect(_on_poll_timer_timeout)
	
	# Load saved custom prompt
	if settings.has_setting("gamedev_ai/custom_system_prompt"):
		custom_prompt_input.text = settings.get_setting("gamedev_ai/custom_system_prompt")
	custom_prompt_input.text_changed.connect(_on_custom_prompt_changed)
	
	# Vector DB UI
	
	# Initial sync of instructions if client is already set
	if gemini_client:
		gemini_client.custom_instructions = custom_prompt_input.text
	
	# Build the "Conversations" tab (inserted at index 0)
	_build_conversation_tab()
	
	_load_presets()
	
	_populate_language_selector()
	language_selector.item_selected.connect(_on_language_changed)
	_apply_locale()
	
	# Sync initial language with provider
	if gemini_client:
		gemini_client.response_language_instruction = locale_manager.get_ai_language_instruction()
	
	# Precompile regex for markdown parser
	_regex_bold_italic = RegEx.new()
	_regex_bold_italic.compile("\\*\\*\\*(.+?)\\*\\*\\*")
	_regex_bold = RegEx.new()
	_regex_bold.compile("\\*\\*(.+?)\\*\\*")
	_regex_italic = RegEx.new()
	_regex_italic.compile("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
	_regex_code = RegEx.new()
	_regex_code.compile("`([^`]+)`")
	_regex_suggest = RegEx.new()
	_regex_suggest.compile("\\[SUGGEST:\\s*(.+?)\\]")
	
	# meta_clicked is now connected per-bubble in _create_chat_bubble()
	
	var fs = EditorInterface.get_resource_filesystem()
	if fs and not fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.connect(_on_filesystem_changed)
	
	# Apply custom visual theme
	_apply_custom_theme()
	_load_ui_settings()
	_deferred_init()
	# 初始化弹窗与特殊布局
	if _edit_dialog == null and has_method("_setup_edit_dialog"):
		_setup_edit_dialog()
	if _delete_confirm_dialog == null and has_method("_setup_delete_confirm_dialog"):
		_setup_delete_confirm_dialog()
	if has_method("_setup_magic_row"):
		_setup_magic_row()
	
	# 强制字号按钮文本（A- / A+）
	if font_size_minus_btn != null:
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.icon = null
		font_size_minus_btn.tooltip_text = "减小字号"
	if font_size_plus_btn != null:
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.icon = null
		font_size_plus_btn.tooltip_text = "增大字号"

	_setup_magic_row()
	_apply_all_icons()
	_shrink_tab_widths()

	_setup_copy_features()
	_setup_edit_dialog()
	_setup_delete_confirm_dialog()
	_setup_rename_dialog()


	# ===== 修复7 收尾 =====
	call_deferred("_fix_options_v9")
	call_deferred("_v10_final")
	# ===== 修复7 结束 =====

	# ===== 修复30 收尾 =====
	call_deferred("_hide_removed_v2")
	call_deferred("_ensure_extras_v5")
	call_deferred("_v30_final")
	call_deferred("_v30_trigger_dedupe")
	# ===== 修复30 结束 =====

	# ===== 修复32 收尾 =====
	call_deferred("_v32_fix_all")
	# ===== 修复32 结束 =====

	# ===== 修复33 收尾 =====
	# ===== 修复33 结束 =====

	# ===== 修复34 收尾 =====
	call_deferred("_v34_init")
	# ===== 修复34 结束 =====

	# ===== 修复36 收尾 =====
	call_deferred("_v36_init")
	# ===== 修复36 结束 =====

	# ===== 修复38 收尾 =====
	call_deferred("_v38_fix_settings_layout")
	# ===== 修复38 结束 =====

	# ===== 修复39 收尾 =====
	call_deferred("_v39_init")
	# ===== 修复39 结束 =====

	# ===== 修复42 收尾 =====
	call_deferred("_v42_kill_usage")
	call_deferred("_v40_refresh_all_footers")
	# ===== 修复42 结束 =====

	# ===== 修复43 收尾 =====
	call_deferred("_v43_init")
	# ===== 修复43 结束 =====

	# ===== 修复45b 收尾 =====
	# ===== 修复45b 结束 =====

	# ===== 修复47 收尾 =====
	call_deferred("_v46_hide_selection")
	call_deferred("_v47_fix_chinese_ui")
	# ===== 修复47 结束 =====

	# ===== 修复51 收尾 =====
	call_deferred("_v51_hide_selection_forever")
	# ===== 修复51 结束 =====

	# ===== 修复52 收尾 =====
	call_deferred("_v52_init")
	# ===== 修复52 结束 =====

	# ===== 修复53 收尾 =====
	# ===== 修复53 结束 =====

	# ===== 修复53 收尾 =====
	call_deferred("_v53_ensure_retry_timer")
	# ===== 修复53 结束 =====

	# ===== 修复57 收尾 =====
	# ===== 修复57 结束 =====

	# ===== 修复58 收尾 =====
	# ===== 修复58 结束 =====

	# ===== 修复60 收尾 =====
	call_deferred("_v58_startup_tips")
	# ===== 修复60 结束 =====

	# ===== 修复61 收尾 =====
	# ===== 修复61 结束 =====

	# ===== 修复63 收尾 =====
	call_deferred("_v61_setup_multikey_ui")
	# ===== 修复63 结束 =====

	# ===== 修复66 收尾 =====
	call_deferred("_v66_init")
	# ===== 修复66 结束 =====

	# ===== 修复69 收尾 =====
	# ===== 修复69 结束 =====

	# ===== 修复70 收尾 =====
	call_deferred("_v70_init")
	# ===== 修复70 结束 =====
func setup(client, manager, executor):
	context_manager = manager
	_tool_executor = executor
	_tool_executor.tool_output.connect(_on_tool_output)
	_tool_executor.confirmation_needed.connect(_on_confirmation_needed)
	_tool_executor.diff_preview_requested.connect(_on_diff_preview_requested)
	_tool_executor.image_captured.connect(_on_image_captured)
	_tool_executor.init_vector_db(self)
	_tool_executor.vector_db.db_output.connect(_on_vector_db_output)
	
	# Create destructive action confirmation dialog
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirm Destructive Action"
	_confirm_dialog.ok_button_text = "Yes, proceed"
	# _confirm_dialog.cancel_button_text = "Cancel"  # AcceptDialog 无此属性
	_confirm_dialog.confirmed.connect(_on_destructive_confirmed)
	_confirm_dialog.canceled.connect(_on_destructive_cancelled)
	add_child(_confirm_dialog)
	
	_set_client(client)

func _set_client(client):
	pass
	# Disconnect old client if exists
	if gemini_client:
		if gemini_client.response_received.is_connected(_on_ai_response):
			gemini_client.response_received.disconnect(_on_ai_response)
		if gemini_client.error_occurred.is_connected(_on_ai_error):
			gemini_client.error_occurred.disconnect(_on_ai_error)
		if gemini_client.tool_call_received.is_connected(_on_tool_calls):
			gemini_client.tool_call_received.disconnect(_on_tool_calls)
		if gemini_client.status_changed.is_connected(_on_status_changed):
			gemini_client.status_changed.disconnect(_on_status_changed)
		if gemini_client.token_usage_reported.is_connected(_on_token_usage):
			gemini_client.token_usage_reported.disconnect(_on_token_usage)
	
	gemini_client = client
	
	if gemini_client:
		gemini_client.response_received.connect(_on_ai_response)
		gemini_client.error_occurred.connect(_on_ai_error)
		gemini_client.tool_call_received.connect(_on_tool_calls)
		gemini_client.status_changed.connect(_on_status_changed)
		gemini_client.token_usage_reported.connect(_on_token_usage)
		if custom_prompt_input:
			gemini_client.custom_instructions = custom_prompt_input.text
			gemini_client.screenshot_enabled = screenshot_enabled

# ═══════════════════════════════════════════════════════════════
# CONVERSATION MANAGER TAB
# ═══════════════════════════════════════════════════════════════

const HISTORY_DIR: String = "res://.gamedev_ai/history"


func _list_history_files() -> Array:
	var files: Array = []
	var dir = DirAccess.open(HISTORY_DIR)
	if not dir:
		return files
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			files.append(HISTORY_DIR + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _read_session_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var txt = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


func _read_session_meta(path: String) -> Dictionary:
	var data = _read_session_data(path)
	if data.is_empty():
		return {}
	var sid = str(data.get("session_id", path.get_file().get_basename()))
	var title = str(data.get("title", sid))
	if title.strip_edges() == "":
		title = sid
	return {"path": path, "id": sid, "title": title, "data": data}


func _build_conversation_tab():
	var tab_container = $TabContainer
	if tab_container.has_node("Conversations"):
		return
	
	var conv_tab = VBoxContainer.new()
	conv_tab.name = "Conversations"
	conv_tab.add_theme_constant_override("separation", 8)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 6)
	
	var new_chat_btn = Button.new()
	new_chat_btn.name = "NewChatTopBtn"
	new_chat_btn.text = "新建对话"
	new_chat_btn.tooltip_text = "开始新对话，清空当前历史"
	new_chat_btn.custom_minimum_size = Vector2(96, 32)
	if new_chat_btn != null: new_chat_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	new_chat_btn.clip_text = false
	new_chat_btn.pressed.connect(_on_new_chat_pressed)
	top_hbox.add_child(new_chat_btn)
	
	var refresh_btn = Button.new()
	refresh_btn.name = "RefreshTopBtn"
	refresh_btn.text = "刷新列表"
	refresh_btn.tooltip_text = "重新从本地加载对话列表"
	refresh_btn.custom_minimum_size = Vector2(96, 32)
	if refresh_btn != null: refresh_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	refresh_btn.clip_text = false
	refresh_btn.pressed.connect(_refresh_conversations_list)
	top_hbox.add_child(refresh_btn)
	
	conv_tab.add_child(top_hbox)
	
	var scroll = ScrollContainer.new()
	if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	conv_tab.add_child(scroll)
	
	var list = VBoxContainer.new()
	list.name = "ConversationList"
	if list != null: list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	_conversation_list = list
	
	tab_container.add_child(conv_tab)
	tab_container.move_child(conv_tab, 0)
	
	call_deferred("_refresh_conversations_list")
func _setup_rename_dialog():
	if _rename_dialog != null:
		return
	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "重命名对话"
	_rename_dialog.ok_button_text = "保存"
	# _rename_dialog.cancel_button_text = "取消"  # AcceptDialog 无此属性
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	_rename_input = LineEdit.new()
	_rename_input.custom_minimum_size = Vector2(280, 0)
	_rename_dialog.add_child(_rename_input)
	add_child(_rename_dialog)


func _refresh_conversations_list():
	if not _conversation_list:
		return
	for child in _conversation_list.get_children():
		child.queue_free()
	
	var dir = DirAccess.open(HISTORY_DIR)
	if not dir:
		var err_lbl = Label.new()
		err_lbl.text = "请新建对话，因为历史对话目录不存在"
		err_lbl.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		_conversation_list.add_child(err_lbl)
		return
	
	var files: Array = []
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			files.append(HISTORY_DIR + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()
	
	if files.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "暂无历史对话（保存一次对话后会出现在这里）"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_conversation_list.add_child(empty_lbl)
		return
	
	var icon_base: String = "res://addons/gamedev_ai/assets/icons/"
	
	for path in files:
		var meta = _read_session_meta(path)
		var sid: String = str(meta.get("id", path.get_file().get_basename()))
		var title: String = str(meta.get("title", sid))
		if title.strip_edges() == "":
			title = sid
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		
		# 名字按钮 —— 撑满剩余空间，超出省略号
		var name_btn = Button.new()
		name_btn.text = title
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if name_btn != null: name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.clip_text = true
		name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_btn.tooltip_text = "双击加载：" + title
		name_btn.gui_input.connect(_on_conv_name_gui_input.bind(path))
		row.add_child(name_btn)
		
		# 加载 —— 固定 56
		var load_btn = Button.new()
		load_btn.text = "加载"
		load_btn.custom_minimum_size = Vector2(56, 32)
		if load_btn != null: load_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		load_btn.clip_text = false
		load_btn.pressed.connect(_on_conv_load_pressed.bind(path))
		row.add_child(load_btn)
		
		# 重命名 —— 图标 32×32
		var rename_btn = Button.new()
		rename_btn.flat = true
		rename_btn.custom_minimum_size = Vector2(32, 32)
		if rename_btn != null: rename_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var rename_tex = _load_svg_icon(icon_base + "rename.svg", "8ab4f8", 0.7)
		if rename_tex != null:
			rename_btn.icon = rename_tex
		else:
			rename_btn.text = "✎"
		rename_btn.tooltip_text = "重命名"
		rename_btn.pressed.connect(_on_conv_rename_pressed.bind(path, name_btn))
		row.add_child(rename_btn)
		
		# 删除 —— 图标 32×32
		var del_btn = Button.new()
		del_btn.flat = true
		del_btn.custom_minimum_size = Vector2(32, 32)
		if del_btn != null: del_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var del_tex = _load_svg_icon(icon_base + "delete.svg", "ff8a80", 0.7)
		if del_tex != null:
			del_btn.icon = del_tex
		else:
			del_btn.text = "🗑"
		del_btn.tooltip_text = "删除"
		del_btn.pressed.connect(_on_conv_delete_pressed.bind(path))
		row.add_child(del_btn)
		
		_conversation_list.add_child(row)
func _on_conv_delete_confirmed():
	pass


func _session_get_id(session) -> String:
	if session == null:
		return ""
	for key in ["id", "session_id", "uuid", "name"]:
		var v = session.get(key)
		if v != null and str(v) != "":
			return str(v)
	return ""


func _session_get_title(session) -> String:
	if session == null:
		return "无标题"
	for key in ["title", "name"]:
		var v = session.get(key)
		if v != null and str(v) != "":
			return str(v)
	return "无标题"
func _load_conversation(path):
	if path == null or str(path) == "":
		_show_toast("[color=red]无效路径[/color]")
		return
	var data = _read_session_data(path)
	if data.is_empty():
		_show_toast("[color=red]读取失败：" + str(path) + "[/color]")
		return
	
	# 优先读 messages（新格式），其次 transcript（旧格式）
	var msgs = data.get("messages", null)
	var trans = data.get("transcript", null)
	var use_trans: Array = []
	if msgs is Array and not msgs.is_empty():
		use_trans = msgs
	elif trans is Array and not trans.is_empty():
		use_trans = trans
	
	if gemini_client:
		var hist = data.get("history", [])
		if hist is Array and "history" in gemini_client:
			gemini_client.set("history", hist)
		if "transcript" in gemini_client:
			gemini_client.set("transcript", use_trans)
		var sid: String = str(data.get("session_id", ""))
		if sid != "":
			_session_file_id = sid
	
	_v66_rebuild_chat_from_transcript()
	_show_toast("[color=gray]已加载：" + path.get_file() + "[/color]")
	$TabContainer.current_tab = 1
func _rename_conversation(session_id, new_name):
	var clean_name = str(new_name).strip_edges()
	if clean_name == "":
		return
	if gemini_client and gemini_client.has_method("rename_session"):
		gemini_client.rename_session(session_id, clean_name)


func _delete_conversation(path):
	if path == null or str(path) == "":
		_show_toast("[color=red]无效的路径[/color]")
		return
	_pending_delete_path = str(path)
	# 弹确认窗
	if _delete_confirm_dialog:
		_delete_confirm_dialog.dialog_text = "确定要删除这个对话吗？
" + str(path) + "
此操作无法撤销。"
		_delete_confirm_dialog.popup_centered()
	else:
		pass


func _setup_delete_confirm_dialog():
	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.title = "删除对话"
	_delete_confirm_dialog.ok_button_text = "删除"
	# _delete_confirm_dialog.cancel_button_text = "取消"  # AcceptDialog 无此属性
	_delete_confirm_dialog.dialog_text = "确定要删除这个对话吗？"
	_delete_confirm_dialog.confirmed.connect(_on_conv_delete_confirmed)
	add_child(_delete_confirm_dialog)
func _load_presets():
	var settings = EditorInterface.get_editor_settings()
	if settings.has_setting("gamedev_ai/presets"):
		presets = settings.get_setting("gamedev_ai/presets")
	if not (presets is Dictionary) or presets.is_empty():
		presets = {
			"Gemini Default": {
				"provider": 0,
				"api_key": "",
				"base_url": "",
				"model_name": ""
			}
		}
	_update_preset_selector()
	
	if settings.has_setting("gamedev_ai/active_preset"):
		var saved_name: String = str(settings.get_setting("gamedev_ai/active_preset"))
		if presets.has(saved_name):
			active_preset_name = saved_name
		else:
			active_preset_name = presets.keys()[0]
	else:
		active_preset_name = presets.keys()[0]
	
	var idx := 0
	for i in range(preset_selector.item_count):
		if preset_selector.get_item_text(i) == active_preset_name:
			idx = i
			break
	preset_selector.selected = idx
	chat_preset_selector.selected = idx
	_on_preset_selected(idx)
func _update_preset_selector():
	preset_selector.clear()
	chat_preset_selector.clear()
	for p_name in presets.keys():
		preset_selector.add_item(p_name)
		chat_preset_selector.add_item(p_name)
	call_deferred("_shrink_all_options_v7")
func _save_presets():
	var settings = EditorInterface.get_editor_settings()
	# 深拷贝一份，避免引用
	var copy: Dictionary = {}
	for k in presets.keys():
		var v = presets[k]
		if v is Dictionary:
			copy[str(k)] = v.duplicate(true)
		else:
			copy[str(k)] = v
	settings.set_setting("gamedev_ai/presets", copy)
	settings.set_setting("gamedev_ai/active_preset", active_preset_name)
func _on_preset_selected(index: int):
	if index < 0 or index >= preset_selector.item_count:
		return
	active_preset_name = preset_selector.get_item_text(index)
	if not presets.has(active_preset_name):
		return
	var config = presets[active_preset_name]
	
	preset_name_input.text = active_preset_name
	provider_selector.selected = int(config.get("provider", 0))
	settings_bar.visible = true
	api_input.text = str(config.get("api_key", ""))
	url_input.text = str(config.get("base_url", ""))
	model_input.text = str(config.get("model_name", ""))
	
	chat_preset_selector.selected = index
	_save_presets()
	preset_changed.emit(config)
	_update_fields_for_provider(int(config.get("provider", 0)))
	if has_method("_v61_on_preset_selected_hook"):
		_v61_on_preset_selected_hook(index)
func _on_chat_preset_selected(index: int):
	preset_selector.selected = index
	_on_preset_selected(index)

func _on_add_preset_pressed():
	var new_name = "New Preset " + str(presets.size() + 1)
	presets[new_name] = {
		"provider": 0,
		"api_key": "",
		"base_url": "",
		"model_name": ""
	}
	_update_preset_selector()
	for i in range(preset_selector.item_count):
		if preset_selector.get_item_text(i) == new_name:
			preset_selector.selected = i
			_on_preset_selected(i)
			break
	preset_edit_panel.visible = true

func _on_edit_preset_pressed():
	preset_edit_panel.visible = true

func _on_close_edit_pressed():
	# 先尝试重命名
	var new_name: String = preset_name_input.text.strip_edges()
	if new_name != "" and new_name != active_preset_name:
		_on_rename_preset(new_name)
	# 保证再次回写配置
	_save_presets()
	preset_edit_panel.visible = false
func _on_font_minus_pressed():
	_current_font_size = max(10, _current_font_size - 2)
	_apply_font_size()

func _on_font_plus_pressed():
	_current_font_size = min(32, _current_font_size + 2)
	_apply_font_size()

func _apply_font_size():
	for bubble in chat_vbox.get_children():
		_apply_font_size_recursive(bubble)

func _apply_font_size_recursive(node: Node):
	if node is RichTextLabel:
		node.add_theme_font_size_override("normal_font_size", _current_font_size)
		node.add_theme_font_size_override("bold_font_size", _current_font_size)
		node.add_theme_font_size_override("italics_font_size", _current_font_size)
		node.add_theme_font_size_override("bold_italics_font_size", _current_font_size)
		node.add_theme_font_size_override("mono_font_size", _current_font_size)
	for child in node.get_children():
		_apply_font_size_recursive(child)

func _on_delete_preset_pressed():
	if presets.size() <= 1:
		return
	presets.erase(active_preset_name)
	_load_presets()

func _on_provider_type_changed(index: int):
	if not presets.has(active_preset_name):
		return
	presets[active_preset_name]["provider"] = index
	settings_bar.visible = true
	_save_presets()
	preset_changed.emit(presets[active_preset_name])
	_update_fields_for_provider(index)
func _update_fields_for_provider(index: int):
	var is_local = (index == 2)
	
	api_input.editable = not is_local
	if is_local:
		api_input.text = ""
		if locale_manager:
			api_input.placeholder_text = locale_manager.tr("api_key_not_required")
	else:
		api_input.placeholder_text = ""
	
	if is_local and url_input.text == "":
		url_input.text = "http://localhost:11434/v1"
	
	if is_local:
		url_input.placeholder_text = "http://localhost:11434/v1"
		if locale_manager:
			model_input.placeholder_text = locale_manager.tr("local_model_placeholder")
	else:
		url_input.placeholder_text = ""
		model_input.placeholder_text = ""
	
	_update_local_hint(is_local)
func _update_local_hint(is_local: bool):
	if not _local_hint_label:
		_local_hint_label = Label.new()
		_local_hint_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 0.9))
		_local_hint_label.add_theme_font_size_override("font_size", 11)
		settings_bar.get_parent().add_child(_local_hint_label)
		settings_bar.get_parent().move_child(_local_hint_label, settings_bar.get_index() + 1)
		
	_local_hint_label.visible = is_local
	if is_local and locale_manager:
		_local_hint_label.text = locale_manager.tr("local_hint")

func _on_rename_preset(new_name: String):
	var clean: String = new_name.strip_edges()
	if clean == "" or clean == active_preset_name:
		preset_name_input.text = active_preset_name
		return
	
	if presets.has(clean):
		# 名字已存在
		preset_name_input.text = active_preset_name
		return
	
	var config = presets[active_preset_name]
	# 重新构造字典（有序，避免 erasing 后 key 位置乱）
	var new_presets: Dictionary = {}
	for k in presets.keys():
		if k == active_preset_name:
			new_presets[clean] = config
		else:
			new_presets[k] = presets[k]
	presets = new_presets
	active_preset_name = clean
	
	_update_preset_selector()
	for i in range(preset_selector.item_count):
		if preset_selector.get_item_text(i) == active_preset_name:
			preset_selector.selected = i
			chat_preset_selector.selected = i
			break
	# 强制回写设置
	_save_presets()
func _on_config_changed(_text: String = ""):
	var provider = presets[active_preset_name].get("provider", 0)
	presets[active_preset_name]["api_key"] = "" if provider == 2 else api_input.text
	presets[active_preset_name]["base_url"] = url_input.text
	presets[active_preset_name]["model_name"] = model_input.text
	_save_presets()
	settings_updated.emit()
	if has_method("_v61_on_config_save_hook"):
		_v61_on_config_save_hook()
func _populate_language_selector():
	language_selector.clear()
	var locales = locale_manager.get_available_locales()
	var current = locale_manager.get_locale()
	for i in range(locales.size()):
		language_selector.add_item(locales[i]["name"], i)
		if locales[i]["code"] == current:
			language_selector.selected = i

func _on_language_changed(index: int):
	var locales = locale_manager.get_available_locales()
	if index >= 0 and index < locales.size():
		locale_manager.set_locale(locales[index]["code"])
		var settings = EditorInterface.get_editor_settings()
		settings.set_setting("gamedev_ai/language", locales[index]["code"])
		_apply_locale()
		# Update AI response language
		if gemini_client:
			var lang_instruction = locale_manager.get_ai_language_instruction()
			gemini_client.response_language_instruction = lang_instruction

func _apply_locale():
	if not locale_manager:
		return
	var L = locale_manager
	
	# Chat tab
	send_button.tooltip_text = L.tr("tt_send")
	add_file_btn.text = ""
	add_file_btn.tooltip_text = L.tr("tt_attach")
	summarize_btn.text = ""
	summarize_btn.tooltip_text = "Save all current messages to file"
	prompt_settings_btn.text = L.tr("prompt_settings")
	selection_status.text = L.tr("no_selection")
	input_field.placeholder_text = L.tr("input_placeholder")
	execute_plan_btn.text = L.tr("run_plan")
	
	for title_label in _card_titles:
		if is_instance_valid(title_label):
			title_label.text = L.tr(title_label.get_meta("tr_key"))
	
	var p_popup = prompt_settings_btn.get_popup()
	p_popup.set_item_text(0, L.tr("context"))
	p_popup.set_item_text(1, L.tr("screenshot"))
	p_popup.set_item_text(2, L.tr("plan_first"))
	p_popup.set_item_text(3, L.tr("watch_mode"))
	
	# Tab titles
	var tab_container = find_child("TabContainer", true, false)
	if tab_container and tab_container is TabContainer:
		if tab_container.get_tab_count() >= 1:
			tab_container.set_tab_title(0, "对话管理")
		if tab_container.get_tab_count() >= 2:
			tab_container.set_tab_title(1, L.tr("chat_tab"))
		if tab_container.get_tab_count() >= 3:
			tab_container.set_tab_title(2, L.tr("settings_tab"))
	
	# Settings tab
	var p_label = find_child("PresetLabel", true, false)
	if p_label: p_label.text = L.tr("preset_label")
	var add_btn = find_child("AddPresetBtn", true, false)
	if add_btn: add_btn.text = L.tr("add")
	if edit_preset_btn != null: edit_preset_btn.text = L.tr("edit")
	var del_btn = find_child("DelPresetBtn", true, false)
	if del_btn: del_btn.text = L.tr("delete")
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
	var name_lbl = find_child("NameLabel", true, false)
	if name_lbl: name_lbl.text = L.tr("preset_name_label")
	var prov_lbl = find_child("ProviderLabel", true, false)
	if prov_lbl: prov_lbl.text = L.tr("provider_label")
	var api_lbl = find_child("ApiLabel", true, false)
	if api_lbl: api_lbl.text = L.tr("api_key_label")
	var mod_lbl = find_child("ModelLabel", true, false)
	if mod_lbl: mod_lbl.text = L.tr("model_name_label")
	var url_lbl = find_child("UrlLabel", true, false)
	if url_lbl: url_lbl.text = L.tr("base_url_label")
	if language_label != null: language_label.text = L.tr("language_label")
	var cust_lbl = find_child("CustomPromptLabel", true, false)
	if cust_lbl: cust_lbl.text = L.tr("custom_instructions_label")
	if custom_prompt_input != null:
		custom_prompt_input.placeholder_text = L.tr("custom_instructions_placeholder")
	
	# Diff preview
	if _diff_preview_panel != null:
		var dl = _diff_preview_panel.get_node_or_null("DiffLabel")
		if dl != null: dl.text = L.tr("diff_preview_label")
	if _apply_diff_btn != null: _apply_diff_btn.text = L.tr("apply_changes")
	if _skip_diff_btn != null: _skip_diff_btn.text = L.tr("skip")
func _v66_on_new_chat_pressed():
	if gemini_client:
		if gemini_client.has_method("new_session"):
			gemini_client.new_session()
		_clear_chat()
		_session_file_id = ""
		_last_reasoning_full = ""
		_show_toast("[color=gray]已开始新对话[/color]")
		_update_ui_state(false)
	_refresh_conversations_list()
func _on_summarize_pressed():
	_save_all_messages_to_file()

func _save_all_messages_to_file():
	var dir_path: String = HISTORY_DIR
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			_show_toast("[color=red]无法创建目录 " + dir_path + "[/color]")
			return
	
	var sid: String = _v66_get_session_file_id()
	var path: String = dir_path + "/" + sid + ".json"
	
	# ─── 先收未加载的更早消息（_pending_history_entries）───
	var messages: Array = []
	for entry in _pending_history_entries:
		if not (entry is Dictionary):
			continue
		var r: String = str(entry.get("role", ""))
		if r == "summary":
			messages.append({"role": "summary", "text": str(entry.get("text", ""))})
			continue
		messages.append({
			"role": r,
			"text": str(entry.get("text", "")),
			"blocks": entry.get("blocks", [])
		})
	
	# ─── 再从 UI 收集当前显示的所有消息 ───
	for child in chat_vbox.get_children():
		if child == _diff_preview_panel:
			continue
		if child == _load_more_btn:
			continue
		if not child.has_meta("role"):
			continue
		var role: String = str(child.get_meta("role"))
		
		# 总结气泡
		if role == "summary" or (child.has_meta("is_summary") and bool(child.get_meta("is_summary"))):
			var summary_text: String = str(child.get_meta("summary_text", ""))
			var lbl_s = child.get_meta("label", null)
			if is_instance_valid(lbl_s):
				summary_text = lbl_s.get_parsed_text()
			messages.append({"role": "summary", "text": summary_text})
			continue
		
		var label = child.get_meta("label")
		if not is_instance_valid(label):
			continue
		var raw_bb: String = label.get_meta("raw_bbcode", "")
		
		var blocks: Array = []
		var block_ids: Array = []
		for bid in _block_data.keys():
			if _block_data[bid].get("bubble_ref") == label:
				block_ids.append(bid)
		block_ids.sort()
		for bid in block_ids:
			var d: Dictionary = _block_data[bid]
			blocks.append({
				"label": str(d.get("label", "")),
				"content": str(d.get("content", "")).replace("[lb]", "["),
				"color": str(d.get("color", "gray")),
				"expanded": bool(d.get("expanded", false))
			})
			var block_bb: String = _get_block_bbcode(bid)
			if block_bb != "" and block_bb in raw_bb:
				raw_bb = raw_bb.replace(block_bb, "")
		
		raw_bb = _v54_strip_response_prefix_from_bb(raw_bb)
		messages.append({
			"role": role,
			"text": raw_bb.strip_edges(),
			"blocks": blocks
		})
	
	# ─── 保留 title ───
	var existing_title: String = ""
	if FileAccess.file_exists(path):
		var old_data = _read_session_data(path)
		existing_title = str(old_data.get("title", ""))
	
	var trans_compat: Array = []
	for m in messages:
		if str(m.get("role", "")) == "summary":
			continue
		trans_compat.append({"role": m.get("role", "user"), "text": m.get("text", "")})
	
	var data: Dictionary = {
		"saved_at": Time.get_datetime_string_from_system(),
		"session_id": sid,
		"title": existing_title,
		"messages": messages,
		"transcript": trans_compat
	}
	if existing_title.strip_edges() == "":
		data["title"] = _generate_default_title(messages, [])
	
	if gemini_client and "transcript" in gemini_client:
		gemini_client.set("transcript", messages)
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
		var fs = EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()
		_show_toast("[color=green]已保存 " + str(messages.size()) + " 条[/color]")
		_refresh_conversations_list()
	else:
		_show_toast("[color=red]保存失败[/color]")
func _generate_default_title(transcript, history) -> String:
	pass
	# 优先从第一条 user 消息提取
	var first_user_text: String = ""
	if transcript is Array:
		for entry in transcript:
			if entry is Dictionary and entry.get("role", "") == "user":
				first_user_text = str(entry.get("text", ""))
				break
	if first_user_text == "" and history is Array:
		for entry in history:
			if entry is Dictionary and entry.get("role", "") == "user":
				var c = entry.get("content", "")
				if c is String:
					first_user_text = str(c)
				elif c is Array and c.size() > 0:
					var p = c[0]
					if p is Dictionary:
						first_user_text = str(p.get("text", ""))
				break
	
	var title: String = ""
	if first_user_text.strip_edges() != "":
		var t = first_user_text.strip_edges().replace("
", " ")
		if t.length() > 30:
			t = t.substr(0, 30) + "…"
		title = t
	
	if title == "":
		title = "对话 " + Time.get_datetime_string_from_system(false, true)
	return title
func _show_toast(message: String, duration: float = 5.0):
	var toast = PanelContainer.new()
	toast.top_level = true
	toast.z_index = 100
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	style.border_color = Color(0.3, 0.5, 0.9, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	toast.add_theme_stylebox_override("panel", style)
	
	var lbl = RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.text = message
	lbl.custom_minimum_size = Vector2(280, 0)
	toast.add_child(lbl)
	
	add_child(toast)
	await get_tree().process_frame
	await get_tree().process_frame
	
	var real_h: float = toast.size.y
	if real_h <= 0.0:
		real_h = toast.get_combined_minimum_size().y
	if real_h <= 0.0:
		real_h = 48.0
	
	var vp = get_viewport()
	var vp_rect: Rect2 = vp.get_visible_rect() if vp else Rect2(0, 0, 800, 600)
	
	var shift_amount: float = real_h + 8.0
	for t in _active_toasts:
		if is_instance_valid(t):
			var tw_shift = t.create_tween()
			tw_shift.tween_property(t, "global_position:y",
				t.global_position.y - shift_amount, 0.25) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var target_x: float = (vp_rect.size.x - toast.size.x) * 0.5
	var target_y: float = vp_rect.size.y - 160.0
	
	toast.global_position = Vector2(-toast.size.x, target_y)
	toast.modulate.a = 0.0
	_active_toasts.append(toast)
	
	var tw = toast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(toast, "global_position:x", target_x, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast, "modulate:a", 1.0, 0.3)
	
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(toast):
		var tw_out = toast.create_tween()
		tw_out.set_parallel(true)
		tw_out.tween_property(toast, "global_position:x", -toast.size.x, 0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_out.tween_property(toast, "modulate:a", 0.0, 0.3)
		await tw_out.finished
		if is_instance_valid(toast):
			toast.queue_free()
	_active_toasts.erase(toast)
func _v54_render_msg(entry):
	if not (entry is Dictionary):
		return
	var role: String = str(entry.get("role", "user"))
	var text: String = str(entry.get("text", ""))
	var blocks = entry.get("blocks", [])
	
	# 兼容旧格式：只有 role+text
	if role == "user":
		_log_user_message(text)
	elif role == "ai" or role == "model" or role == "system":
		_add_to_chat("
[b]Response:[/b]
", "ai")
		var clean_text: String = _strip_response_prefix(str(text))
		if clean_text.strip_edges() != "":
			_add_to_chat(_markdown_to_bbcode(clean_text) + "
", "ai")
		if blocks is Array:
			for b in blocks:
				if not (b is Dictionary):
					continue
				var lbl: String = str(b.get("label", ""))
				var content: String = str(b.get("content", ""))
				var color: String = str(b.get("color", "gray"))
				var expanded: bool = bool(b.get("expanded", false))
				if content == "" and lbl == "":
					continue
				_append_collapsible_block(lbl, content, color, expanded)
	else:
		# 未知角色 → 当作用户消息
		_log_user_message(text)
func _v66_add_load_more_button():
	_load_more_btn = Button.new()
	var text_msg = locale_manager.tr("load_older_messages") if locale_manager and locale_manager.has_method("tr") else "Carregar Mais"
	_load_more_btn.text = str(_pending_history_entries.size()) + " " + text_msg
	_load_more_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_load_more_btn.pressed.connect(_load_older_messages)
	
	chat_vbox.add_child(_load_more_btn)
	chat_vbox.move_child(_load_more_btn, 0)

func _v66_load_older_messages():
	if _pending_history_entries.is_empty() or _load_more_btn == null or _load_more_btn.disabled:
		return
	_load_more_btn.disabled = true
	_load_more_btn.text = "加载中…"
	await get_tree().process_frame
	var old_scroll = chat_scroll.scroll_vertical
	var old_height = chat_vbox.size.y
	var total: int = _pending_history_entries.size()
	var batch_start: int = max(0, total - 5)
	var batch_end: int = total
	for i in range(total - 1, batch_start - 1, -1):
		var e = _pending_history_entries[i]
		if e is Dictionary and str(e.get("role", "")) == "summary":
			batch_start = i
			break
	var batch: Array = _pending_history_entries.slice(batch_start, batch_end)
	if batch_start == 0:
		_pending_history_entries.clear()
	else:
		_pending_history_entries.resize(batch_start)
	# ─── 强制每条独立气泡，从 index 1 开始插入 ───
	var insert_at: int = 1
	for entry in batch:
		_current_bubble = null
		_current_role = ""
		_v66_render_msg(entry, insert_at)
		insert_at += 1
	if _pending_history_entries.is_empty():
		_load_more_btn.queue_free()
		_load_more_btn = null
	else:
		_load_more_btn.disabled = false
		_load_more_btn.text = str(_pending_history_entries.size()) + " 条更早消息"
	await get_tree().process_frame
	await get_tree().process_frame
	chat_scroll.scroll_vertical = old_scroll + (chat_vbox.size.y - old_height)
func _on_status_changed(is_requesting: bool):
	# 无限重试活跃期间：忽略 false，保持"终止"
	if _v69_retry_active:
		_update_ui_state(true)
		return
	_update_ui_state(is_requesting)
func _update_ui_state(busy: bool):
	input_field.editable = !busy
	var icon_path = "res://addons/gamedev_ai/assets/icons/"
	if busy:
		send_button.text = ""
		send_button.icon = _load_svg_icon(icon_path + "stop.svg", "ffffff", 0.75)
		send_button.tooltip_text = locale_manager.tr("stop") if locale_manager else "Stop"
		_style_danger_button(send_button, 20)
	else:
		send_button.text = ""
		send_button.icon = _load_svg_icon(icon_path + "send.svg", "ffffff", 0.75)
		send_button.tooltip_text = locale_manager.tr("tt_send") if locale_manager else "Send"
		_style_solid_button(send_button, Color(0.15, 0.6, 0.35), 20)

func _on_send_pressed():
	if _v61_is_generating_summary:
		_v61_cancel_summary()
		return
	if gemini_client and gemini_client.is_requesting:
		_stop_ai()
		return
	if _is_retrying or _v53_is_in_retry_loop():
		_stop_ai()
		return
	var text = input_field.text.strip_edges()
	if text.is_empty() and _attached_files.is_empty():
		return
	_process_send(text)
func _on_execute_plan_pressed():
	execute_plan_btn.visible = false
	_plan_pending = false
	plan_first_enabled = false # Auto-disable to avoid loop
	prompt_settings_btn.get_popup().set_item_checked(2, false)
	_process_send("Okay, the plan looks good. Please execute the proposed plan now using the appropriate tools.", true)

func _on_prompt_setting_id_pressed(id: int):
	if id == 100:
		if _full_auto:
			_show_toast("[color=orange]完全自动化状态下，自动审批已强制开启[/color]
[color=gray]如需关闭请先关闭完全自动化[/color]")
			_refresh_menu_checks()
			return
		_v34_set_auto_approve(not _auto_approve)
		_refresh_menu_checks()
		return
	elif id == 101:
		_v52_set_infinite_retry(not _infinite_retry)
		_refresh_menu_checks()
		return
	elif id == 102:
		_v52_set_full_auto(not _full_auto)
		_refresh_menu_checks()
		return
	var popup = prompt_settings_btn.get_popup()
	var checked = !popup.is_item_checked(id)
	popup.set_item_checked(id, checked)
	match id:
		0: context_enabled = checked
		1:
			screenshot_enabled = checked
			if gemini_client:
				gemini_client.screenshot_enabled = checked
		2: plan_first_enabled = checked
		3: watch_mode_enabled = checked
func _get_filtered_tools() -> Array:
	var tools: Array = []
	if _tool_executor:
		tools = _tool_executor.get_tool_definitions()
		if not screenshot_enabled:
			var filtered := []
			for t in tools:
				if t.get("name") != "capture_editor_screenshot":
					filtered.append(t)
			tools = filtered
	# 追加自定义 UnDo 工具
	var has_undo := false
	for t in tools:
		if t.get("name") == "undo_tool_call":
			has_undo = true
			break
	if not has_undo:
		tools.append({
			"name": "undo_tool_call",
			"description": "恢复某个工具调用前的文件状态。需要提供该工具调用的 ID 和对应撤销码。",
			"parameters": {
				"type": "object",
				"properties": {
					"tool_call_id": {"type": "string", "description": "要撤销的工具调用 ID（8 位）"},
					"undo_code": {"type": "string", "description": "该工具调用对应的撤销码（8 位）"}
				},
				"required": ["tool_call_id", "undo_code"]
			}
		})
	return tools
func _stop_ai():
	# 设置取消标记 → 后续的响应/错误会被丢弃
	_v69_retry_cancelled = true
	_v69_retry_active = false
	if _v69_retry_timer != null and is_instance_valid(_v69_retry_timer):
		_v69_retry_timer.stop()
	_is_stopped = false   # 立即复位，避免下一次正常响应的检查误伤
	_is_retrying = false
	_retry_count = 0
	_last_send_payload = {}
	_clear_tool_progress()
	batch_queue.clear()
	batch_results.clear()
	current_tool_context = {}
	if gemini_client:
		gemini_client.cancel_request()
	if _diff_preview_panel and _diff_preview_panel.visible:
		_diff_preview_panel.visible = false
		chat_scroll.visible = true
		if _tool_executor and _tool_executor.has_method("cancel_pending_action"):
			_tool_executor.cancel_pending_action()
	_current_bubble = null
	_current_role = ""
	# 强制发送按钮恢复
	_update_ui_state(false)
	_show_toast("[color=orange]已手动取消[/color]")
func _on_input_gui_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and event.shift_pressed:
			input_field.get_viewport().set_input_as_handled()
			var text = input_field.text.strip_edges()
			if text.is_empty() and _attached_files.is_empty():
				return
			_process_send(text)
		elif event.keycode == KEY_V and event.ctrl_pressed:
			var clipboard_image = DisplayServer.clipboard_get_image()
			if clipboard_image and not clipboard_image.is_empty():
				input_field.get_viewport().set_input_as_handled()
				var img_buffer = clipboard_image.save_png_to_buffer()
				_attached_files.append({
					"type": "image",
					"filename": "clipboard.png",
					"mime_type": "image/png",
					"image_obj": clipboard_image,
					"raw_bytes": img_buffer
				})
				_refresh_thumbnails()
				_show_toast("[color=green]" + locale_manager.tr("image_pasted") + "[/color]")

const SLASH_COMMANDS = [
	"/brainstorm", "/plan", "/debug", "/create", "/deploy", 
	"/enhance", "/orchestrate", "/preview", "/status", "/test"
]

func _on_input_text_changed():
	var text = input_field.text
	var caret_line = input_field.get_caret_line()
	var caret_col = input_field.get_caret_column()
	
	var lines = text.split("\n")
	if lines.size() <= caret_line: return
	var line_text = lines[caret_line]
	var text_before_caret = line_text.substr(0, caret_col)
	
	var last_space_idx = text_before_caret.rfind(" ")
	var current_word = ""
	if last_space_idx == -1:
		current_word = text_before_caret
	else:
		current_word = text_before_caret.substr(last_space_idx + 1)
	
	if current_word.begins_with("/") and current_word.length() > 0:
		_show_command_suggestions(current_word)
	else:
		command_popup.hide()

func _show_command_suggestions(prefix: String):
	command_popup.clear()
	var matches = []
	for cmd in SLASH_COMMANDS:
		if cmd.begins_with(prefix):
			matches.append(cmd)
	
	if matches.is_empty():
		command_popup.hide()
		return
		
	for i in range(matches.size()):
		command_popup.add_item(matches[i], i)
		
	var caret_pos = input_field.get_caret_draw_pos()
	var global_pos = input_field.global_position + caret_pos + Vector2(0, 24)
	
	var popup_rect = Rect2i(int(global_pos.x), int(global_pos.y), 200, matches.size() * 32)
	command_popup.popup(popup_rect)

func _on_command_selected(id: int):
	var selected_cmd = command_popup.get_item_text(id)
	
	var text = input_field.text
	var caret_line = input_field.get_caret_line()
	var caret_col = input_field.get_caret_column()
	
	var lines = text.split("\n")
	var line_text = lines[caret_line]
	var text_before_caret = line_text.substr(0, caret_col)
	var text_after_caret = line_text.substr(caret_col)
	
	var last_space_idx = text_before_caret.rfind(" ")
	var new_line_text = ""
	if last_space_idx == -1:
		new_line_text = selected_cmd + " " + text_after_caret
	else:
		new_line_text = text_before_caret.substr(0, last_space_idx + 1) + selected_cmd + " " + text_after_caret
		
	lines[caret_line] = new_line_text
	input_field.text = "\n".join(lines)
	
	var new_col = (last_space_idx + 1 if last_space_idx != -1 else 0) + selected_cmd.length() + 1
	input_field.set_caret_line(caret_line)
	input_field.set_caret_column(new_col)
	
	command_popup.hide()
	input_field.grab_focus()

func _on_add_file_selected(path: String):
	_attach_file_from_path(path)

func _on_image_captured(path: String):
	if FileAccess.file_exists(path):
		var img = Image.new()
		var err = img.load(path)
		if err == OK:
			var file = FileAccess.open(path, FileAccess.READ)
			var bytes = file.get_buffer(file.get_length())
			var filename = path.get_file()
			
			_attached_files.append({
				"type": "image",
				"filename": filename,
				"mime_type": "image/png",
				"image_obj": img,
				"raw_bytes": bytes
			})
			_refresh_thumbnails()
			var tr_text = locale_manager.tr("image_attached") if locale_manager else "Attached image: "
			_add_to_chat("\n[color=green][i]" + tr_text + filename + "[/i][/color]\n")

func _refresh_thumbnails():
	for child in _thumbnail_list.get_children():
		child.queue_free()
		
	if _attached_files.is_empty():
		_image_preview_scroll.visible = false
		return
		
	_image_preview_scroll.visible = true
	
	for i in range(_attached_files.size()):
		var file_data = _attached_files[i]
		var container = Control.new()
		
		if file_data["type"] == "image":
			var img = file_data["image_obj"]
			var thumb_rect = TextureRect.new()
			thumb_rect.custom_minimum_size = Vector2(80, 80)
			var texture = ImageTexture.create_from_image(img)
			thumb_rect.texture = texture
			thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			thumb_rect.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_popup_texture_rect.texture = texture
					_image_popup_dialog.popup_centered()
			)
			thumb_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			container.custom_minimum_size = Vector2(80, 80)
			container.add_child(thumb_rect)
		else:
			var panel = PanelContainer.new()
			panel.custom_minimum_size = Vector2(80, 80)
			panel.tooltip_text = file_data["filename"]
			var vbox = VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			var icon_label = Label.new()
			var is_audio = file_data["filename"].ends_with("mp3") or file_data["filename"].ends_with("wav") or file_data["filename"].ends_with("ogg")
			icon_label.text = "🎵" if is_audio else "📎"
			icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var name_label = Label.new()
			name_label.text = file_data["filename"]
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.clip_text = true
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.custom_minimum_size = Vector2(70, 0)
			vbox.add_child(icon_label)
			vbox.add_child(name_label)
			panel.add_child(vbox)
			container.custom_minimum_size = Vector2(80, 80)
			container.add_child(panel)
		
		var close_btn = Button.new()
		close_btn.text = ""
		var _close_icon = load("res://addons/gamedev_ai/assets/icons/close.svg")
		close_btn.icon = _close_icon
		close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close_btn.expand_icon = true
		close_btn.custom_minimum_size = Vector2(20, 20)
		close_btn.size = Vector2(20, 20)
		close_btn.position = Vector2(container.custom_minimum_size.x - 22, 2)
		close_btn.add_theme_color_override("icon_normal_color", Color(1.0, 1.0, 1.0, 0.9))
		close_btn.add_theme_color_override("icon_hover_color", Color.WHITE)
		close_btn.add_theme_color_override("icon_pressed_color", Color(0.9, 0.3, 0.3))
		var btn_normal = StyleBoxFlat.new()
		btn_normal.bg_color = Color(0.12, 0.12, 0.15, 0.85)
		btn_normal.border_color = Color(0.3, 0.3, 0.35, 0.6)
		btn_normal.border_width_top = 1
		btn_normal.border_width_bottom = 1
		btn_normal.border_width_left = 1
		btn_normal.border_width_right = 1
		btn_normal.corner_radius_top_left = 3
		btn_normal.corner_radius_top_right = 3
		btn_normal.corner_radius_bottom_left = 3
		btn_normal.corner_radius_bottom_right = 3
		btn_normal.content_margin_left = 0
		btn_normal.content_margin_right = 0
		btn_normal.content_margin_top = 0
		btn_normal.content_margin_bottom = 0
		var btn_hover = btn_normal.duplicate()
		btn_hover.bg_color = Color(0.75, 0.2, 0.2, 0.95)
		btn_hover.border_color = Color(0.9, 0.35, 0.35, 0.8)
		var btn_pressed = btn_normal.duplicate()
		btn_pressed.bg_color = Color(0.6, 0.12, 0.12, 0.95)
		btn_pressed.border_color = Color(0.7, 0.25, 0.25, 0.8)
		close_btn.add_theme_stylebox_override("normal", btn_normal)
		close_btn.add_theme_stylebox_override("hover", btn_hover)
		close_btn.add_theme_stylebox_override("pressed", btn_pressed)
		close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		close_btn.pressed.connect(func():
			_remove_attached_file(i)
		)
		
		container.add_child(close_btn)
		_thumbnail_list.add_child(container)

func _remove_attached_file(index: int):
	if index >= 0 and index < _attached_files.size():
		_attached_files.remove_at(index)
		_refresh_thumbnails()
		_show_toast("[color=orange]" + locale_manager.tr("attachment_removed") + "[/color]")



func _attach_file_from_path(path: String) -> void:
	pass
	# Resolve res:// paths to absolute for FileAccess
	var abs_path = path
	if path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	elif path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)

	var ext = path.get_extension().to_lower()
	var filename = path.get_file()

	if ext in ["png", "jpg", "jpeg", "webp"]:
		var img = Image.new()
		var err = img.load(abs_path)
		if err == OK:
			var file = FileAccess.open(abs_path, FileAccess.READ)
			if file:
				var bytes = file.get_buffer(file.get_length())
				var mime = "image/" + ("jpeg" if ext in ["jpg", "jpeg"] else ext)
				_attached_files.append({
					"type": "image",
					"filename": filename,
					"mime_type": mime,
					"image_obj": img,
					"raw_bytes": bytes
				})
				_refresh_thumbnails()
				_show_toast("[color=green]" + locale_manager.tr("image_attached") + filename + "[/color]")
		else:
			_show_toast("[color=red]" + locale_manager.tr("failed_load_image") + path + "[/color]")
	else:
		pass
		# Treat everything else as text (GDScript, scenes, resources, configs, etc.)
		# For binary-ish files that can't be read as text, attach metadata only
		var file = FileAccess.open(abs_path, FileAccess.READ)
		if file:
			var content: String
			if ext in ["png", "jpg", "jpeg", "webp", "mp3", "ogg", "wav", "ttf", "otf"]:
				content = "Binary file — path: " + path + "\nSize: " + str(file.get_length()) + " bytes"
			else:
				content = file.get_as_text()
			_attached_files.append({
				"type": "text",
				"filename": filename,
				"text_content": content
			})
			_refresh_thumbnails()
			_show_toast("[color=green]" + locale_manager.tr("text_file_attached") + filename + "[/color]")
		else:
			pass
			# File not directly accessible — attach path as reference
			_attached_files.append({
				"type": "text",
				"filename": filename,
				"text_content": "File reference: " + path + "\n(Could not read content directly)"
			})
			_refresh_thumbnails()
			_add_to_chat("\n[color=yellow][i]Attached reference: " + filename + "[/i][/color]\n")

func _is_game_running() -> bool:
	return EditorInterface.is_playing_scene()

func _process_send(prompt_text: String, is_execute_plan: bool = false, is_watch_mode: bool = false):
	if _is_game_running() and not is_watch_mode:
		_add_to_chat("
[color=orange][b]" + locale_manager.tr("game_running_warning") + "[/color]
", "system")
		return
	_is_stopped = false
	_watch_fix_count = 0
	
	# 1. UI 层显示原文（不含摘要）
	if not is_execute_plan:
		if _show_time_enabled:
			var _time_str: String = Time.get_datetime_string_from_system()
			prompt_text = "时间：" + _time_str + "

" + prompt_text
		_log_user_message(prompt_text, -1)
		input_field.text = ""
	else:
		_add_to_chat("
[color=cyan][b]" + locale_manager.tr("executing_plan") + "[/b][/color]
")
	
	var selection = {}
	if context_manager:
		selection = context_manager.get_selection_info()
	
	var final_prompt = prompt_text
	if not selection.is_empty() and not is_execute_plan:
		final_prompt = "Selection Context (File: " + selection.path + "):
```gdscript
" + selection.text + "
```

Command: " + prompt_text
		_add_to_chat("[i]Using selection from " + selection.path.get_file() + "...[/i]
")

	if plan_first_enabled and not is_execute_plan:
		final_prompt += "

CRITICAL INSTRUCTION: The user has enabled 'Plan First' mode. Do NOT output any tool calls to modify files yet. Instead, output a detailed, numbered step-by-step plan explaining exactly what tools you will use and what you will do. This is your planning phase."
		_plan_pending = true
	else:
		_plan_pending = false
		execute_plan_btn.visible = false

	var context = ""
	if context_enabled and context_manager:
		context += "Engine Info:
" + context_manager.get_engine_version_context() + "
"
		context += "Project Structure:
" + context_manager.get_project_index() + "
"
		context += "Project Settings:
" + context_manager.get_project_settings_dump() + "
"
		context += "Current Scene tree:
" + context_manager.get_scene_tree_dump() + "
"
		context += "Current Script content:
" + context_manager.get_current_script() + "
"
	
	if _memory_manager:
		var memory_text = _memory_manager.get_all_memories_formatted()
		if memory_text != "":
			context += "
" + memory_text + "
"
	
	if not _dropped_files.is_empty():
		context += "
--- Additional File Context ---
"
		for path in _dropped_files:
			if FileAccess.file_exists(path):
				var f = FileAccess.open(path, FileAccess.READ)
				if f:
					context += "File: " + path + "
"
					context += f.get_as_text() + "

"
	
	var files_data = []
	if not _attached_files.is_empty():
		for file in _attached_files:
			if file["type"] == "text":
				context += "
--- Attached File: " + file["filename"] + " ---
"
				context += file["text_content"] + "
"
			elif file["type"] == "image":
				var encoded = _encode_image(file["image_obj"])
				files_data.append(encoded)
			elif file["type"] == "binary":
				var base64 = Marshalls.raw_to_base64(file["raw_bytes"])
				files_data.append({
					"mime_type": file["mime_type"],
					"data": base64
				})
		_show_toast("[i]" + locale_manager.tr("sending_attachments") + "[/i]")
		_attached_files.clear()
		_refresh_thumbnails()
	
	if screenshot_enabled and context_manager:
		var scr = context_manager.get_editor_screenshot()
		if not scr.is_empty():
			files_data.append(scr)
			_show_toast("[i]" + locale_manager.tr("capturing_screenshot") + "[/i]")

	var tools = _get_filtered_tools()
	
	if gemini_client:
		# ─── 2. 若有摘要 → 拼到 final_prompt 前缀 ───
		var _sum: String = ""
		if has_method("_v61_get_summary_text"):
			_sum = _v61_get_summary_text()
		if _sum.strip_edges() != "":
			final_prompt = "【对话摘要（历史上下文，仅供参考，无需回应本段）】
" + \
				"───对话摘要───
" + _sum.strip_edges() + "
───对话摘要结束───

" + \
				"【当前请求】
" + final_prompt
		
		_last_send_payload = {
			"final_prompt": final_prompt,
			"context": context,
		}
		_retry_count = 0
		# 重建 history（只保留摘要之后的消息）
		if _sum.strip_edges() != "":
			if has_method("_v61_apply_summary_history"):
				_v61_apply_summary_history()
		gemini_client.send_prompt(final_prompt, context, tools, files_data)
		_set_tool_progress("💭 接收响应中…")
		_on_clear_dropped_files()
func _encode_image(image: Image) -> Dictionary:
	var max_dim = 1024
	if image.get_width() > max_dim or image.get_height() > max_dim:
		var scale = float(max_dim) / max(image.get_width(), image.get_height())
		image.resize(int(image.get_width() * scale), int(image.get_height() * scale))
	
	var buffer = image.save_png_to_buffer()
	var base64 = Marshalls.raw_to_base64(buffer)
	return {
		"mime_type": "image/png",
		"data": base64
	}

func _on_poll_timer_timeout():
	# 强制隐藏"当前选择"（防止任何路径复活）
	if selection_status != null and is_instance_valid(selection_status):
		selection_status.visible = false
	if watch_mode_enabled:
		_check_for_new_errors()
func _check_for_new_errors():
	var path = "user://logs/godot.log"
	if not FileAccess.file_exists(path): return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var length = file.get_length()
	file.close()
	
	if _last_log_size == 0:
		_last_log_size = length # Initial sync, don't trigger on old errors
		return
		
	if length > _last_log_size:
		pass
		# Log has grown, read new content
		file = FileAccess.open(path, FileAccess.READ)
		file.seek(_last_log_size)
		var new_content = file.get_buffer(length - _last_log_size).get_string_from_utf8()
		file.close()
		_last_log_size = length
		
		# Check for errors in new content
		if "ERROR:" in new_content or "SCRIPT ERROR:" in new_content:
			if gemini_client and not gemini_client.is_requesting:
				pass
				# Rate limiting: max fixes and cooldown
				if _watch_fix_count >= _WATCH_MAX_FIXES:
					_add_to_chat("\n[color=orange][b]" + locale_manager.tr("watch_max_limit").replace("{max}", str(_WATCH_MAX_FIXES)) + "[/b][/color]\n")
					return
				
				var now = Time.get_unix_time_from_system()
				if now < _watch_cooldown_until:
					return  # Still in cooldown
				
				_watch_fix_count += 1
				_watch_cooldown_until = now + _WATCH_COOLDOWN_SECS
				_add_to_chat("\n[color=orange][b]" + locale_manager.tr("watch_error_detected").replace("{current}", str(_watch_fix_count)).replace("{max}", str(_WATCH_MAX_FIXES)) + "[/b][/color]\n")
				
				if _is_game_running():
					EditorInterface.stop_playing_scene()
				
				_process_send("I noticed a new error in the console:\n" + new_content + "\n\nPlease analyze and fix it.", false, true)

func _on_tool_calls(tool_calls: Array):
	if _is_stopped:
		return
	_try_display_reasoning()
	
	batch_queue = tool_calls.duplicate()
	batch_results.clear()
	_batch_total = tool_calls.size()
	
	# 为每个 call 补上 8 位 id
	for i in range(batch_queue.size()):
		var c = batch_queue[i]
		if not c.has("id") or str(c["id"]) == "":
			c["id"] = _v34_gen_code()
	
	if not batch_queue.is_empty():
		var first_tool = batch_queue[0]
		var action_name = "AI Batch: " + first_tool.get("name", "Unknown")
		if _tool_executor.has_method("start_composite_action"):
			_tool_executor.start_composite_action(action_name)
		_process_next_batch_item()
func _process_next_batch_item():
	if _is_stopped:
		_clear_tool_progress()
		return
	if batch_queue.is_empty():
		_clear_tool_progress()
		return
	
	var call_data = batch_queue.pop_front()
	current_tool_context = call_data
	
	var tool_name: String = call_data["name"]
	var args: Dictionary = call_data["args"]
	var tool_id: String = str(call_data.get("id", ""))
	
	if tool_name == "undo_tool_call":
		var result: String = _v34_handle_undo(args) if has_method("_v34_handle_undo") else "UnDo 未启用"
		_on_tool_output(result)
		return
	
	var step: int = _batch_total - batch_queue.size()
	var progress: String = "[" + str(step) + "/" + str(_batch_total) + "] " if _batch_total > 1 else ""
	
	# 工具调用标题 + 参数 合并为一个折叠块（标题=工具名，内容=参数）
	var arg_str: String = str(args)
	var block_label: String = progress + "🛠️ " + tool_name
	_append_collapsible_block(block_label, arg_str, "dodgerblue", false)
	
	_set_tool_progress(progress + "执行 " + tool_name)
	
	var undo_code: String = _v34_backup_before_tool(tool_name, args, tool_id) if has_method("_v34_backup_before_tool") else ""
	if undo_code != "":
		_add_to_chat("[color=#888888][i]🔐 已备份，撤销码: " + undo_code + "[/i][/color]
", "ai")
	
	_tool_executor.execute_tool(tool_name, args)
func _on_tool_output(output: String):
	if _is_stopped:
		_clear_tool_progress()
		return
		
	var line_count = output.count("
") + 1
	var tool_name: String = ""
	if not current_tool_context.is_empty():
		tool_name = str(current_tool_context.get("name", ""))
	var label: String = "📤 " + (tool_name if tool_name != "" else "结果") + " (" + str(line_count) + " 行)"
	_append_collapsible_block(label, output, "green", false)
	
	if not current_tool_context.is_empty():
		var tool_id = current_tool_context.get("id", "")
		var response_part = gemini_client.generate_tool_response(current_tool_context["name"], output, tool_id)
		batch_results.append(response_part)
		current_tool_context = {}
	
	if not batch_queue.is_empty():
		await get_tree().process_frame
		_process_next_batch_item()
	else:
		if gemini_client and not batch_results.is_empty():
			var tools = _get_filtered_tools()
				
			var files_data = []
			if not _attached_files.is_empty():
				for file in _attached_files:
					if file["type"] == "image":
						files_data.append(_encode_image(file["image_obj"]))
					elif file["type"] == "binary":
						files_data.append({
							"mime_type": file["mime_type"],
							"data": Marshalls.raw_to_base64(file["raw_bytes"])
						})
				_attached_files.clear()
				_refresh_thumbnails()
				
			gemini_client.send_tool_responses(batch_results, tools, files_data)
			batch_results.clear()
			_set_tool_progress("💭 思考中...")
			
		if _tool_executor.has_method("commit_composite_action"):
			_tool_executor.commit_composite_action()
func _on_undo_pressed():
	if _tool_executor and _tool_executor.has_method("undo"):
		_tool_executor.undo()
		_add_to_chat("\n[i]" + locale_manager.tr("undoing_last") + "[/i]\n")

func _on_fix_console_pressed():
	var errors = _get_error_logs()
	if errors.is_empty():
		_add_to_chat("\n[i]" + locale_manager.tr("no_errors_found") + "[/i]\n")
		return
		
	var prompt = "Here are the errors from the current Godot session. Please analyze and fix them:\n\n" + errors
	_process_send(prompt)

func _get_error_logs() -> String:
	var path = "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return "Error: Log file not found at " + path + ". Please enable file logging in Project Settings."
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Could not open log file."
		
	var content = file.get_as_text()
	file.close()
	
	var session_start_index = content.rfind("Godot Engine v")
	if session_start_index != -1:
		content = content.substr(session_start_index)
	
	var lines = content.split("\n")
	var raw_error_blocks = []
	var capturing_error = false
	var current_error = ""
	
	for line in lines:
		if "ERROR:" in line or "SCRIPT ERROR:" in line or "USER SCRIPT ERROR:" in line:
			if capturing_error and current_error != "":
				raw_error_blocks.append(current_error)
			capturing_error = true
			current_error = line
		elif capturing_error:
			if line.begins_with(" ") or line.begins_with("\t") or line.begins_with("<"):
				current_error += "\n" + line
			else:
				if current_error != "":
					raw_error_blocks.append(current_error)
				capturing_error = false
				current_error = ""
				
	if capturing_error and current_error != "":
		raw_error_blocks.append(current_error)
		
	var unique_errors = {}
	var filtered_errors = []
	
	for err_block in raw_error_blocks:
		if not unique_errors.has(err_block):
			unique_errors[err_block] = true
			filtered_errors.append(err_block)
	
	if filtered_errors.is_empty():
		return ""
		
	return "\n\n".join(filtered_errors)

func _on_ai_response(response: String):
	# 用户在等待响应时终止 → 丢弃这条响应
	if _v69_retry_cancelled:
		_v69_cleanup_and_restore()
		return
	
	# 收到正常响应 → 停止重试
	_v69_stop_retry()
	_retry_count = 0
	_is_retrying = false
	_last_send_payload = {}
	_update_ui_state(false)
	
	if _is_stopped:
		return
	_try_display_reasoning()
	if response.strip_edges() != "":
		_add_to_chat(_markdown_to_bbcode(response) + "
", "ai")
	var extracted_calls = _extract_text_tool_calls(response)
	if not extracted_calls.is_empty():
		_on_tool_calls(extracted_calls)
		return
	_current_bubble = null
	_current_role = ""
	if _plan_pending:
		execute_plan_btn.visible = true
func _extract_text_tool_calls(text: String) -> Array:
	var calls = []
	
	# Pattern 1: <tool_call>{"arguments": {}, "name": "tool_name"}</tool_call>
	var regex1 = RegEx.new()
	regex1.compile("<tool_call>\\s*([\\s\\S]*?)\\s*</tool_call>")
	var matches1 = regex1.search_all(text)
	for m in matches1:
		var json_str = m.get_string(1).strip_edges()
		var parsed = JSON.parse_string(json_str)
		if parsed and typeof(parsed) == TYPE_DICTIONARY:
			var call_data = {
				"name": parsed.get("name", ""),
				"args": parsed.get("arguments", parsed.get("args", {}))
			}
			if call_data["name"] != "":
				calls.append(call_data)
	
	# Pattern 2: ```json\n{"name": "...", "arguments": {...}}\n```
	if calls.is_empty():
		var regex2 = RegEx.new()
		regex2.compile("```(?:json)?\\s*\\n\\s*(\\{[\\s\\S]*?\"name\"[\\s\\S]*?\\})\\s*\\n\\s*```")
		var matches2 = regex2.search_all(text)
		for m in matches2:
			var json_str = m.get_string(1).strip_edges()
			var parsed = JSON.parse_string(json_str)
			if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("name"):
				var call_data = {
					"name": parsed.get("name", ""),
					"args": parsed.get("arguments", parsed.get("args", {}))
				}
				if call_data["name"] != "":
					calls.append(call_data)
	
	return calls

func _strip_tool_call_text(text: String) -> String:
	var result = text
	# Strip <tool_call>...</tool_call>
	var regex1 = RegEx.new()
	regex1.compile("<tool_call>[\\s\\S]*?</tool_call>")
	result = regex1.sub(result, "", true)
	# Strip ```json tool blocks
	var regex2 = RegEx.new()
	regex2.compile("```(?:json)?\\s*\\n\\s*\\{[\\s\\S]*?\"name\"[\\s\\S]*?\\}\\s*\\n\\s*```")
	result = regex2.sub(result, "", true)
	return result

func _on_ai_error(error: String):
	# 用户终止
	if _v69_retry_cancelled or _is_stopped:
		_v69_cleanup_and_restore()
		_is_stopped = false
		return
	
	# ─── 无限重试 ───
	if _infinite_retry:
		if _v69_retry_active:
			# 已在重试中 → 忽略重复 error，不改按钮
			return
		if _last_send_payload.is_empty():
			_v69_cleanup_and_restore()
			return
		_v69_retry_count += 1
		var wait_s: float = 5.0 if _v69_retry_count <= 3 else 7.5
		_set_tool_progress("💭 接收响应中…（第 " + str(_v69_retry_count) + " 次，等待 " + str(int(wait_s)) + "s）")
		# 保持终止状态
		_update_ui_state(true)
		_v69_start_retry_wait(wait_s)
		return
	
	# ─── 普通 5 次重试 ───
	if _retry_count < _MAX_RETRIES and not _last_send_payload.is_empty():
		_retry_count += 1
		_is_retrying = true
		var delay: float = _RETRY_DELAY_STEP * float(_retry_count)
		_show_toast("[color=yellow]将在 " + str(int(delay)) + " 秒后重试 (" + str(_retry_count) + "/" + str(_MAX_RETRIES) + ")…[/color]")
		_set_tool_progress("⏳ " + str(int(delay)) + " 秒后重试 (" + str(_retry_count) + "/" + str(_MAX_RETRIES) + ")")
		_update_ui_state(true)
		await get_tree().create_timer(delay).timeout
		if _is_stopped:
			_v69_stop_retry()
			_is_stopped = false
			return
		if gemini_client and not _last_send_payload.is_empty():
			_update_ui_state(true)
			var tools = _get_filtered_tools()
			gemini_client.send_prompt(_last_send_payload["final_prompt"], _last_send_payload["context"], tools, [])
			_set_tool_progress("💭 接收响应中…（第 " + str(_retry_count) + " 次重试）")
		else:
			_v69_stop_retry()
	else:
		_show_toast("[color=red]Error: " + error + "[/color]")
		_v69_stop_retry()
func _log_user_message(msg: String, token_count: int = -1, insert_index: int = -1):
	_add_to_chat(msg + "
", "user", insert_index)
func _on_log_entry(entry: Dictionary):
	var color = "red" if entry.type == "error" else "gray"
	var msg = "\n[color=" + color + "][b]Engine " + entry.type.capitalize() + ":[/b] " + entry.message
	if entry.has("source") and entry.source.file:
		msg += " (" + entry.source.file.get_file() + ":" + str(entry.source.line) + ")"
	msg += "[/color]\n"
	_add_to_chat(msg)

func _markdown_to_bbcode(text: String) -> String:
	var result := ""
	var lines = text.split("
")
	var in_code_block := false
	var re_ul_bold_italic = RegEx.new()
	re_ul_bold_italic.compile("(?<![a-zA-Z0-9_])___([^_
]+?)___(?![a-zA-Z0-9_])")
	var re_ul_bold = RegEx.new()
	re_ul_bold.compile("(?<![a-zA-Z0-9_])__([^_
]+?)__(?![a-zA-Z0-9_])")
	var re_ul_italic = RegEx.new()
	re_ul_italic.compile("(?<![a-zA-Z0-9_])_([^_
]+?)_(?![a-zA-Z0-9_])")
	
	for line in lines:
		if line.strip_edges().begins_with("```"):
			if in_code_block:
				result += "[/code]
"
				in_code_block = false
			else:
				result += "[code]"
				in_code_block = true
			continue
		if in_code_block:
			result += line + "
"
			continue
		
		if line.begins_with("### "):
			result += "[b]" + line.substr(4) + "[/b]
"
			continue
		elif line.begins_with("## "):
			result += "
[b][color=#8be9fd]" + line.substr(3) + "[/color][/b]
"
			continue
		elif line.begins_with("# "):
			result += "
[b][color=#50fa7b][font_size=18]" + line.substr(2) + "[/font_size][/color][/b]
"
			continue
		
		if line.strip_edges().begins_with("- ") or line.strip_edges().begins_with("* "):
			var indent = line.length() - line.strip_edges().length()
			var prefix = "  ".repeat(indent / 2) + "• "
			line = prefix + line.strip_edges().substr(2)
		
		# 粗斜体
		if _regex_bold_italic != null:
			line = _regex_bold_italic.sub(line, "[b][i]$1[/i][/b]", true)
		if _regex_bold != null:
			line = _regex_bold.sub(line, "[b]$1[/b]", true)
		# 斜体 *text*
		if _regex_italic != null:
			line = _regex_italic.sub(line, "[i]$1[/i]", true)
		# 下划线系列
		line = re_ul_bold_italic.sub(line, "[b][i]$1[/i][/b]", true)
		line = re_ul_bold.sub(line, "[b]$1[/b]", true)
		line = re_ul_italic.sub(line, "[i]$1[/i]", true)
		if _regex_code != null:
			line = _regex_code.sub(line, "[code]$1[/code]", true)
		if _regex_suggest != null:
			line = _regex_suggest.sub(line, "[url=suggest:$1][b][color=#50fa7b] 💡 $1 [/color][/b][/url]", true)
		
		result += line + "
"
	
	if in_code_block:
		result += "[/code]
"
	return result
func _strip_response_prefix(text: String) -> String:
	var t: String = text.strip_edges()
	for _i in range(4):
		var lower: String = t.to_lower()
		if lower.begins_with("**response:**"):
			t = t.substr(13).strip_edges()
		elif lower.begins_with("**response**:"):
			t = t.substr(13).strip_edges()
		elif lower.begins_with("response:"):
			t = t.substr(9).strip_edges()
		elif lower.begins_with("response："):
			t = t.substr(9).strip_edges()
		elif lower.begins_with("[b]response:[/b]"):
			t = t.substr(17).strip_edges()
		else:
			break
	return t
func _on_confirmation_needed(message: String, _tool_name: String, _args: Dictionary):
	# 自动审批
	if _auto_approve:
		_show_toast("[color=green]自动审批通过： " + _tool_name + "[/color]")
		if _tool_executor:
			_tool_executor.confirm_pending_action()
		return
	_confirm_dialog.dialog_text = "[危险操作] " + message + "

" + locale_manager.tr("cannot_be_undone")
	_confirm_dialog.popup_centered()
func _on_destructive_confirmed():
	if _tool_executor:
		_tool_executor.confirm_pending_action()

func _on_destructive_cancelled():
	if _tool_executor:
		_tool_executor.cancel_pending_action()

func _find_current_footer() -> Label:
	var node: Node = _current_bubble
	while node != null:
		if node.has_meta("footer"):
			return node.get_meta("footer")
		node = node.get_parent()
	return null


func _on_custom_prompt_changed():
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("gamedev_ai/custom_system_prompt", custom_prompt_input.text)
	if gemini_client:
		gemini_client.custom_instructions = custom_prompt_input.text

# Drag & Drop Handlers
func _can_drop_data_fw(_at_pos: Vector2, data: Variant) -> bool:
	return _can_drop_data(_at_pos, data)

func _drop_data_fw(_at_pos: Vector2, data: Variant):
	_drop_data(_at_pos, data)

func _can_drop_data(_at_pos: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY:
		if data.has("type"):
			if data["type"] in ["files", "nodes", "resource", "obj"]:
				return true
		# Also accept bare 'files' or 'nodes' keys (Godot 4 drag format)
		if data.has("files") or data.has("nodes"):
			return true
	return false

func _drop_data(_at_pos: Vector2, data: Variant):
	if typeof(data) != TYPE_DICTIONARY:
		return

	# --- Node drops (Scene Tree) ---
	# Handle bare 'nodes' key (Godot 4 scene tree drag) as rich context
	var node_paths_raw: Array = []
	if data.has("nodes") and (not data.has("type") or data.get("type") == "nodes"):
		node_paths_raw = data["nodes"]
	elif data.get("type", "") == "nodes" and data.has("nodes"):
		node_paths_raw = data["nodes"]

	if not node_paths_raw.is_empty():
		var editor_root = EditorInterface.get_edited_scene_root()
		var lines: Array = []
		var node_names: Array = []
		for np in node_paths_raw:
			var node = editor_root.get_node_or_null(np) if editor_root else null
			if node:
				var script = node.get_script()
				var script_path = script.resource_path if (script and script.resource_path != "") else "(no script)"
				var scene_path = node.scene_file_path if node.scene_file_path != "" else "(no scene file)"
				lines.append("Node: " + node.name + "  |  Type: " + node.get_class() + "  |  Path: " + str(np) + "  |  Scene: " + scene_path + "  |  Script: " + script_path)
				node_names.append(node.name)
			else:
				lines.append("Node path: " + str(np))
				var path_str = str(np)
				var last_slash = path_str.rfind("/")
				if last_slash != -1:
					node_names.append(path_str.substr(last_slash + 1))
				else:
					node_names.append(path_str)

		var label = ""
		if node_names.size() == 1:
			label = node_names[0]
		elif node_names.size() <= 3:
			label = ", ".join(node_names)
		else:
			label = str(node_paths_raw.size()) + " nodes"

		_attached_files.append({
			"type": "text",
			"filename": label,
			"text_content": "## Dragged Nodes from Scene Tree\n\n" + "\n".join(lines)
		})
		_refresh_thumbnails()
		_add_to_chat("\n[color=green][i]Attached " + label + "[/i][/color]\n")
		_update_dropped_files_ui()
		return

	# --- File / Resource drops ---
	var paths_to_add: Array[String] = []

	if data.has("type"):
		match data["type"]:
			"files":
				if data.has("files"):
					paths_to_add.append_array(data["files"])
			"resource":
				var res = data.get("resource")
				if res and res.resource_path != "":
					paths_to_add.append(res.resource_path)
			"obj":
				var obj = data.get("object")
				if obj is Resource and obj.resource_path != "":
					paths_to_add.append(obj.resource_path)
				elif obj is Node:
					if obj.scene_file_path != "":
						paths_to_add.append(obj.scene_file_path)
					var script = obj.get_script()
					if script and script.resource_path != "":
						paths_to_add.append(script.resource_path)

	# Fallback: bare 'files' key
	if paths_to_add.is_empty() and data.has("files"):
		paths_to_add.append_array(data["files"])

	# Route ALL file types through _attach_file_from_path for full content
	for f in paths_to_add:
		_attach_file_from_path(f)

	_update_dropped_files_ui()

func _update_dropped_files_ui():
	if _dropped_files.is_empty():
		_file_preview_container.visible = false
	else:
		_file_preview_container.visible = true
		var file_names = []
		for f in _dropped_files:
			file_names.append(f.get_file())
		_file_preview_label.text = "[color=cyan]Files attached:[/color] " + ", ".join(file_names)

func _on_clear_dropped_files():
	_dropped_files.clear()
	_update_dropped_files_ui()

func _on_diff_preview_requested(path: String, old_content: String, new_content: String, tool_name: String, _args: Dictionary):
	# 完全自动化 → 直接 apply
	if _full_auto:
		_show_toast("[color=orange]完全自动化：直接应用 " + tool_name + "[/color]")
		if _tool_executor:
			_tool_executor.confirm_pending_action()
		return
	_diff_preview_panel.visible = true
	if _diff_preview_panel.get_parent() != chat_vbox:
		_diff_preview_panel.reparent(chat_vbox)
	chat_vbox.move_child(_diff_preview_panel, -1)
	_diff_display.scroll_following = false
	_diff_display.clear()
	_diff_display.append_text("[b]Modifying: " + path + "[/b] (" + tool_name + ")
")
	if tool_name == "patch_script" or tool_name == "replace_selection":
		_diff_display.append_text("[color=red][s]" + _markdown_to_bbcode(old_content) + "[/s][/color]
")
		_diff_display.append_text("[color=green]" + _markdown_to_bbcode(new_content) + "[/color]
")
	else:
		_diff_display.append_text(_markdown_to_bbcode(new_content))
	await get_tree().process_frame
	var v_scroll = _diff_display.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value = 0
func _on_apply_diff_pressed():
	_diff_preview_panel.visible = false
	if _tool_executor:
		_tool_executor.confirm_pending_action()

func _on_skip_diff_pressed():
	_diff_preview_panel.visible = false
	if _tool_executor:
		_tool_executor.cancel_pending_action()

func _on_filesystem_changed():
	var valid_files: Array[String] = []
	for f in _dropped_files:
		if FileAccess.file_exists(f):
			valid_files.append(f)
			
	if valid_files.size() != _dropped_files.size():
		_dropped_files = valid_files
		_update_dropped_files_ui()

func _on_meta_clicked(meta):
	var meta_str = str(meta)
	if meta_str.begins_with("suggest:"):
		var suggestion = meta_str.substr(8)
		input_field.text = suggestion
		_on_send_pressed()
	elif meta_str.begins_with("toggle_block:"):
		var block_id = meta_str.substr(13).to_int()
		_toggle_block(block_id)
	else:
		OS.shell_open(meta_str)

func _append_collapsible_block(label: String, content: String, color: String, expanded: bool):
	var id = _next_block_id
	_next_block_id += 1
	var safe_content = content.replace("[", "[lb]")
	_block_data[id] = {
		"label": label,
		"content": safe_content,
		"color": color,
		"expanded": expanded,
		"bubble_ref": null
	}
	_add_to_chat(_get_block_bbcode(id), "ai")
	_block_data[id]["bubble_ref"] = _current_bubble
func _get_block_bbcode(id: int) -> String:
	var data = _block_data[id]
	var icon = "▼ " if data.expanded else "▶ "
	var bb = "
[color=" + data.color + "][url=toggle_block:" + str(id) + "]" + icon + data.label + "[/url][/color]
"
	if data.expanded:
		bb += "[indent][color=#888888][i]" + data.content + "[/i][/color][/indent]
"
	return bb
func _toggle_block(id: int):
	if not _block_data.has(id): return
	var data = _block_data[id]
	var old_bb = _get_block_bbcode(id)
	data.expanded = !data.expanded
	var new_bb = _get_block_bbcode(id)
	_chat_log_bbcode = _chat_log_bbcode.replace(old_bb, new_bb)
	if data.has("bubble_ref") and is_instance_valid(data.bubble_ref):
		var current_bb = data.bubble_ref.get_meta("raw_bbcode", "")
		var fixed_bb = current_bb.replace(old_bb, new_bb)
		data.bubble_ref.set_meta("raw_bbcode", fixed_bb)
		data.bubble_ref.text = fixed_bb
func _add_to_chat(bbcode: String, role: String = "ai", insert_index: int = -1):
	pass
	# system 归一到 ai（同一种视觉，合并到同一气泡）
	if role == "system":
		role = "ai"
	
	# error 强制断开当前气泡 → 下一次创建新气泡
	if role == "error":
		_current_bubble = null
		_current_role = ""
	
	_chat_log_bbcode += bbcode
	
	if _current_bubble == null or _current_role != role:
		_create_chat_bubble(role, insert_index)
		
	_current_bubble.append_text(bbcode)
	
	var current_bb = _current_bubble.get_meta("raw_bbcode", "")
	_current_bubble.set_meta("raw_bbcode", current_bb + bbcode)
	
	if insert_index == -1:
		await get_tree().process_frame
		var v_scroll = chat_scroll.get_v_scroll_bar()
		if v_scroll:
			var near_bottom: bool = (v_scroll.max_value - v_scroll.value - v_scroll.page) < 100
			if near_bottom:
				v_scroll.value = v_scroll.max_value
func _create_chat_bubble(role: String, insert_index: int = -1):
	_current_role = role
	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 2)
	var outer = HBoxContainer.new()
	outer.size_flags_horizontal = SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 12)
	wrapper.add_child(outer)
	var footer = Label.new()
	footer.name = "Footer"
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.visible = false
	wrapper.add_child(footer)
	var avatar_holder = PanelContainer.new()
	var avatar_style = StyleBoxFlat.new()
	avatar_style.bg_color = Color(0.95, 0.95, 0.95)
	avatar_style.set_corner_radius_all(20)
	avatar_style.content_margin_left = 4
	avatar_style.content_margin_right = 4
	avatar_style.content_margin_top = 4
	avatar_style.content_margin_bottom = 4
	avatar_holder.add_theme_stylebox_override("panel", avatar_style)
	avatar_holder.custom_minimum_size = Vector2(40, 40)
	avatar_holder.size_flags_horizontal = SIZE_SHRINK_BEGIN
	avatar_holder.size_flags_vertical = SIZE_SHRINK_BEGIN
	var avatar = TextureRect.new()
	avatar.custom_minimum_size = Vector2(32, 32)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_holder.add_child(avatar)
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_child(text_vbox)
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	if has_method("_on_meta_clicked"):
		label.meta_clicked.connect(_on_meta_clicked)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	_current_bubble = label
	text_vbox.add_child(label)
	if _current_font_size != 14:
		label.add_theme_font_size_override("normal_font_size", _current_font_size)
		label.add_theme_font_size_override("bold_font_size", _current_font_size)
		label.add_theme_font_size_override("italics_font_size", _current_font_size)
		label.add_theme_font_size_override("bold_italics_font_size", _current_font_size)
		label.add_theme_font_size_override("mono_font_size", _current_font_size)
	var action_hbox = HBoxContainer.new()
	action_hbox.size_flags_horizontal = SIZE_SHRINK_END
	action_hbox.add_theme_constant_override("separation", 4)
	var icon_base: String = "res://addons/gamedev_ai/assets/icons/"
	
	if role == "ai" or role == "system":
		var sum_btn = Button.new()
		sum_btn.flat = true
		sum_btn.custom_minimum_size = Vector2(28, 28)
		sum_btn.icon = _load_svg_icon(icon_base + "compress.svg", "b0b0b0", 0.65)
		if sum_btn.icon == null:
			sum_btn.text = "📄"
		sum_btn.tooltip_text = "总结对话（压缩上下文）"
		sum_btn.pressed.connect(func(): _v61_generate_summary(wrapper))
		action_hbox.add_child(sum_btn)
	
	var copy_btn = Button.new()
	copy_btn.flat = true
	copy_btn.custom_minimum_size = Vector2(28, 28)
	copy_btn.icon = _load_svg_icon(icon_base + "copy.svg", "b0b0b0", 0.65)
	if copy_btn.icon == null:
		copy_btn.text = "📋"
	copy_btn.tooltip_text = "复制"
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(label.get_parsed_text())
		_show_toast("[color=green]已复制[/color]")
	)
	action_hbox.add_child(copy_btn)
	
	var edit_msg_btn = Button.new()
	edit_msg_btn.flat = true
	edit_msg_btn.custom_minimum_size = Vector2(28, 28)
	edit_msg_btn.icon = _load_svg_icon(icon_base + "edit.svg", "8ab4f8", 0.65)
	if edit_msg_btn.icon == null:
		edit_msg_btn.text = "✎"
	edit_msg_btn.tooltip_text = "编辑"
	action_hbox.add_child(edit_msg_btn)
	
	var del_msg_btn = Button.new()
	del_msg_btn.flat = true
	del_msg_btn.custom_minimum_size = Vector2(28, 28)
	del_msg_btn.icon = _load_svg_icon(icon_base + "delete.svg", "ff8a80", 0.65)
	if del_msg_btn.icon == null:
		del_msg_btn.text = "✖"
	del_msg_btn.tooltip_text = "删除"
	action_hbox.add_child(del_msg_btn)
	
	text_vbox.add_child(action_hbox)
	
	if role == "user":
		style.bg_color = Color(0.18, 0.22, 0.3)
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 2
		var user_tex = load("res://addons/gamedev_ai/assets/user_icon.svg")
		if user_tex:
			avatar.texture = user_tex
			avatar.modulate = Color(0.3, 0.4, 0.6)
		outer.add_child(panel)
		outer.add_child(avatar_holder)
	else:
		style.bg_color = Color(0.12, 0.13, 0.16, 0.7)
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 12
		var ai_tex = load("res://addons/gamedev_ai/assets/ai_icon.png")
		if ai_tex:
			avatar.texture = ai_tex
		outer.add_child(avatar_holder)
		outer.add_child(panel)
	
	wrapper.set_meta("label", label)
	wrapper.set_meta("role", role)
	wrapper.set_meta("footer", footer)
	wrapper.set_meta("created_at", Time.get_datetime_string_from_system(false, true))
	wrapper.set_meta("updated_at", wrapper.get_meta("created_at"))
	
	if _show_time_enabled:
		footer.visible = true
		footer.text = str(wrapper.get_meta("created_at"))
	
	edit_msg_btn.pressed.connect(_on_edit_message_pressed.bind(wrapper, label))
	del_msg_btn.pressed.connect(_on_delete_message_pressed.bind(wrapper))
	
	# ★ 直接加入，无 tween，无 modulate 动画
	chat_vbox.add_child(wrapper)
	if insert_index != -1:
		chat_vbox.move_child(wrapper, insert_index)
func _clear_chat():
	_chat_log_bbcode = ""
	_current_bubble = null
	for child in chat_vbox.get_children():
		if child == _diff_preview_panel:
			child.visible = false
			continue
		child.queue_free()


# ═══════════════════════════════════════════════════════════════
# 消息编辑 / 删除
# ═══════════════════════════════════════════════════════════════

func _setup_edit_dialog():
	_edit_dialog = AcceptDialog.new()
	_edit_dialog.title = "编辑消息"
	_edit_dialog.ok_button_text = "保存"
	_edit_dialog.confirmed.connect(_on_edit_save)
	_edit_dialog.add_button("编辑并重发", true, "edit_resend")
	_edit_dialog.add_button("取消", true, "cancel")
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(320, 180)
	_edit_input = TextEdit.new()
	_edit_input.custom_minimum_size = Vector2(300, 160)
	_edit_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_edit_input)
	_edit_dialog.add_child(vbox)
	
	add_child(_edit_dialog)


func _find_label_in_bubble(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node
	for child in node.get_children():
		var result = _find_label_in_bubble(child)
		if result:
			return result
	return null


func _on_edit_save():
	if not _edit_target_bubble or not is_instance_valid(_edit_target_bubble):
		return
	var new_text: String = _edit_input.text
	var label = _edit_target_bubble.get_meta("label", null)
	if label and is_instance_valid(label):
		var old_bb = label.get_meta("raw_bbcode", "")
		var new_bb = _markdown_to_bbcode(new_text).strip_edges() + "\n"
		label.text = new_bb
		label.set_meta("raw_bbcode", new_bb)
		if old_bb != "":
			_chat_log_bbcode = _chat_log_bbcode.replace(old_bb, new_bb)
	_edit_target_bubble = null


func _apply_all_icons():
	var base: String = "res://addons/gamedev_ai/assets/icons/"
	_apply_icon_to(summarize_btn, base + "save.svg", "💾")
	_apply_icon_to(add_file_btn, base + "attach.svg", "📎")
	_apply_icon_to(prompt_settings_btn, base + "settings.svg", "⚙")
	_apply_icon_to(send_button, base + "send.svg", "➤")
	_apply_icon_to(execute_plan_btn, base + "plus.svg", "▶")
	
	var add_preset_btn = find_child("AddPresetBtn", true, false)
	var del_preset_btn = find_child("DelPresetBtn", true, false)
	_apply_icon_to(add_preset_btn, base + "plus.svg", "")
	_apply_icon_to(edit_preset_btn, base + "rename.svg", "")
	_apply_icon_to(del_preset_btn, base + "delete.svg", "")
	
	_apply_icon_to(_apply_diff_btn, base + "send.svg", "")
	_apply_icon_to(_skip_diff_btn, base + "delete.svg", "")


func _apply_icon_to(btn, path: String, fallback_text: String = ""):
	if btn == null:
		return
	var tex = _load_svg_icon(path, "ffffff", 0.75)
	if tex != null:
		btn.icon = tex
		# 如果按钮原本就带着 fallback 文本且当前是空，清空
		if fallback_text != "" and btn.text == fallback_text:
			btn.text = ""
	elif fallback_text != "":
		btn.text = fallback_text


func _apply_custom_theme():
	pass
	# Keep only the margins that were requested by the user
	
	# Tab padding and spacing
	var tabbar_bg = StyleBoxFlat.new()
	tabbar_bg.bg_color = Color(0.08, 0.09, 0.12) # Dark background for the tab bar
	tabbar_bg.content_margin_top = 10 # Spacing above tabs
	$TabContainer.add_theme_stylebox_override("tabbar_background", tabbar_bg)
	
	# Remove custom tab colors so it uses editor default colors
	if $TabContainer.has_theme_stylebox_override("tab_unselected"):
		$TabContainer.remove_theme_stylebox_override("tab_unselected")
	if $TabContainer.has_theme_stylebox_override("tab_selected"):
		$TabContainer.remove_theme_stylebox_override("tab_selected")

	var tab_panel = StyleBoxEmpty.new()
	tab_panel.content_margin_left = 12
	tab_panel.content_margin_right = 12
	tab_panel.content_margin_top = 12
	tab_panel.content_margin_bottom = 12
	$TabContainer.add_theme_stylebox_override("panel", tab_panel)
	
	# Margins for chat actions
	var chat_container = $TabContainer/Chat
	chat_container.add_theme_constant_override("separation", 12)
	
	# Chat output display padding
	var output_style = StyleBoxFlat.new()
	output_style.bg_color = Color(0, 0, 0, 0.15) # subtle dark background for readability
	output_style.corner_radius_top_left = 8
	output_style.corner_radius_top_right = 8
	output_style.corner_radius_bottom_right = 8
	output_style.corner_radius_bottom_left = 8
	output_style.content_margin_left = 12
	output_style.content_margin_top = 12
	output_style.content_margin_right = 12
	output_style.content_margin_bottom = 12
	chat_scroll.add_theme_stylebox_override("panel", output_style)
	
	# Input field padding
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.1, 0.11, 0.14)
	input_style.border_width_left = 1
	input_style.border_width_top = 1
	input_style.border_width_right = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.25, 0.27, 0.35)
	input_style.corner_radius_top_left = 12
	input_style.corner_radius_top_right = 12
	input_style.corner_radius_bottom_right = 12
	input_style.corner_radius_bottom_left = 12
	input_style.content_margin_left = 16
	input_style.content_margin_right = 16
	input_style.content_margin_top = 12
	input_style.content_margin_bottom = 35 # Extra space for toolbar
	
	input_field.add_theme_stylebox_override("normal", input_style)
	input_field.add_theme_stylebox_override("focus", input_style)
	
	# Circular Send Button Style
	var send_style = StyleBoxFlat.new()
	send_style.bg_color = Color(0.15, 0.6, 0.35)
	send_style.corner_radius_top_left = 20
	send_style.corner_radius_top_right = 20
	send_style.corner_radius_bottom_right = 20
	send_style.corner_radius_bottom_left = 20
	send_style.shadow_color = Color(0, 0, 0, 0.3)
	send_style.shadow_size = 4
	send_style.shadow_offset = Vector2(0, 2)
	
	send_button.add_theme_stylebox_override("normal", send_style)
	send_button.add_theme_stylebox_override("hover", send_style)
	send_button.add_theme_stylebox_override("pressed", send_style)
	
	_apply_all_icons()
	_apply_all_icons()
	
	if magic_actions_btn != null: magic_actions_btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	if prompt_settings_btn != null: prompt_settings_btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	
	# Secondary toolbar style
	var ghost_style = StyleBoxEmpty.new()
	ghost_style.content_margin_left = 8
	ghost_style.content_margin_right = 8
	
	add_file_btn.add_theme_stylebox_override("normal", ghost_style)
	prompt_settings_btn.add_theme_stylebox_override("normal", ghost_style)
	
	_style_solid_button(execute_plan_btn, Color(0.2, 0.6, 0.3))
	_style_solid_button(_apply_diff_btn, Color(0.2, 0.6, 0.3))
	
	_style_solid_button(_skip_diff_btn, Color(0.4, 0.4, 0.45))
	_style_solid_button(_file_clear_btn, Color(0.5, 0.3, 0.3))
	
	_style_solid_button(font_size_minus_btn, Color(0.3, 0.35, 0.4))
	_style_solid_button(font_size_plus_btn, Color(0.3, 0.35, 0.4))
	
	# Force horizontal expansion for all tabs and their internals
	$TabContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in $TabContainer.get_children():
		if child is Control:
			if child != null: child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if String(child.name) != "Settings":
				_force_expansion_recursive(child)
	
	# ── Phase 2: Settings Cards ──
	_apply_settings_cards()

# ═══════════════════════════════════════════════════════════════
# 收缩 Chat / Settings 页宽度
# ═══════════════════════════════════════════════════════════════




	# CloseEditBtn 居中（避免被 VScrollBar 遮住）
	if close_edit_btn != null:
		var ceb_parent = close_edit_btn.get_parent()
		if ceb_parent is HBoxContainer:
			ceb_parent.alignment = BoxContainer.ALIGNMENT_CENTER
func _shrink_tab_widths():
	var tc = $TabContainer
	var chat_tab = tc.get_node_or_null("Chat")
	var settings_tab = tc.get_node_or_null("Settings")
	if chat_tab:
		chat_tab.clip_contents = true
		chat_tab.custom_minimum_size = Vector2(200, 0)
		_shrink_controls_recursive(chat_tab)
	if settings_tab:
		settings_tab.clip_contents = true
		settings_tab.custom_minimum_size = Vector2(150, 0)
		_shrink_controls_recursive(settings_tab)


func _shrink_controls_recursive(node: Node):
	if node is LineEdit:
		node.custom_minimum_size = Vector2(0, node.custom_minimum_size.y)
	elif node is TextEdit:
		node.custom_minimum_size = Vector2(0, node.custom_minimum_size.y)
	elif node is RichTextLabel:
		node.custom_minimum_size = Vector2(0, node.custom_minimum_size.y)
	for child in node.get_children():
		_shrink_controls_recursive(child)
func _load_svg_icon(path: String, color_hex: String, scale: float = 1.0) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return null
	var svg_content = file.get_as_text()
	svg_content = svg_content.replace("currentColor", "#" + color_hex)
	var img = Image.new()
	var err = img.load_svg_from_string(svg_content, scale)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null

func _force_expansion_recursive(node: Node):
	if node is Control:
		if node is Container:
			if node != null: node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for child in node.get_children():
			_force_expansion_recursive(child)

func _style_solid_button(btn: Control, bg_color: Color, corner: int = 6):
	if not is_instance_valid(btn):
		return
	var normal = StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.corner_radius_top_left = corner
	normal.corner_radius_top_right = corner
	normal.corner_radius_bottom_right = corner
	normal.corner_radius_bottom_left = corner
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	
	var hover = normal.duplicate()
	hover.bg_color = bg_color.lightened(0.2)
	
	var pressed = normal.duplicate()
	pressed.bg_color = bg_color.darkened(0.2)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _style_danger_button(btn: Control, corner: int = 6):
	_style_solid_button(btn, Color(0.7, 0.2, 0.2), corner)

func _style_ghost_danger_button(btn: Control):
	if not is_instance_valid(btn):
		return
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = Color(0.8, 0.25, 0.25, 0.6)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	
	var hover = normal.duplicate()
	hover.bg_color = Color(0.7, 0.2, 0.2, 0.15)
	hover.border_color = Color(0.9, 0.3, 0.3, 0.8)
	
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.7, 0.2, 0.2, 0.3)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))

func _make_card_style(bg_color: Color = Color(0.14, 0.15, 0.19), border_color: Color = Color(0.25, 0.27, 0.35, 0.4)) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _wrap_in_card(parent: Control, children: Array, title_key: String, bg_color: Color = Color(0.14, 0.15, 0.19), border_color: Color = Color(0.25, 0.27, 0.35, 0.4)) -> PanelContainer:
	var card = PanelContainer.new()
	if card != null: card.size_flags_horizontal = Control.SIZE_FILL
	card.clip_contents = true
	card.add_theme_stylebox_override("panel", _make_card_style(bg_color, border_color))
	
	var vbox = VBoxContainer.new()
	if vbox != null: vbox.size_flags_horizontal = Control.SIZE_FILL
	vbox.add_theme_constant_override("separation", 8)
	
	# 标题
	if title_key != "":
		var title_label = Label.new()
		title_label.text = locale_manager.tr(title_key) if locale_manager else title_key
		title_label.set_meta("tr_key", title_key)
		title_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		vbox.add_child(title_label)
		_card_titles.append(title_label)
	
	# 计算插入位置
	var insert_idx = -1
	for child in children:
		if is_instance_valid(child) and child.get_parent() == parent:
			var idx = child.get_index()
			if insert_idx == -1 or idx < insert_idx:
				insert_idx = idx
	
	# 转移子节点
	for child in children:
		if is_instance_valid(child):
			child.reparent(vbox)
	
	card.add_child(vbox)
	if insert_idx >= 0 and insert_idx < parent.get_child_count():
		parent.add_child(card)
		parent.move_child(card, insert_idx)
	else:
		parent.add_child(card)
	
	return card
func _setup_magic_row():
	var chat_tab = $TabContainer/Chat
	if chat_tab == null or selection_status == null:
		return
	if selection_status.get_parent() != chat_tab:
		selection_status.reparent(chat_tab)
	var input_vbox = chat_tab.get_node_or_null("InputVBox")
	if input_vbox != null:
		var idx: int = input_vbox.get_index()
		if idx >= 0:
			chat_tab.move_child(selection_status, idx)
	selection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if selection_status != null: selection_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_status.clip_text = true
	selection_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
func _apply_settings_cards():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	
	var scroll = settings_tab.get_node_or_null("SettingsScroll")
	var inner: VBoxContainer = null
	
	if scroll == null:
		var existing: Array = []
		for c in settings_tab.get_children():
			existing.append(c)
		
		scroll = ScrollContainer.new()
		scroll.name = "SettingsScroll"
		if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.clip_contents = true
		settings_tab.add_child(scroll)
		
		inner = VBoxContainer.new()
		inner.name = "SettingsContent"
		if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_theme_constant_override("separation", 12)
		scroll.add_child(inner)
		
		for c in existing:
			c.reparent(inner)
	else:
		if scroll is ScrollContainer:
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inner = scroll.find_child("SettingsContent", true, false)
		if inner == null:
			inner = VBoxContainer.new()
			inner.name = "SettingsContent"
			if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inner.add_theme_constant_override("separation", 12)
			scroll.add_child(inner)
	
	_flatten_all_cards(inner)
	_ensure_api_title(inner)
	_normalize_settings_flags(inner)


func _flatten_all_cards(root: Node):
	# 递归遍历，把 PanelContainer 的内容提到它的位置
	var changed := true
	var guard := 0
	while changed and guard < 20:
		guard += 1
		changed = false
		var stack: Array = [root]
		while not stack.is_empty():
			var parent = stack.pop_back()
			for c in parent.get_children():
				if c is PanelContainer:
					var contents: Array = []
					for sub in c.get_children():
						if sub is VBoxContainer or sub is HBoxContainer:
							for g in sub.get_children():
								# 跳过 tr_key 标题
								if g is Label and g.has_meta("tr_key"):
									g.queue_free()
									continue
								contents.append(g)
						else:
							contents.append(sub)
					var idx: int = c.get_index()
					for cc in contents:
						if is_instance_valid(cc):
							cc.reparent(parent)
							parent.move_child(cc, idx)
							idx += 1
					c.queue_free()
					changed = true
					break
				else:
					stack.append(c)


func _ensure_api_title(inner: VBoxContainer):
	var existing = inner.get_node_or_null("ApiConfigTitle")
	if existing != null:
		return
	var preset_bar = inner.get_node_or_null("PresetBar")
	if preset_bar == null:
		return
	var t := Label.new()
	t.name = "ApiConfigTitle"
	t.text = "API 配置"
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(t)
	inner.move_child(t, preset_bar.get_index())


func _flatten_cards(container: Node):
	var cards: Array = []
	for c in container.get_children():
		if c is PanelContainer:
			cards.append(c)
	for card in cards:
		var contents: Array = []
		for sub in card.get_children():
			if sub is VBoxContainer:
				for inner_child in sub.get_children():
					if inner_child is Label and inner_child.has_meta("tr_key"):
						inner_child.queue_free()
						continue
					contents.append(inner_child)
		var idx: int = card.get_index()
		for c in contents:
			if is_instance_valid(c):
				c.reparent(container)
				container.move_child(c, idx)
				idx += 1
		card.queue_free()


func _add_api_title(inner: VBoxContainer):
	if inner.get_node_or_null("ApiConfigTitle") != null:
		return
	var preset_bar = inner.get_node_or_null("PresetBar")
	if preset_bar == null:
		return
	var t := Label.new()
	t.name = "ApiConfigTitle"
	t.text = "API 配置"
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(t)
	inner.move_child(t, preset_bar.get_index())


func _normalize_settings_flags(root: Node):
	if root is Control:
		if root is VBoxContainer or root is HBoxContainer \
			or root is GridContainer or root is PanelContainer \
			or root is MarginContainer:
			if root != null: root.size_flags_horizontal = Control.SIZE_FILL
	for child in root.get_children():
		_normalize_settings_flags(child)


func _add_action_icons():
	var btn_map = {
		$TabContainer/Chat/ActionsContainer/RefactorBtn: "✧ ",
		$TabContainer/Chat/ActionsContainer/FixBtn: "� ",
		$TabContainer/Chat/ActionsContainer/ExplainBtn: "💡 ",
		$TabContainer/Chat/ActionsContainer/UndoBtn: "↶ ",
		$TabContainer/Chat/ActionsContainer/FixConsoleBtn: "⌨ ",
	}
	for btn in btn_map.keys():
		var icon_prefix = btn_map[btn]
		if not btn.text.begins_with(icon_prefix.left(1)):
			btn.text = icon_prefix + btn.text

# --- Copy functionality (legacy stubs - copy is now per-bubble) ---
func _setup_copy_features():
	pass

func _on_output_display_gui_input(_event: InputEvent):
	pass

func _check_floating_copy_btn():
	pass

func _on_copy_popup_id_pressed(_id: int):
	pass

func _on_floating_copy_pressed():
	pass

func _perform_copy():
	pass

# ===================== VECTOR DB UI =====================
func _on_scan_changes_pressed():
	if not _tool_executor or not _tool_executor.vector_db:
		return
	
	
	var result = _tool_executor.vector_db.scan_changes()
	var bbcode = ""
	
	# New or modified (yellow)
	for path in result["new_or_modified"]:
		bbcode += "[color=yellow]● NEW/MOD [/color] " + path + "\n"
	
	# Moved/renamed (blue)
	for m in result["moved"]:
		bbcode += "[color=dodgerblue]➜ MOVED  [/color] " + m["old"] + " → " + m["new"] + "\n"
	
	# Deleted (red)
	for path in result["deleted"]:
		bbcode += "[color=red]✖ DELETED[/color] " + path + "\n"
	
	# Retained (green) - show count only to avoid clutter
	var retained_count = result["retained"].size()
	if retained_count > 0:
		bbcode += "[color=green]✔ " + str(retained_count) + " file(s) unchanged (retained)[/color]\n"
	
	if bbcode == "":
		bbcode = "[color=gray]No script files found in the project.[/color]"
	
	# Summary line
	var total = result["retained"].size() + result["moved"].size() + result["new_or_modified"].size() + result["deleted"].size()
	bbcode += "\n[b]Total: " + str(total) + " files[/b] | "
	bbcode += "[color=yellow]" + str(result["new_or_modified"].size()) + " to embed[/color] | "
	bbcode += "[color=dodgerblue]" + str(result["moved"].size()) + " moved[/color] | "
	bbcode += "[color=red]" + str(result["deleted"].size()) + " deleted[/color]"
	

func _on_index_codebase_pressed():
	pass

func _on_index_confirmed():
	if not _tool_executor or not _tool_executor.vector_db:
		return
	_tool_executor.vector_db.index_project()

var _vdb_messages: Array = []

func _on_vector_db_output(text: String):
	_vdb_messages.append(text)
	# The final message contains "complete" — show the result popup
	if "complete" in text.to_lower():
		var full_msg = "\n".join(_vdb_messages)
		_vdb_messages.clear()

# ===================== ENHANCE INSTRUCTIONS =====================
func _on_enhance_prompt_pressed():
	var raw_text = custom_prompt_input.text.strip_edges()
	if raw_text == "":
		_show_enhance_error("Please write some instructions first before enhancing.")
		return
	
	
	# Create a one-shot HTTPRequest if not already created
	if not _enhance_http:
		_enhance_http = HTTPRequest.new()
		_enhance_http.use_threads = true
		_enhance_http.timeout = 360.0
		add_child(_enhance_http)
		_enhance_http.request_completed.connect(_on_enhance_request_completed)
	
	# Build the one-shot request using the active preset
	var preset = presets.get(active_preset_name, {})
	var provider = preset.get("provider", 0)
	var api_key = preset.get("api_key", "")
	var base_url = preset.get("base_url", "")
	var model = preset.get("model_name", "")
	
	var enhance_prompt = "You are an expert at writing system prompt instructions for AI coding assistants specialized in Godot 4 game development. The user has written the following custom instructions but they may not be well structured or clear enough. Your job is to rewrite and enhance these instructions to be clearer, more specific, and more effective, while preserving the user's original intent. Keep the same language the user wrote in. Output ONLY the enhanced instructions text, no explanations or markdown formatting.\n\nOriginal instructions:\n" + raw_text
	
	var url = ""
	var headers = ["Content-Type: application/json"]
	var body = ""
	
	if provider == 0: # Gemini / Vertex
		var m = model if model != "" else "gemini-3.1-pro-preview"
		if base_url != "":
			url = base_url
			if not url.ends_with("/"): url += "/"
			url += "v1beta/models/" + m + ":generateContent"
		else:
			url = "http://127.0.0.1:8000/v1beta/models/" + m + ":generateContent"
		body = JSON.stringify({
			"contents": [{"role": "user", "parts": [{"text": enhance_prompt}]}]
		})
	else: # OpenAI / OpenRouter
		var m = model if model != "" else "gpt-4o"
		if base_url != "":
			url = base_url
			if not url.ends_with("/"): url += "/"
			url += "v1/chat/completions"
		else:
			url = "https://api.openai.com/v1/chat/completions"
		if api_key != "":
			headers.append("Authorization: Bearer " + api_key)
		body = JSON.stringify({
			"model": m,
			"messages": [{"role": "user", "content": enhance_prompt}]
		})
	
	var err = _enhance_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_show_enhance_error("Failed to send enhance request: " + str(err))
		_reset_enhance_btn()

func _on_enhance_request_completed(_result, response_code, _headers, body):
	if response_code != 200:
		var payload = body.get_string_from_utf8()
		_show_enhance_error("API Error (" + str(response_code) + "): " + payload.substr(0, 300))
		_reset_enhance_btn()
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	var text = ""
	
	# Parse Gemini response
	if json and json.has("candidates"):
		var parts = json["candidates"][0].get("content", {}).get("parts", [])
		for part in parts:
			if part.has("text"):
				text += part["text"]
	# Parse OpenAI response
	elif json and json.has("choices"):
		text = json["choices"][0].get("message", {}).get("content", "")
	
	if text.strip_edges() == "":
		_show_enhance_error("AI returned an empty response.")
		_reset_enhance_btn()
		return
	
	_enhanced_text = text.strip_edges()
	_reset_enhance_btn()

func _on_enhance_accepted():
	if _enhanced_text != "":
		custom_prompt_input.text = _enhanced_text
		# Save to editor settings
		var settings = EditorInterface.get_editor_settings()
		settings.set_setting("gamedev_ai/custom_system_prompt", _enhanced_text)
		if gemini_client:
			gemini_client.custom_instructions = _enhanced_text
		_enhanced_text = ""

func _reset_enhance_btn():
	pass

func _show_enhance_error(msg: String):
	pass


func _try_set_icon(_prop_name: String, _icon_path: String):
	pass
func _try_display_reasoning():
	if not gemini_client:
		return
	var hist = null
	if "history" in gemini_client:
		hist = gemini_client.history
	if not (hist is Array) or hist.size() == 0:
		return
	for i in range(hist.size() - 1, -1, -1):
		var entry = hist[i]
		if not (entry is Dictionary):
			continue
		var role: String = str(entry.get("role", ""))
		if role != "assistant" and role != "model":
			continue
		# 尝试多种字段名
		var reasoning: String = ""
		for key in ["reasoning_content", "reasoning", "thinking", "thought"]:
			var v = entry.get(key, null)
			if v != null and str(v).strip_edges() != "":
				reasoning = str(v)
				break
		# 从 content 数组里找 reasoning/thought part
		if reasoning == "":
			var content = entry.get("content", null)
			if content is Array:
				for part in content:
					if part is Dictionary:
						var ptype: String = str(part.get("type", ""))
						var is_thought: bool = bool(part.get("thought", false))
						if ptype == "reasoning" or ptype == "thinking" or is_thought:
							var txt: String = str(part.get("text", ""))
							if txt.strip_edges() != "":
								reasoning = txt
								break
		if reasoning == "":
			return
		if reasoning == _last_reasoning_full:
			return
		_last_reasoning_full = reasoning
		_append_collapsible_block("💭 思考过程", reasoning, "gray", false)
		return
func _open_rename_dialog(path_or_id, current_name):
	var dlg := AcceptDialog.new()
	dlg.title = "重命名对话"
	dlg.ok_button_text = "保存"
	# dlg.cancel_button_text = "取消"  # AcceptDialog 无此属性
	dlg.size = Vector2i(440, 180)
	
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(400, 90)
	vb.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = "输入新的对话名称："
	vb.add_child(lbl)
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(380, 0)
	le.text = str(current_name)
	vb.add_child(le)
	dlg.add_child(vb)
	
	var target: String = str(path_or_id)
	dlg.confirmed.connect(func():
		var t: String = le.text.strip_edges()
		if t == "":
			_show_toast("[color=red]名称不能为空[/color]")
			dlg.queue_free()
			return
		var ok := false
		if target.begins_with("res://") and FileAccess.file_exists(target):
			ok = _write_session_title(target, t)
		else:
			ok = _rename_conversation(target, t)
		if ok:
			var fs = EditorInterface.get_resource_filesystem()
			if fs:
				fs.scan()
			_refresh_conversations_list()
			_show_toast("[color=green]已重命名为：" + t + "[/color]")
		else:
			_show_toast("[color=red]重命名失败[/color]")
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	
	add_child(dlg)
	dlg.popup_centered()
func _on_rename_confirmed():
	pass



# ═══════════════════════════════════════════════════════════════
# 修复27：附加内容 / 用量统计
# ═══════════════════════════════════════════════════════════════

const USAGE_DIR: String = "res://.gamedev_ai/Usage"
const USAGE_FILE: String = "res://.gamedev_ai/Usage/usage.json"

var _show_time_enabled: bool = false
var _show_token_enabled: bool = false
var _show_recv_time_enabled: bool = false
var _usage_entries: Array = []
var _usage_pie: Control = null


func _deferred_init():
	pass
	# 字号按钮强制文本
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "缩小"
		font_size_minus_btn.custom_minimum_size = Vector2(48, 34)
		font_size_minus_btn.tooltip_text = "减小字号"
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "放大"
		font_size_plus_btn.custom_minimum_size = Vector2(48, 34)
		font_size_plus_btn.tooltip_text = "增大字号"
	
	# CloseEditBtn 强制文本
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 32)
	
	# 编辑弹窗初始化
	if _edit_dialog == null and has_method("_setup_edit_dialog"):
		_setup_edit_dialog()
	
	# 附加设置卡片
	_setup_additional_cards()
	# 加载用量
	_usage_load()


# -------------------- 附加设置卡片 --------------------

func _get_settings_content() -> VBoxContainer:
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return null
	var n = settings_tab.get_node_or_null("SettingsScroll/SettingsMargin/SettingsContent")
	if n is VBoxContainer:
		return n
	n = settings_tab.get_node_or_null("SettingsScroll/SettingsContent")
	if n is VBoxContainer:
		return n
	if settings_tab is VBoxContainer:
		return settings_tab
	return null


func _remove_vectordb_card():
	var inner = _get_settings_content()
	if inner == null:
		return
	for card in inner.get_children():
		if not (card is PanelContainer):
			continue
		var found := false
		for sub in card.find_children("*", "Label", true, false):
			if sub is Label:
				var t: String = sub.text.to_lower()
				if "向量" in sub.text or "vector" in t:
					found = true
					break
		if found:
			card.queue_free()


func _hide_vectordb():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	# 遍历 Settings 全子树，隐藏所有含 VectorDB 关键字的节点
	var stack: Array = [settings_tab]
	while not stack.is_empty():
		var node = stack.pop_back()
		var nm := String(node.name)
		if "VectorDB" in nm or "ScanChanges" in nm or "IndexCodebase" in nm \
			or "IndexConfirm" in nm or "IndexResult" in nm:
			if node is CanvasItem:
				node.visible = false
		for c in node.get_children():
			stack.append(c)


func _hide_magic_button():
	var real_magic = find_child("MagicActionsBtn", true, false)
	if real_magic != null and real_magic is CanvasItem:
		real_magic.visible = false
	var dummy = find_child("MagicActionsBtn_Dummy", true, false)
	if dummy != null and dummy is CanvasItem:
		dummy.visible = false


func _setup_additional_cards():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	var scroll = settings_tab.get_node_or_null("SettingsScroll")
	if scroll == null:
		return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null:
		inner = settings_tab
	
	# 已存在 → 直接返回
	if inner.get_node_or_null("AdditionalTitle") != null:
		return
	
	var sep := HSeparator.new()
	sep.name = "AdditionalSep"
	inner.add_child(sep)
	
	var title := Label.new()
	title.name = "AdditionalTitle"
	title.text = "附加内容"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(title)
	
	var cb1 := CheckBox.new()
	cb1.name = "CbShowTime"
	cb1.text = "发送时附带当前时间"
	cb1.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
	cb1.button_pressed = _show_time_enabled
	cb1.toggled.connect(func(v): _show_time_enabled = v; _save_ui_settings())
	inner.add_child(cb1)
	
	var cb2 := CheckBox.new()
	cb2.name = "CbShowToken"
	cb2.text = "显示 Token 数"
	cb2.tooltip_text = "消息下方显示消耗 Token 数"
	cb2.button_pressed = _show_token_enabled
	cb2.toggled.connect(func(v): _show_token_enabled = v; _save_ui_settings())
	inner.add_child(cb2)
	
	var cb3 := CheckBox.new()
	cb3.name = "CbShowRecvTime"
	cb3.text = "显示收发时间"
	cb3.tooltip_text = "消息下方显示发送/接收时间"
	cb3.button_pressed = _show_recv_time_enabled
	cb3.toggled.connect(func(v): _show_recv_time_enabled = v; _save_ui_settings())
	inner.add_child(cb3)
	
	# 用量统计区
	var sep2 := HSeparator.new()
	sep2.name = "UsageSep"
	inner.add_child(sep2)
	
	var title2 := Label.new()
	title2.name = "UsageTitle"
	title2.text = "用量统计"
	title2.add_theme_font_size_override("font_size", 14)
	title2.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(title2)
	
	var summary := Label.new()
	summary.name = "UsageSummary"
	summary.text = "（暂无数据）"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if summary != null: summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(summary)
	
	var refresh := Button.new()
	refresh.name = "UsageRefreshBtn"
	refresh.text = "刷新统计"
	refresh.custom_minimum_size = Vector2(120, 32)
	refresh.pressed.connect(func():
		_usage_load()
		_update_usage_summary()
	)
	inner.add_child(refresh)
func _update_usage_summary():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	var summary = settings_tab.find_child("UsageSummary", true, false)
	if summary == null:
		return
	if _usage_entries.is_empty():
		summary.text = "（暂无数据）"
		return
	var total_p: int = 0
	var total_c: int = 0
	var total_t: int = 0
	var lines: Array = []
	for e in _usage_entries:
		total_p += int(e.get("prompt", 0))
		total_c += int(e.get("completion", 0))
		total_t += int(e.get("total", 0))
	lines.append("总计：" + str(total_t) + " tokens")
	lines.append("  输入：" + str(total_p) + " / 输出：" + str(total_c))
	lines.append("记录条目：" + str(_usage_entries.size()))
	summary.text = "\n".join(lines)


func _save_ui_settings():
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("gamedev_ai/show_time", _show_time_enabled)
	settings.set_setting("gamedev_ai/show_token", _show_token_enabled)
	settings.set_setting("gamedev_ai/show_recv_time", _show_recv_time_enabled)
	if has_method("_v40_refresh_all_footers"):
		_v40_refresh_all_footers()


func _load_ui_settings():
	var settings = EditorInterface.get_editor_settings()
	if settings.has_setting("gamedev_ai/show_time"):
		_show_time_enabled = settings.get_setting("gamedev_ai/show_time")
	if settings.has_setting("gamedev_ai/show_token"):
		_show_token_enabled = settings.get_setting("gamedev_ai/show_token")
	if settings.has_setting("gamedev_ai/show_recv_time"):
		_show_recv_time_enabled = settings.get_setting("gamedev_ai/show_recv_time")


# -------------------- 用量文件 --------------------

func _usage_append(prompt_t: int, completion_t: int, total_t: int, cached_t: int):
	var entry: Dictionary = {
		"ts": Time.get_datetime_string_from_system(),
		"model": _usage_current_model(),
		"prompt": prompt_t,
		"completion": completion_t,
		"total": total_t,
		"cached": cached_t
	}
	_usage_entries.append(entry)
	_usage_save()
	_update_usage_summary()


func _usage_current_model() -> String:
	if active_preset_name != "" and presets.has(active_preset_name):
		return str(presets[active_preset_name].get("model_name", "unknown"))
	return "unknown"


func _usage_save():
	if not DirAccess.dir_exists_absolute(USAGE_DIR):
		DirAccess.make_dir_recursive_absolute(USAGE_DIR)
	var f = FileAccess.open(USAGE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_usage_entries, "  "))
		f.close()


func _usage_load():
	_usage_entries = []
	if not FileAccess.file_exists(USAGE_FILE):
		return
	var f = FileAccess.open(USAGE_FILE, FileAccess.READ)
	if not f:
		return
	var txt = f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if data is Array:
		_usage_entries = data

func _create_edit_dialog():
	if _edit_dialog != null:
		return
	_edit_dialog = AcceptDialog.new()
	_edit_dialog.title = "编辑消息"
	_edit_dialog.ok_button_text = "保存"
	_edit_dialog.add_button("编辑并重发", true, "edit_resend")
	_edit_dialog.add_button("取消", true, "cancel")
	_edit_dialog.confirmed.connect(_on_edit_save)
	
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(360, 200)
	vb.add_theme_constant_override("separation", 6)
	_edit_input = TextEdit.new()
	_edit_input.custom_minimum_size = Vector2(340, 180)
	_edit_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(_edit_input)
	_edit_dialog.add_child(vb)
	add_child(_edit_dialog)


func _kill_vectordb():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	# 找 SettingsContent
	var content: Node = null
	var scroll = settings_tab.find_child("SettingsScroll", true, false)
	if scroll != null:
		content = scroll.find_child("SettingsContent", true, false)
	if content == null:
		content = settings_tab
	# 遍历卡片，含"向量"或"VectorDB"关键字的删除
	var to_kill: Array = []
	for card in content.get_children():
		var kill := false
		if card is PanelContainer:
			for sub in card.find_children("*", "Label", true, false):
				if sub is Label:
					if "向量" in sub.text or "vector" in sub.text.to_lower():
						kill = true
						break
		if not kill and card.name.begins_with("VectorDB"):
			kill = true
		if kill:
			to_kill.append(card)
	# 再扫一遍所有含 VectorDB 关键字的节点
	var stack: Array = [settings_tab]
	while not stack.is_empty():
		var n = stack.pop_back()
		var nm := String(n.name)
		if ("VectorDB" in nm or "ScanChanges" in nm or "IndexCodebase" in nm \
			or "IndexConfirm" in nm or "IndexResult" in nm) and n not in to_kill:
			to_kill.append(n)
		for c in n.get_children():
			stack.append(c)
	for n in to_kill:
		if is_instance_valid(n):
			n.queue_free()


# ═══════════════════════════════════════════════════════════════
# 修复32：对话管理 & 消息编辑 干净版本
# ═══════════════════════════════════════════════════════════════


func _write_session_title(path: String, new_title: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var txt = f.read_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		return false
	data["title"] = new_title
	var wf = FileAccess.open(path, FileAccess.WRITE)
	if not wf:
		return false
	wf.store_string(JSON.stringify(data, "  "))
	wf.close()
	return true


func _on_conv_name_gui_input(event, path):
	if event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_load_conversation(path)


func _on_conv_load_pressed(path):
	_load_conversation(path)


func _on_conv_rename_pressed(path, name_btn):
	var path_str: String = str(path)
	var project_hist: String = "res://.gamedev_ai/history/"
	if not path_str.begins_with(project_hist):
		_show_toast("[color=red]非法路径：" + path_str + "[/color]")
		return
	if not FileAccess.file_exists(path_str):
		_show_toast("[color=red]文件不存在：" + path_str + "[/color]")
		return
	
	var cur_title: String = ""
	if is_instance_valid(name_btn):
		cur_title = name_btn.text
	
	var old = get_node_or_null("__RenamePanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__RenamePanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(440, 180)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	style.border_color = Color(0.35, 0.55, 0.95, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	
	var lbl := Label.new()
	lbl.text = "重命名对话"
	lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(lbl)
	
	var le := LineEdit.new()
	le.text = cur_title
	le.custom_minimum_size = Vector2(400, 0)
	vb.add_child(le)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(80, 32)
	hb.add_child(cancel_btn)
	hb.add_child(save_btn)
	vb.add_child(hb)
	
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2(
		(vp_size.x - panel.size.x) * 0.5,
		(vp_size.y - panel.size.y) * 0.5
	)
	
	save_btn.pressed.connect(func():
		var t: String = le.text.strip_edges()
		if t == "":
			_show_toast("[color=red]名称不能为空[/color]")
			return
		if _write_session_title(path_str, t):
			var fs = EditorInterface.get_resource_filesystem()
			if fs:
				fs.scan()
			_refresh_conversations_list()
			_show_toast("[color=green]已重命名为：" + t + "[/color]")
		else:
			_show_toast("[color=red]重命名失败[/color]")
		panel.queue_free()
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
	
	le.grab_focus()
	le.select_all()
func _write_session_title_by_path(path: String, new_title: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var txt: String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		data = {}
	data["title"] = new_title
	var wf = FileAccess.open(path, FileAccess.WRITE)
	if not wf:
		return false
	wf.store_string(JSON.stringify(data, "  "))
	wf.close()
	return true
func _show_input_panel(title: String, default_value: String, on_save: Callable):
	pass
	# 删掉旧面板
	var old = get_node_or_null("__InputPanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__InputPanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(420, 180)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	style.border_color = Color(0.35, 0.55, 0.95, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(lbl)
	
	var le := LineEdit.new()
	le.text = default_value
	le.custom_minimum_size = Vector2(380, 0)
	vb.add_child(le)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(80, 32)
	hb.add_child(cancel_btn)
	hb.add_child(save_btn)
	vb.add_child(hb)
	
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2(
		(vp_size.x - panel.size.x) * 0.5,
		(vp_size.y - panel.size.y) * 0.5
	)
	
	save_btn.pressed.connect(func():
		on_save.call(le.text.strip_edges())
		panel.queue_free()
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
	
	le.grab_focus()
	le.select_all()
func _on_conv_delete_pressed(path):
	_show_confirm_panel("删除对话",
		"确定要删除这个对话吗？
" + path + "
此操作无法撤销。",
		func():
			if FileAccess.file_exists(path):
				var err = DirAccess.remove_absolute(path)
				if err == OK:
					var fs = EditorInterface.get_resource_filesystem()
					if fs:
						fs.scan()
					_show_toast("[color=green]已删除：" + path.get_file() + "[/color]")
				else:
					_show_toast("[color=red]删除失败：" + str(err) + "[/color]")
			_refresh_conversations_list()
	)


func _show_confirm_panel(title: String, text: String, on_confirm: Callable):
	var old = get_node_or_null("__ConfirmPanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__ConfirmPanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(420, 180)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	style.border_color = Color(0.9, 0.5, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(lbl)
	
	var msg := Label.new()
	msg.text = text
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(380, 0)
	vb.add_child(msg)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(80, 32)
	hb.add_child(cancel_btn)
	hb.add_child(ok_btn)
	vb.add_child(hb)
	
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2(
		(vp_size.x - panel.size.x) * 0.5,
		(vp_size.y - panel.size.y) * 0.5
	)
	
	ok_btn.pressed.connect(func():
		on_confirm.call()
		panel.queue_free()
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
func _do_delete_conversation():
	pass


func _on_edit_message_pressed(bubble, label):
	if not is_instance_valid(bubble) or not is_instance_valid(label):
		return
	var role: String = str(bubble.get_meta("role", "ai"))
	var is_user: bool = (role == "user")
	var old = get_node_or_null("__EditPanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__EditPanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(680, 580)
	
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	st.border_color = Color(0.35, 0.55, 0.95, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", st)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var ttl := Label.new()
	ttl.text = "编辑消息"
	ttl.add_theme_font_size_override("font_size", 14)
	vb.add_child(ttl)
	
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var blocks_vb := VBoxContainer.new()
	blocks_vb.name = "BlocksVBox"
	blocks_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blocks_vb.add_theme_constant_override("separation", 8)
	scroll.add_child(blocks_vb)
	
	# ─── 按 raw_bbcode 顺序解析 ───
	var raw_bb: String = label.get_meta("raw_bbcode", "")
	
	# 收集所有块的 bbcode 字符串 → 对应 _block_data
	var block_entries: Array = []
	for bid in _block_data.keys():
		if _block_data[bid].get("bubble_ref") == label:
			var bb: String = _get_block_bbcode(bid)
			block_entries.append({"id": bid, "bb": bb, "pos": raw_bb.find(bb) if bb != "" else -1})
	block_entries.sort_custom(func(a, b): return a["pos"] < b["pos"])
	
	# 按位置切分文本段和块段
	var cursor: int = 0
	for e in block_entries:
		if e["pos"] < 0:
			continue
		# 文本段
		if e["pos"] > cursor:
			var text_seg: String = raw_bb.substr(cursor, e["pos"] - cursor)
			text_seg = text_seg.strip_edges()
			if text_seg != "":
				_v51_make_block(blocks_vb, "文本", text_seg)
		# 块段
		var d: Dictionary = _block_data[e["id"]]
		var content_str: String = str(d.get("content", "")).replace("[lb]", "[")
		_v51_make_block(blocks_vb, str(d.get("label", "")), content_str)
		cursor = e["pos"] + e["bb"].length()
	# 尾部文本
	if cursor < raw_bb.length():
		var tail: String = raw_bb.substr(cursor).strip_edges()
		if tail != "":
			_v51_make_block(blocks_vb, "文本", tail)
	
	if blocks_vb.get_child_count() == 0:
		_v51_make_block(blocks_vb, "文本", "")
	
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var add_block := Button.new()
	add_block.text = "+ 添加"
	add_block.custom_minimum_size = Vector2(80, 32)
	hb.add_child(add_block)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(72, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(72, 32)
	var resend_btn: Button = null
	if is_user:
		resend_btn = Button.new()
		resend_btn.text = "编辑并重发"
		resend_btn.custom_minimum_size = Vector2(110, 32)
	hb.add_child(cancel_btn)
	hb.add_child(save_btn)
	if resend_btn != null:
		hb.add_child(resend_btn)
	vb.add_child(hb)
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vps: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2((vps.x - panel.size.x) * 0.5, (vps.y - panel.size.y) * 0.5)
	
	add_block.pressed.connect(func(): _v51_make_block(blocks_vb, "文本", ""))
	cancel_btn.pressed.connect(func(): panel.queue_free())
	save_btn.pressed.connect(func():
		_v51_apply_blocks(blocks_vb, label)
		_show_toast("[color=green]消息已保存[/color]")
		panel.queue_free()
	)
	if resend_btn != null:
		resend_btn.pressed.connect(func():
			var t := _v51_get_first_text(blocks_vb)
			panel.queue_free()
			_edit_and_resend(bubble, t)
		)
func _v51_get_first_text(blocks_vb: VBoxContainer) -> String:
	for c in blocks_vb.get_children():
		if c.has_meta("v50_te"):
			var te: TextEdit = c.get_meta("v50_te")
			if te.text.strip_edges() != "":
				return te.text
	return ""


func _v51_apply_blocks(blocks_vb: VBoxContainer, label):
	# 先删旧块
	var old_bids: Array = []
	for bid in _block_data.keys():
		if _block_data[bid].get("bubble_ref") == label:
			old_bids.append(bid)
	for b in old_bids:
		_block_data.erase(b)
	
	var combined: String = ""
	for child in blocks_vb.get_children():
		if not child.has_meta("v50_te"):
			continue
		var te: TextEdit = child.get_meta("v50_te")
		var le: LineEdit = child.get_meta("v50_le")
		var tag: String = le.text.strip_edges()
		var content: String = te.text
		if content.strip_edges() == "":
			continue
		if tag == "文本" or tag == "":
			# 无标签 → 普通文本，与正文一样
			combined += _markdown_to_bbcode(content) + "
"
		else:
			var bid2 = _next_block_id
			_next_block_id += 1
			var color: String = "gray"
			# 工具调用（含 🛠️ / 🔧 或"工具调用"字眼）→ 蓝色
			if "🛠️" in tag or "🔧" in tag or "工具调用" in tag or "Tool Call" in tag:
				color = "dodgerblue"
			# 结果 / 输出 → 绿色
			elif "📤" in tag or "输出" in tag or "结果" in tag or "Result" in tag or "Output" in tag:
				color = "green"
			# 思考过程 → 灰色
			elif "💭" in tag or "思考" in tag or "Thinking" in tag or "Reason" in tag:
				color = "gray"
			# 默认灰色
			_block_data[bid2] = {
				"label": tag,
				"content": content.replace("[", "[lb]"),
				"color": color,
				"expanded": false,
				"bubble_ref": label
			}
			combined += _get_block_bbcode(bid2)
	label.text = combined
	label.set_meta("raw_bbcode", combined)
func _v51_make_block(parent: VBoxContainer, tag: String, content: String):
	var block := PanelContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	bs.set_border_width_all(1)
	bs.border_color = Color(0.3, 0.35, 0.45, 0.6)
	bs.set_corner_radius_all(6)
	bs.content_margin_left = 8
	bs.content_margin_right = 8
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	block.add_theme_stylebox_override("panel", bs)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	var hdr := HBoxContainer.new()
	var le := LineEdit.new()
	le.text = tag
	le.custom_minimum_size = Vector2(140, 26)
	le.add_theme_font_size_override("font_size", 11)
	hdr.add_child(le)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)
	var del := Button.new()
	del.text = "✕"
	del.custom_minimum_size = Vector2(24, 24)
	del.pressed.connect(func(): block.queue_free())
	hdr.add_child(del)
	vbox.add_child(hdr)
	
	var te := TextEdit.new()
	te.text = content
	te.custom_minimum_size = Vector2(0, 90)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(te)
	
	block.add_child(vbox)
	block.set_meta("v50_te", te)
	block.set_meta("v50_le", le)
	parent.add_child(block)
func _v50_make_block(parent: VBoxContainer, tag: String, content: String):
	var block := PanelContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	bs.set_border_width_all(1)
	bs.border_color = Color(0.3, 0.35, 0.45, 0.6)
	bs.set_corner_radius_all(6)
	bs.content_margin_left = 8
	bs.content_margin_right = 8
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	block.add_theme_stylebox_override("panel", bs)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	var hdr := HBoxContainer.new()
	var le := LineEdit.new()
	le.text = tag
	le.custom_minimum_size = Vector2(140, 26)
	le.add_theme_font_size_override("font_size", 11)
	hdr.add_child(le)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)
	var del := Button.new()
	del.text = "✕"
	del.custom_minimum_size = Vector2(24, 24)
	del.pressed.connect(func(): block.queue_free())
	hdr.add_child(del)
	vbox.add_child(hdr)
	
	var te := TextEdit.new()
	te.text = content
	te.custom_minimum_size = Vector2(0, 90)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(te)
	
	block.add_child(vbox)
	block.set_meta("v50_te", te)
	block.set_meta("v50_le", le)
	parent.add_child(block)
func _show_edit_panel(label: RichTextLabel, bubble: PanelContainer):
	var old = get_node_or_null("__EditPanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__EditPanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(520, 340)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	style.border_color = Color(0.35, 0.55, 0.95, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	
	var lbl := Label.new()
	lbl.text = "编辑消息"
	lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(lbl)
	
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(480, 220)
	te.text = label.get_parsed_text()
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(te)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	var resend_btn := Button.new()
	resend_btn.text = "编辑并重发"
	resend_btn.custom_minimum_size = Vector2(120, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(80, 32)
	hb.add_child(cancel_btn)
	hb.add_child(resend_btn)
	hb.add_child(save_btn)
	vb.add_child(hb)
	
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2(
		(vp_size.x - panel.size.x) * 0.5,
		(vp_size.y - panel.size.y) * 0.5
	)
	
	save_btn.pressed.connect(func():
		var new_text: String = te.text
		var new_bb: String = _markdown_to_bbcode(new_text).strip_edges() + "
"
		var old_bb: String = label.get_meta("raw_bbcode", "")
		label.text = new_bb
		label.set_meta("raw_bbcode", new_bb)
		if old_bb != "":
			_chat_log_bbcode = _chat_log_bbcode.replace(old_bb, new_bb)
		_show_toast("[color=green]消息已保存[/color]")
		panel.queue_free()
	)
	resend_btn.pressed.connect(func():
		var t: String = te.text
		panel.queue_free()
		_edit_and_resend(bubble, t)
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
	te.grab_focus()
func _edit_and_resend(bubble, new_text: String):
	if not is_instance_valid(bubble):
		return
	var idx: int = bubble.get_index()
	var children = chat_vbox.get_children()
	for i in range(children.size() - 1, idx - 1, -1):
		var child = children[i]
		if child == _diff_preview_panel:
			continue
		chat_vbox.remove_child(child)
		child.queue_free()
	_chat_log_bbcode = ""
	_current_bubble = null
	_current_role = ""
	if new_text.strip_edges() == "":
		return
	_process_send(new_text)


func _on_delete_message_pressed(bubble):
	pass
	if not is_instance_valid(bubble):
		return
	
	var old = get_node_or_null("__DelPanel")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__DelPanel"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(400, 170)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	style.border_color = Color(0.9, 0.5, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	
	var ttl := Label.new()
	ttl.text = "删除消息"
	ttl.add_theme_font_size_override("font_size", 14)
	vb.add_child(ttl)
	
	var msg := Label.new()
	msg.text = "确定要删除这条消息吗？此操作无法撤销。"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(360, 0)
	vb.add_child(msg)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	var ok_btn := Button.new()
	ok_btn.text = "删除"
	ok_btn.custom_minimum_size = Vector2(80, 32)
	hb.add_child(cancel_btn)
	hb.add_child(ok_btn)
	vb.add_child(hb)
	
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2((vp_size.x - panel.size.x) * 0.5, (vp_size.y - panel.size.y) * 0.5)
	
	ok_btn.pressed.connect(func():
		panel.queue_free()
		var lbl = bubble.get_meta("label", null)
		if lbl and is_instance_valid(lbl):
			var bb = lbl.get_meta("raw_bbcode", "")
			if bb != "":
				_chat_log_bbcode = _chat_log_bbcode.replace(bb, "")
			if _current_bubble == lbl:
				_current_bubble = null
				_current_role = ""
		bubble.queue_free()
		_show_toast("[color=orange]消息已删除[/color]")
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())

func _deferred_setup_settings():
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	# 已存在 → 只规范化
	if settings_tab.has_node("SettingsScroll"):
		var s0 = settings_tab.get_node("SettingsScroll")
		if s0 is ScrollContainer:
			s0.size_flags_vertical = Control.SIZE_EXPAND_FILL
			if s0 != null: s0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s0.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			s0.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			s0.clip_contents = true
		return
	
	# 收集现有子节点
	var existing: Array = []
	for c in settings_tab.get_children():
		existing.append(c)
	
	# 创建滚动容器
	var scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	settings_tab.add_child(scroll)
	
	var inner = VBoxContainer.new()
	inner.name = "SettingsContent"
	if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	
	# 把原内容搬进去
	for c in existing:
		if c is Control:
			c.reparent(inner)
	
	# API 配置标题
	var preset_bar = inner.get_node_or_null("PresetBar")
	if preset_bar != null and inner.get_node_or_null("ApiConfigTitle") == null:
		var t = Label.new()
		t.name = "ApiConfigTitle"
		t.text = "API 配置"
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
		inner.add_child(t)
		inner.move_child(t, preset_bar.get_index())
	
	pass


func _deferred_save():
	_save_all_messages_to_file()



func _deferred_final_init():
	# 1) 隐藏魔法操作
	var magic = find_child("MagicActionsBtn", true, false)
	if magic != null and magic is CanvasItem:
		magic.visible = false
	var magic_dummy = find_child("MagicActionsBtn_Dummy", true, false)
	if magic_dummy != null and magic_dummy is CanvasItem:
		magic_dummy.visible = false
	
	# 2) 确保 Settings 滚动条存在
	_ensure_settings_scroll()
	
	# 3) 附加内容 / 用量统计
	_ensure_additional_section()
	
	# 4) 字号按钮
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if summarize_btn != null:
		summarize_btn.custom_minimum_size = Vector2(40, 32)
		if summarize_btn != null: summarize_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
	
	pass


func _ensure_settings_scroll() -> VBoxContainer:
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return null
	
	var scroll = settings_tab.get_node_or_null("SettingsScroll")
	if scroll != null and scroll is ScrollContainer:
		if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.clip_contents = true
		var inner0 = scroll.find_child("SettingsContent", true, false)
		if inner0 is VBoxContainer:
			return inner0
		# 没有 content 就补一个
		var new_inner = VBoxContainer.new()
		new_inner.name = "SettingsContent"
		if new_inner != null: new_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(new_inner)
		return new_inner
	
	# 没有 → 创建
	var existing: Array = []
	for c in settings_tab.get_children():
		existing.append(c)
	
	scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	settings_tab.add_child(scroll)
	
	var inner = VBoxContainer.new()
	inner.name = "SettingsContent"
	if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	
	for c in existing:
		if c is Control:
			c.reparent(inner)
	
	# API 配置标题
	var preset_bar = inner.get_node_or_null("PresetBar")
	if preset_bar != null and inner.get_node_or_null("ApiConfigTitle") == null:
		var t = Label.new()
		t.name = "ApiConfigTitle"
		t.text = "API 配置"
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
		inner.add_child(t)
		inner.move_child(t, preset_bar.get_index())
	
	return inner


func _ensure_additional_section():
	var inner = _ensure_settings_scroll()
	if inner == null:
		return
	if inner.get_node_or_null("AdditionalTitle") != null:
		return
	
	# 分隔线
	var sep := HSeparator.new()
	sep.name = "AdditionalSep"
	inner.add_child(sep)
	
	# 附加内容标题
	var t1 := Label.new()
	t1.name = "AdditionalTitle"
	t1.text = "附加内容"
	t1.add_theme_font_size_override("font_size", 14)
	t1.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(t1)
	
	# 三个开关
	var cb1 := CheckBox.new()
	cb1.name = "CbShowTime"
	cb1.text = "发送时附带当前时间"
	cb1.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
	cb1.button_pressed = _show_time_enabled
	cb1.toggled.connect(func(v): _show_time_enabled = v; _save_ui_settings())
	inner.add_child(cb1)
	
	var cb2 := CheckBox.new()
	cb2.name = "CbShowToken"
	cb2.text = "显示 Token 数"
	cb2.tooltip_text = "消息下方显示消耗 Token 数"
	cb2.button_pressed = _show_token_enabled
	cb2.toggled.connect(func(v): _show_token_enabled = v; _save_ui_settings())
	inner.add_child(cb2)
	
	var cb3 := CheckBox.new()
	cb3.name = "CbShowRecvTime"
	cb3.text = "显示收发时间"
	cb3.tooltip_text = "消息下方显示发送/接收时间"
	cb3.button_pressed = _show_recv_time_enabled
	cb3.toggled.connect(func(v): _show_recv_time_enabled = v; _save_ui_settings())
	inner.add_child(cb3)
	
	# 用量统计分隔线
	var sep2 := HSeparator.new()
	sep2.name = "UsageSep"
	inner.add_child(sep2)
	
	var t2 := Label.new()
	t2.name = "UsageTitle"
	t2.text = "用量统计"
	t2.add_theme_font_size_override("font_size", 14)
	t2.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	inner.add_child(t2)
	
	var summary := Label.new()
	summary.name = "UsageSummary"
	summary.text = "（暂无数据）"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if summary != null: summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(summary)
	
	var refresh := Button.new()
	refresh.name = "UsageRefreshBtn"
	refresh.text = "刷新统计"
	refresh.custom_minimum_size = Vector2(120, 32)
	refresh.pressed.connect(func():
		_usage_load()
		_update_usage_summary()
	)
	inner.add_child(refresh)
	
	# 隐藏 AI 优化指令
	if enhance_prompt_btn != null:
		pass



func _force_final_pass():
	# 强制 close_edit_btn 文本（在 _apply_locale 之后跑，防止被覆盖）
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 32)
	
	# 强制 Settings 最小宽度 = Chat 最小宽度
	var __chat = $TabContainer.get_node_or_null("Chat")
	var __settings = $TabContainer.get_node_or_null("Settings")
	if __chat != null and __settings != null:
		var __cw = __chat.custom_minimum_size.x
		if __cw <= 0.0:
			__cw = 200.0
		__settings.custom_minimum_size = Vector2(__cw, 0)
	
	# 字号按钮
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if summarize_btn != null:
		summarize_btn.custom_minimum_size = Vector2(40, 32)
		if summarize_btn != null: summarize_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# 隐藏魔法操作
	var __magic = find_child("MagicActionsBtn", true, false)
	if __magic != null and __magic is CanvasItem:
		__magic.visible = false
	var __magic2 = find_child("MagicActionsBtn_Dummy", true, false)
	if __magic2 != null and __magic2 is CanvasItem:
		__magic2.visible = false


func _force_final_pass_deferred():
	await get_tree().process_frame
	_force_final_pass()



func _force_final_pass_39():
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 32)
	
	var __chat_39 = $TabContainer.get_node_or_null("Chat")
	var __settings_39 = $TabContainer.get_node_or_null("Settings")
	if __chat_39 != null and __settings_39 != null:
		var __cw_39: float = __chat_39.custom_minimum_size.x
		if __cw_39 <= 0.0:
			__cw_39 = 200.0
		__settings_39.custom_minimum_size = Vector2(__cw_39, 0)
	
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if summarize_btn != null:
		summarize_btn.custom_minimum_size = Vector2(40, 32)
		if summarize_btn != null: summarize_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	var __m1 = find_child("MagicActionsBtn", true, false)
	if __m1 != null and __m1 is CanvasItem:
		__m1.visible = false
	var __m2 = find_child("MagicActionsBtn_Dummy", true, false)
	if __m2 != null and __m2 is CanvasItem:
		__m2.visible = false



func _force_final_v15():
	# ---- Settings 撑满 + 滚动条 ----
	var settings_tab = $TabContainer.get_node_or_null("Settings")
	if settings_tab != null and settings_tab is Control:
		settings_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if settings_tab != null: settings_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var scroll = settings_tab.get_node_or_null("SettingsScroll")
		if scroll == null:
			var existing: Array = []
			for c in settings_tab.get_children():
				existing.append(c)
			scroll = ScrollContainer.new()
			scroll.name = "SettingsScroll"
			if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.clip_contents = true
			settings_tab.add_child(scroll)
			var inner = VBoxContainer.new()
			inner.name = "SettingsContent"
			if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inner.add_theme_constant_override("separation", 12)
			scroll.add_child(inner)
			for c in existing:
				if c is Control:
					c.reparent(inner)
		else:
			if scroll is ScrollContainer:
				scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
				if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				scroll.clip_contents = true
		# 确保 SettingsContent 存在
		var check_inner = scroll.find_child("SettingsContent", true, false)
		if check_inner == null:
			check_inner = VBoxContainer.new()
			check_inner.name = "SettingsContent"
			if check_inner != null: check_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(check_inner)
	
	# ---- 隐藏向量数据库 / Enhance 残留节点 ----
	var __stack: Array = [$TabContainer.get_node_or_null("Settings")]
	while not __stack.is_empty():
		var n = __stack.pop_back()
		if n == null:
			continue
		var nm: String = str(n.name)
		if "VectorDB" in nm or "ScanChanges" in nm or "IndexCodebase" in nm 			or "IndexConfirm" in nm or "IndexResult" in nm 			or "EnhancePrompt" in nm or "EnhancePreview" in nm:
			if n is CanvasItem:
				n.visible = false
		for c in n.get_children():
			__stack.append(c)
	
	# ---- close_edit_btn 文本 ----
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 32)
	
	# ---- 字号按钮 ----
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(44, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if summarize_btn != null:
		summarize_btn.custom_minimum_size = Vector2(40, 32)
		if summarize_btn != null: summarize_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# ---- 隐藏魔法操作 ----
	var __m1 = find_child("MagicActionsBtn", true, false)
	if __m1 != null and __m1 is CanvasItem:
		__m1.visible = false
	var __m2 = find_child("MagicActionsBtn_Dummy", true, false)
	if __m2 != null and __m2 is CanvasItem:
		__m2.visible = false
	
	# ---- 附加内容卡片（如果 _setup_additional_cards 之前没跑成功，这里再跑一次）----
	if has_method("_setup_additional_cards"):
		var settings_tab2 = $TabContainer.get_node_or_null("Settings")
		if settings_tab2 != null:
			var sc = settings_tab2.get_node_or_null("SettingsScroll")
			if sc != null:
				var inner2 = sc.find_child("SettingsContent", true, false)
				if inner2 != null and inner2.get_node_or_null("AdditionalTitle") == null:
					_setup_additional_cards()



func _collect_ctrls_recursive(node: Node, out: Array):
	for child in node.get_children():
		if child is Control:
			out.append(child)
		_collect_ctrls_recursive(child, out)


func _final_layout_v1():
	# ─── 1. 所有 OptionButton 自适应 ───
	var all_ctrls: Array = []
	_collect_ctrls_recursive(self, all_ctrls)
	for c in all_ctrls:
		if c is OptionButton:
			if c != null: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.clip_text = true
			c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			c.fit_to_longest_item = false
			if c.custom_minimum_size.x > 80:
				c.custom_minimum_size = Vector2(60, c.custom_minimum_size.y)
	
	# ─── 2. Button 分类处理 ───
	for c in all_ctrls:
		if not (c is Button):
			continue
		var has_text: bool = c.text.strip_edges() != ""
		var has_icon: bool = c.icon != null
		if not has_text and has_icon:
			# 图标按钮：固定宽度，不压缩
			if c != null: c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			if c.custom_minimum_size.x < 32:
				c.custom_minimum_size = Vector2(36, c.custom_minimum_size.y)
		elif has_text:
			# 文本按钮：可压缩 + 省略号，最小 36
			c.clip_text = true
			c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if c.custom_minimum_size.x < 36:
				c.custom_minimum_size = Vector2(36, c.custom_minimum_size.y)
	
	# ─── 3. 关键按钮显式处理 ───
	if preset_selector != null:
		if preset_selector != null: preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_selector.clip_text = true
		preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preset_selector.fit_to_longest_item = false
	if chat_preset_selector != null:
		if chat_preset_selector != null: chat_preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_preset_selector.clip_text = true
		chat_preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chat_preset_selector.fit_to_longest_item = false
	if language_selector != null:
		if language_selector != null: language_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		language_selector.clip_text = true
		language_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		language_selector.fit_to_longest_item = false
	if provider_selector != null:
		if provider_selector != null: provider_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		provider_selector.clip_text = true
		provider_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		provider_selector.fit_to_longest_item = false
	
	# 预设三按钮
	var add_pb = find_child("AddPresetBtn", true, false)
	var del_pb = find_child("DelPresetBtn", true, false)
	for b in [add_pb, edit_preset_btn, del_pb]:
		if b != null and b is Button:
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if b.custom_minimum_size.x < 36:
				b.custom_minimum_size = Vector2(36, b.custom_minimum_size.y)
	
	# ─── 4. 字号按钮（固定文本，固定宽度）───
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(40, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(40, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# ─── 5. 保存/附加等图标按钮固定 ───
	if summarize_btn != null:
		summarize_btn.custom_minimum_size = Vector2(40, 32)
		if summarize_btn != null: summarize_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if send_button != null:
		send_button.custom_minimum_size = Vector2(40, 40)
		if send_button != null: send_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if add_file_btn != null:
		add_file_btn.custom_minimum_size = Vector2(36, 32)
		if add_file_btn != null: add_file_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# ─── 6. Settings 最小宽度 = Chat 最小宽度 ───
	var chat_tab = $TabContainer.get_node_or_null("Chat")
	var settings_tab = $TabContainer.get_node_or_null("Settings")
	if chat_tab != null and settings_tab != null:
		var cw: float = chat_tab.custom_minimum_size.x
		if cw <= 0.0:
			cw = 200.0
		settings_tab.custom_minimum_size = Vector2(cw, 0)
	
	# ─── 7. 确保 close_edit_btn 有文本 ───
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 32)



func _hide_removed_v2():
	# 递归扫描，隐藏所有含关键字的节点
	var roots: Array = []
	var tab = $TabContainer
	if tab != null:
		roots.append(tab)
	var self_stack: Array = [self]
	# 从根节点开始全扫
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null:
			continue
		var nm: String = str(n.name)
		var hit := false
		for kw in ["VectorDB", "ScanChanges", "IndexCodebase",
					"IndexConfirm", "IndexResult",
					"EnhancePrompt", "EnhancePreview"]:
			if kw in nm:
				hit = true
				break
		if hit and n is CanvasItem:
			n.visible = false
		for c in n.get_children():
			stack.append(c)
	
	# 删除 SettingsContent 里含相关文本的卡片
	var settings_tab = $TabContainer.get_node_or_null("Settings")
	if settings_tab == null:
		return
	var sc = settings_tab.get_node_or_null("SettingsScroll")
	if sc == null:
		return
	var inner = sc.find_child("SettingsContent", true, false)
	if inner == null:
		return
	for card in inner.get_children():
		if not (card is PanelContainer):
			continue
		var found := false
		for sub in card.find_children("*", "Label", true, false):
			if sub is Label:
				var t: String = sub.text.to_lower()
				if "向量" in sub.text or "vector" in t \
					or "优化" in sub.text or "enhance" in t:
					found = true
					break
		if found:
			card.visible = false



func _collect_all_ctrls_v5(node: Node, out: Array):
	for c in node.get_children():
		if c is Control:
			out.append(c)
		_collect_all_ctrls_v5(c, out)


func _apply_layout_v5():
	var all_ctrls: Array = []
	_collect_all_ctrls_v5(self, all_ctrls)
	
	# ─── 1. 只对 OptionButton 做自适应 ───
	for c in all_ctrls:
		if c is OptionButton:
			if c != null: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.clip_text = true
			c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			c.fit_to_longest_item = false
			c.custom_minimum_size = Vector2(0, c.custom_minimum_size.y)
	
	# ─── 2. 预设三按钮：固定最小宽度 36 ───
	var add_pb = find_child("AddPresetBtn", true, false)
	var del_pb = find_child("DelPresetBtn", true, false)
	for b in [add_pb, edit_preset_btn, del_pb]:
		if b != null and b is Button:
			if b != null: b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.clip_text = false
			b.custom_minimum_size = Vector2(36, 32)
	
	# ─── 3. 字号按钮：宽度 56，完整显示 A- / A+ ───
	if font_size_minus_btn != null:
		font_size_minus_btn.icon = null
		font_size_minus_btn.text = "A-"
		font_size_minus_btn.custom_minimum_size = Vector2(56, 32)
		if font_size_minus_btn != null: font_size_minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		font_size_minus_btn.clip_text = false
	if font_size_plus_btn != null:
		font_size_plus_btn.icon = null
		font_size_plus_btn.text = "A+"
		font_size_plus_btn.custom_minimum_size = Vector2(56, 32)
		if font_size_plus_btn != null: font_size_plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		font_size_plus_btn.clip_text = false
	
	# ─── 4. close_edit_btn ───
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.clip_text = false
		close_edit_btn.custom_minimum_size = Vector2(96, 32)
		if close_edit_btn != null: close_edit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# ─── 5. 自定义指令输入框高度 ───
	if custom_prompt_input != null:
		custom_prompt_input.custom_minimum_size = Vector2(0, 120)
		custom_prompt_input.size_flags_vertical = Control.SIZE_FILL
	
	# ─── 6. 隐藏魔法操作 ───
	var m1 = find_child("MagicActionsBtn", true, false)
	if m1 != null and m1 is CanvasItem:
		m1.visible = false
	var m2 = find_child("MagicActionsBtn_Dummy", true, false)
	if m2 != null and m2 is CanvasItem:
		m2.visible = false
	
	# ─── 7. Settings 最小宽度 = Chat 最小宽度 ───
	var chat_tab = $TabContainer.get_node_or_null("Chat")
	var settings_tab = $TabContainer.get_node_or_null("Settings")
	if chat_tab != null and settings_tab != null:
		var cw: float = chat_tab.custom_minimum_size.x
		if cw <= 0.0:
			cw = 200.0
		settings_tab.custom_minimum_size = Vector2(cw, 0)



func _find_settings_vbox_v5() -> VBoxContainer:
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return null
	
	# 1. 递归找 SettingsContent（优先）
	var found = settings_tab.find_child("SettingsContent", true, false)
	if found != null and found is VBoxContainer:
		return found
	
	# 2. 找 SettingsScroll 里的第一个 VBoxContainer
	var scroll = settings_tab.find_child("SettingsScroll", true, false)
	if scroll != null:
		for c in scroll.get_children():
			if c is VBoxContainer:
				return c
	
	# 3. Settings 本身是 VBoxContainer 就用它
	if settings_tab is VBoxContainer:
		return settings_tab
	
	# 4. 兜底：从 Settings 的子节点找 VBoxContainer
	for c in settings_tab.get_children():
		if c is VBoxContainer:
			return c
		if c is ScrollContainer:
			for cc in c.get_children():
				if cc is VBoxContainer:
					return cc
	
	return null


func _ensure_extras_v5():
	# 等两帧让布局完成
	await get_tree().process_frame
	await get_tree().process_frame
	
	
	var inner = _find_settings_vbox_v5()
	if inner == null:
		return
	
	
	# 幂等检查
	var existing = inner.get_node_or_null("MyExtrasRoot")
	if existing != null:
		existing.visible = true
		return
	
	var root = VBoxContainer.new()
	root.name = "MyExtrasRoot"
	if root != null: root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	inner.add_child(root)
	
	var sep1 = HSeparator.new()
	root.add_child(sep1)
	
	var t1 = Label.new()
	t1.text = "附加内容"
	t1.add_theme_font_size_override("font_size", 14)
	t1.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	root.add_child(t1)
	
	var cb1 = CheckBox.new()
	cb1.text = "发送时附带当前时间"
	cb1.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
	cb1.button_pressed = _show_time_enabled
	cb1.toggled.connect(func(v):
		_show_time_enabled = v
		_save_ui_settings()
	)
	root.add_child(cb1)
	
	var cb2 = CheckBox.new()
	cb2.text = "显示 Token 数"
	cb2.tooltip_text = "消息下方显示消耗 Token 数"
	cb2.button_pressed = _show_token_enabled
	cb2.toggled.connect(func(v):
		_show_token_enabled = v
		_save_ui_settings()
	)
	root.add_child(cb2)
	
	var cb3 = CheckBox.new()
	cb3.text = "显示收发时间"
	cb3.tooltip_text = "消息下方显示发送/接收时间"
	cb3.button_pressed = _show_recv_time_enabled
	cb3.toggled.connect(func(v):
		_show_recv_time_enabled = v
		_save_ui_settings()
	)
	root.add_child(cb3)
	
	var sep2 = HSeparator.new()
	root.add_child(sep2)
	
	var t2 = Label.new()
	t2.text = "用量统计"
	t2.add_theme_font_size_override("font_size", 14)
	t2.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	root.add_child(t2)
	
	var summary = Label.new()
	summary.name = "UsageSummaryV5"
	summary.text = "（暂无数据）"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if summary != null: summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(summary)
	
	var refresh = Button.new()
	refresh.text = "刷新统计"
	refresh.clip_text = false
	refresh.custom_minimum_size = Vector2(96, 32)
	if refresh != null: refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	refresh.pressed.connect(func():
		_usage_load()
		_update_usage_summary_v5()
	)
	root.add_child(refresh)
	


func _update_usage_summary_v5():
	var inner = _find_settings_vbox_v5()
	if inner == null:
		return
	var summary = inner.find_child("UsageSummaryV5", true, false)
	if summary == null:
		return
	if _usage_entries.is_empty():
		summary.text = "（暂无数据）"
		return
	var total_p: int = 0
	var total_c: int = 0
	var total_t: int = 0
	for e in _usage_entries:
		total_p += int(e.get("prompt", 0))
		total_c += int(e.get("completion", 0))
		total_t += int(e.get("total", 0))
	summary.text = "总计：" + str(total_t) + " tokens\n输入：" + str(total_p) + " / 输出：" + str(total_c) + "\n记录条目：" + str(_usage_entries.size())



func _fix_settings_v6():
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var chat_tab = $TabContainer.get_node_or_null("Chat")
	var settings_tab = $TabContainer.get_node_or_null("Settings")
	if chat_tab == null or settings_tab == null:
		return
	
	# 两个 tab 都撑满
	if chat_tab != null: chat_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if settings_tab != null: settings_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Settings 最小宽度 = Chat 最小宽度（若 Chat 未设，用 200）
	var cw: float = chat_tab.custom_minimum_size.x
	if cw <= 0.0:
		cw = 200.0
	settings_tab.custom_minimum_size = Vector2(cw, 0)
	
	# 确保 SettingsScroll
	var scroll = settings_tab.get_node_or_null("SettingsScroll")
	if scroll == null:
		var existing: Array = []
		for c in settings_tab.get_children():
			existing.append(c)
		scroll = ScrollContainer.new()
		scroll.name = "SettingsScroll"
		if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.clip_contents = true
		settings_tab.add_child(scroll)
		var inner = VBoxContainer.new()
		inner.name = "SettingsContent"
		if inner != null: inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_theme_constant_override("separation", 12)
		scroll.add_child(inner)
		for c in existing:
			if c is Control:
				c.reparent(inner)
	elif scroll is ScrollContainer:
		if scroll != null: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.clip_contents = true
	


func _enforce_conv_buttons_v6():
	var conv_tab = $TabContainer.get_node_or_null("Conversations")
	if conv_tab == null:
		return
	# 顶部两个按钮
	for child in conv_tab.get_children():
		if child is HBoxContainer:
			for btn in child.get_children():
				if btn is Button:
					btn.clip_text = false
					if btn.name == "NewChatTopBtn" or btn.name == "RefreshTopBtn":
						btn.custom_minimum_size = Vector2(96, 32)
						if btn != null: btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# 对话行按钮
	if _conversation_list != null:
		for row in _conversation_list.get_children():
			if not (row is HBoxContainer):
				continue
			for btn in row.get_children():
				if not (btn is Button):
					continue
				var t: String = btn.text
				if t == "加载":
					btn.custom_minimum_size = Vector2(56, 32)
					btn.clip_text = false
					if btn != null: btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN



const _OPT_MAX_CHARS: int = 6

func _shrink_all_options_v7():
	_collect_options_v7(self)

func _collect_options_v7(node: Node):
	if node is OptionButton:
		_shrink_one_option_v7(node)
	for c in node.get_children():
		_collect_options_v7(c)

func _shrink_one_option_v7(btn: OptionButton):
	# 备份原 item 文本（第一次）
	if not btn.has_meta("__v7_orig"):
		var orig: Array = []
		for i in range(btn.item_count):
			orig.append(btn.get_item_text(i))
		btn.set_meta("__v7_orig", orig)
		# 弹窗前恢复
		var popup = btn.get_popup()
		if popup != null and not popup.about_to_popup.is_connected(_on_opt_about_to_popup_v7):
			popup.about_to_popup.connect(_on_opt_about_to_popup_v7.bind(btn))
		if popup != null and not popup.popup_hide.is_connected(_on_opt_popup_hide_v7):
			popup.popup_hide.connect(_on_opt_popup_hide_v7.bind(btn))
	
	_apply_short_text_v7(btn)


func _apply_short_text_v7(btn: OptionButton):
	if not btn.has_meta("__v7_orig"):
		return
	var orig: Array = btn.get_meta("__v7_orig")
	var cur: int = btn.selected
	# 遍历所有 item：当前项若太长，截短
	for i in range(min(btn.item_count, orig.size())):
		var full: String = str(orig[i])
		if i == cur and full.length() > _OPT_MAX_CHARS:
			btn.set_item_text(i, full.substr(0, _OPT_MAX_CHARS) + "…")
		else:
			# 非当前项：保持完整（反正没显示在按钮上）
			btn.set_item_text(i, full)


func _restore_full_text_v7(btn: OptionButton):
	if not btn.has_meta("__v7_orig"):
		return
	var orig: Array = btn.get_meta("__v7_orig")
	for i in range(min(btn.item_count, orig.size())):
		btn.set_item_text(i, str(orig[i]))


func _on_opt_about_to_popup_v7(btn: OptionButton):
	_restore_full_text_v7(btn)


func _on_opt_popup_hide_v7(btn: OptionButton):
	call_deferred("_apply_short_text_v7", btn)



func _fix_options_v9():
	_collect_fix_options_v9(self)

func _collect_fix_options_v9(node: Node):
	if node is OptionButton:
		_do_fix_option_v9(node)
	for c in node.get_children():
		_collect_fix_options_v9(c)

func _do_fix_option_v9(btn: OptionButton):
	if btn == null:
		return
	if btn.item_count == 0:
		return
	
	# 备份原始文本（首次）
	if not btn.has_meta("__v9_orig"):
		var orig: Array = []
		for i in range(btn.item_count):
			orig.append(btn.get_item_text(i))
		btn.set_meta("__v9_orig", orig)
		var popup = btn.get_popup()
		if popup != null and not popup.about_to_popup.is_connected(_on_v9_about_popup):
			popup.about_to_popup.connect(_on_v9_about_popup.bind(btn))
		if popup != null and not popup.popup_hide.is_connected(_on_v9_popup_hide):
			popup.popup_hide.connect(_on_v9_popup_hide.bind(btn))
	
	# 应用到当前项
	_apply_v9_short(btn)


func _apply_v9_short(btn: OptionButton):
	if btn == null:
		return
	if not btn.has_meta("__v9_orig"):
		return
	var orig: Array = btn.get_meta("__v9_orig", [])
	if orig.is_empty():
		return
	var cur: int = btn.selected
	var n: int = min(btn.item_count, orig.size())
	for i in range(n):
		var full: String = str(orig[i])
		if i == cur and full.length() > 5:
			btn.set_item_text(i, full.substr(0, 5) + "…")
		else:
			btn.set_item_text(i, full)
	if cur < 0:
		for i in range(n):
			var full2: String = str(orig[i])
			if full2.length() > 5:
				btn.set_item_text(i, full2.substr(0, 5) + "…")


func _on_v9_about_popup(btn: OptionButton):
	if btn == null:
		return
	if not btn.has_meta("__v9_orig"):
		return
	var orig: Array = btn.get_meta("__v9_orig", [])
	for i in range(min(btn.item_count, orig.size())):
		btn.set_item_text(i, str(orig[i]))


func _on_v9_popup_hide(btn: OptionButton):
	call_deferred("_apply_v9_short", btn)



func _v10_final():
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var chat = $TabContainer.get_node_or_null("Chat")
	var settings = $TabContainer.get_node_or_null("Settings")
	if chat == null or settings == null:
		return
	
	# 打印诊断
	
	var stack: Array = [settings]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Control and n != settings:
			var ms = n.get_combined_minimum_size()
			if ms.x > 180:
				pass
		for c in n.get_children():
			stack.append(c)
	
	# 强制所有 tab 页宽度相等
	var target: float = 200.0
	for child in $TabContainer.get_children():
		if child is Control:
			child.custom_minimum_size = Vector2(target, child.custom_minimum_size.y)



class UsageChart:
	extends Control
	var chart_data: Array = []  # [{"label": String, "value": int}]
	
	func set_chart_data(d: Array):
		chart_data = d
		queue_redraw()
	
	func _draw():
		var w: float = size.x
		var h: float = size.y
		if chart_data.is_empty() or w < 20 or h < 20:
			return
		var total: float = 0.0
		for item in chart_data:
			total += float(item.get("value", 0))
		if total <= 0.0:
			return
		
		var colors := [
			Color(0.35, 0.65, 1.0),
			Color(0.35, 0.9, 0.55),
			Color(1.0, 0.75, 0.35),
			Color(1.0, 0.45, 0.45),
			Color(0.75, 0.5, 1.0),
			Color(0.4, 0.85, 0.9),
		]
		
		var n: int = chart_data.size()
		var gap: float = 4.0
		var bar_w: float = (w - gap * float(n + 1)) / float(n)
		var font = ThemeDB.fallback_font
		
		for i in range(n):
			var item = chart_data[i]
			var ratio: float = float(item.get("value", 0)) / total
			var bar_h: float = max(4.0, h * ratio)
			var x: float = gap + i * (bar_w + gap)
			var y: float = h - bar_h
			var color: Color = colors[i % colors.size()]
			draw_rect(Rect2(x, y, bar_w, bar_h), color, true)
			# 标签
			var label: String = str(item.get("label", ""))
			if label.length() > 10:
				label = label.substr(0, 10) + "…"
			draw_string(font, Vector2(x, y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, bar_w + 20, 11, Color(0.8, 0.85, 0.95))
			# 数值
			draw_string(font, Vector2(x, h + 14), str(item.get("value", 0)), HORIZONTAL_ALIGNMENT_LEFT, bar_w + 20, 10, Color(0.6, 0.65, 0.75))


var _usage_chart: Control = null

func _ensure_usage_chart():
	if _usage_chart != null and is_instance_valid(_usage_chart):
		return
	var settings_tab = $TabContainer/Settings
	if settings_tab == null:
		return
	var scroll = settings_tab.find_child("SettingsScroll", true, false)
	if scroll == null:
		return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null:
		inner = settings_tab
	
	# 找 MyExtrasRoot（修复5/6 里创建的），若没有就在 inner 末尾
	var target: Node = inner.get_node_or_null("MyExtrasRoot")
	if target == null:
		target = inner
	
	_usage_chart = UsageChart.new()
	_usage_chart.name = "UsageChart"
	_usage_chart.custom_minimum_size = Vector2(0, 180)
	if _usage_chart != null: _usage_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(_usage_chart)


func _refresh_usage_chart():
	_ensure_usage_chart()
	if _usage_chart == null:
		return
	# 按 model 分组求和
	var by_model: Dictionary = {}
	for e in _usage_entries:
		var model: String = str(e.get("model", "unknown"))
		var total_t: int = int(e.get("total", 0))
		if not by_model.has(model):
			by_model[model] = 0
		by_model[model] += total_t
	# 转成数组
	var data: Array = []
	for model in by_model.keys():
		data.append({"label": str(model), "value": int(by_model[model])})
	# 排序（按值降序）
	data.sort_custom(func(a, b): return a["value"] > b["value"])
	if _usage_chart.has_method("set_chart_data"):
		_usage_chart.call("set_chart_data", data)



const _V11_MAX_CHARS: int = 6

func _v11_shorten_all_options():
	_v11_collect(self)

func _v11_collect(node: Node):
	if node is OptionButton:
		_v11_process_option(node)
	for c in node.get_children():
		_v11_collect(c)

func _v11_process_option(btn: OptionButton):
	if btn == null or btn.item_count == 0:
		return
	var cnt: int = btn.item_count
	
	# 备份（首次或 item 数量变化）
	var has := btn.has_meta("__v11_orig")
	var orig: Array = []
	if has:
		orig = btn.get_meta("__v11_orig", [])
	
	if not has or orig.size() != cnt:
		orig = []
		for i in range(cnt):
			orig.append(btn.get_item_text(i))
		btn.set_meta("__v11_orig", orig)
		# 连接 popup 信号
		var popup = btn.get_popup()
		if popup != null:
			if not popup.about_to_popup.is_connected(_v11_on_popup_about):
				popup.about_to_popup.connect(_v11_on_popup_about.bind(btn))
			if not popup.popup_hide.is_connected(_v11_on_popup_hide):
				popup.popup_hide.connect(_v11_on_popup_hide.bind(btn))
	
	_v11_apply(btn)


func _v11_apply(btn: OptionButton):
	if btn == null: return
	if not btn.has_meta("__v11_orig"): return
	var orig: Array = btn.get_meta("__v11_orig", [])
	if orig.is_empty(): return
	var cur: int = btn.selected
	var n: int = mini(btn.item_count, orig.size())
	for i in range(n):
		var full: String = str(orig[i])
		if i == cur and full.length() > _V11_MAX_CHARS:
			btn.set_item_text(i, full.substr(0, _V11_MAX_CHARS) + "…")
		else:
			btn.set_item_text(i, full)
	if cur < 0:
		for i in range(n):
			var full2: String = str(orig[i])
			if full2.length() > _V11_MAX_CHARS:
				btn.set_item_text(i, full2.substr(0, _V11_MAX_CHARS) + "…")


func _v11_restore(btn: OptionButton):
	if btn == null or not btn.has_meta("__v11_orig"):
		return
	var orig: Array = btn.get_meta("__v11_orig", [])
	for i in range(mini(btn.item_count, orig.size())):
		btn.set_item_text(i, str(orig[i]))


func _v11_on_popup_about(btn: OptionButton):
	_v11_restore(btn)


func _v11_on_popup_hide(btn: OptionButton):
	call_deferred("_v11_apply", btn)


func _v11_dump_settings_width():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null:
		return
	var cw = settings.custom_minimum_size
	var ms = settings.get_combined_minimum_size()
	var stack: Array = [settings]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 150:
					pass
			if c is Node:
				stack.append(c)



var _tool_progress_label: Label = null

func _ensure_tool_progress_label():
	if _tool_progress_label != null and is_instance_valid(_tool_progress_label):
		return
	var chat_tab = $TabContainer.get_node_or_null("Chat")
	if chat_tab == null:
		return
	_tool_progress_label = Label.new()
	_tool_progress_label.name = "ToolProgressLabel"
	_tool_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_progress_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	_tool_progress_label.add_theme_font_size_override("font_size", 12)
	_tool_progress_label.visible = false
	if _tool_progress_label != null: _tool_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_tab.add_child(_tool_progress_label)
	if selection_status != null and selection_status.get_parent() == chat_tab:
		var sel_idx: int = selection_status.get_index()
		if sel_idx >= 0:
			chat_tab.move_child(_tool_progress_label, sel_idx)


func _set_tool_progress(text: String):
	_ensure_tool_progress_label()
	if _tool_progress_label == null:
		return
	_tool_progress_label.text = text
	_tool_progress_label.visible = true


func _clear_tool_progress():
	if _tool_progress_label != null and is_instance_valid(_tool_progress_label):
		_tool_progress_label.visible = false
		_tool_progress_label.text = ""



# ═══════════════════════════════════════════════════════════════
# 修复13：滚动限制 + 下拉框宽度测试
# ═══════════════════════════════════════════════════════════════

var _v13_scroll_bound: bool = false

func _v13_fix_scroll():
	if chat_scroll == null:
		return
	if _v13_scroll_bound:
		return
	_v13_scroll_bound = true
	# 捕获滚轮事件，覆盖默认的加速滚动
	if not chat_scroll.gui_input.is_connected(_v13_on_chat_scroll_input):
		chat_scroll.gui_input.connect(_v13_on_chat_scroll_input)


func _v13_on_chat_scroll_input(event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var vbar = chat_scroll.get_v_scroll_bar()
	if vbar == null:
		return
	# 每次滚动 40px（默认是 50~80，可能加速度高）
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		vbar.value += 40
		chat_scroll.accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		vbar.value -= 40
		chat_scroll.accept_event()


func _v13_fix_option_widths():
	# 给三个下拉框固定一个小的宽度，测试是否能影响 Settings 最小宽度
	if language_selector != null:
		language_selector.custom_minimum_size = Vector2(120, 0)
		if language_selector != null: language_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if preset_selector != null:
		preset_selector.custom_minimum_size = Vector2(120, 0)
		if preset_selector != null: preset_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if chat_preset_selector != null:
		chat_preset_selector.custom_minimum_size = Vector2(120, 0)
		if chat_preset_selector != null: chat_preset_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if provider_selector != null:
		provider_selector.custom_minimum_size = Vector2(120, 0)
		if provider_selector != null: provider_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN



# ═══════════════════════════════════════════════════════════════
# 修复14：下拉框自适应 + 递归诊断
# ═══════════════════════════════════════════════════════════════

func _v14_fix_option_widths():
	# 下拉框：自定义最小值 60，可压缩，显示当前项（超长省略）
	var opts: Array = []
	if language_selector != null: opts.append(language_selector)
	if preset_selector != null: opts.append(preset_selector)
	if chat_preset_selector != null: opts.append(chat_preset_selector)
	if provider_selector != null: opts.append(provider_selector)
	
	for c in opts:
		c.custom_minimum_size = Vector2(60, 0)
		c.size_flags_horizontal = Control.SIZE_FILL
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.fit_to_longest_item = false


func _v14_dump_settings_tree():
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null:
		return
	
	
	# 正确的递归遍历（不管是不是 Control 都入栈）
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 160:
					pass
			stack.append(c)
	
	# 额外：看 TabContainer 的子页
	var tc = $TabContainer
	for child in tc.get_children():
		if child is Control:
			pass



# ═══════════════════════════════════════════════════════════════
# 修复16：下拉框/刷新按钮缩小 + 去重
# ═══════════════════════════════════════════════════════════════

func _v16_fix_all():
	# 1. 缩小下拉框
	var opts: Array = []
	if language_selector != null: opts.append(language_selector)
	if preset_selector != null: opts.append(preset_selector)
	if chat_preset_selector != null: opts.append(chat_preset_selector)
	if provider_selector != null: opts.append(provider_selector)
	for c in opts:
		c.custom_minimum_size = Vector2(40, 0)
		c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.fit_to_longest_item = false
	
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	# 2. 缩小"刷新统计"按钮
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Button and str(n.text) == "刷新统计":
			n.custom_minimum_size = Vector2(60, 28)
			n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			n.clip_text = true
			n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for c in n.get_children():
			stack.append(c)
	
	# 3. 删除重复的"附加内容"/"用量统计"
	_v16_dedupe(settings)
	
	# 4. 诊断
	_v16_dump()


func _v16_dedupe(root: Node):
	# 用 metadata 标记已处理的父容器
	var stack: Array = [root]
	var killed := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text)
				if t.begins_with("附加内容"):
					var p = c.get_parent()
					if p != null and is_instance_valid(p):
						if p.has_meta("__v16_extras_seen"):
							# 重复 → 删整个父 VBox
							if p is VBoxContainer:
								p.queue_free()
								killed += 1
								continue
							else:
								c.queue_free()
								killed += 1
								continue
						else:
							p.set_meta("__v16_extras_seen", true)
				elif t.begins_with("用量统计"):
					var p2 = c.get_parent()
					if p2 != null and is_instance_valid(p2):
						if p2.has_meta("__v16_usage_seen"):
							if p2 is VBoxContainer:
								p2.queue_free()
								killed += 1
								continue
							else:
								c.queue_free()
								killed += 1
								continue
						else:
							p2.set_meta("__v16_usage_seen", true)
			stack.append(c)


func _v16_dump():
	var chat = $TabContainer.get_node_or_null("Chat")
	var settings = $TabContainer.get_node_or_null("Settings")
	if chat == null or settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 120:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复17
# ═══════════════════════════════════════════════════════════════

func _v17_fix_settings_dropdowns():
	# 只处理 Settings 页里的下拉框，不动 chat_preset_selector
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var dropdowns: Array = []
	if preset_selector != null: dropdowns.append(preset_selector)
	if provider_selector != null: dropdowns.append(provider_selector)
	if language_selector != null: dropdowns.append(language_selector)
	
	for c in dropdowns:
		c.custom_minimum_size = Vector2(40, 0)
		c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.fit_to_longest_item = false
	
	# 聊天页的下拉框：恢复 EXPAND_FILL
	if chat_preset_selector != null:
		chat_preset_selector.custom_minimum_size = Vector2(60, 0)
		chat_preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_preset_selector.clip_text = true
		chat_preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chat_preset_selector.fit_to_longest_item = false


func _v17_force_dedupe():
	# 暴力删除双重附加内容 / 用量统计 —— 只保留第一组
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var extras_seen := false
	var usage_seen := false
	var to_free: Array = []
	
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text).strip_edges()
				if t == "附加内容" or t.begins_with("附加内容"):
					if extras_seen:
						# 找到这个 Label 的父容器整个删
						var par = c.get_parent()
						if par != null and is_instance_valid(par) and not to_free.has(par):
							to_free.append(par)
					else:
						extras_seen = true
				elif t == "用量统计" or t.begins_with("用量统计"):
					if usage_seen:
						var par2 = c.get_parent()
						if par2 != null and is_instance_valid(par2) and not to_free.has(par2):
							to_free.append(par2)
					else:
						usage_seen = true
			stack.append(c)
	
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()


func _v17_dump():
	var chat = $TabContainer.get_node_or_null("Chat")
	var settings = $TabContainer.get_node_or_null("Settings")
	if chat == null or settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 120:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复18
# ═══════════════════════════════════════════════════════════════

func _v18_dump_selection():
	if selection_status == null:
		return
	var par = selection_status.get_parent()
	print("[AI助手-v18] selection_status 父=", par.name if par != null else "无",
		" visible=", selection_status.visible,
		" text=", selection_status.text)
	if context_manager != null:
		var sel = context_manager.get_selection_info()


func _v18_fix_selection():
	if selection_status == null: return
	var chat_tab = $TabContainer.get_node_or_null("Chat")
	if chat_tab == null: return
	if selection_status.get_parent() != chat_tab:
		selection_status.reparent(chat_tab)
	var input_vbox = chat_tab.get_node_or_null("InputVBox")
	if input_vbox != null:
		var idx: int = input_vbox.get_index()
		if idx >= 0:
			chat_tab.move_child(selection_status, idx)
	selection_status.visible = true
	selection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	selection_status.clip_text = true
	selection_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _v18_rebuild_extras():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var scroll = settings.find_child("SettingsScroll", true, false)
	if scroll == null:
		return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null:
		return
	
	var children = inner.get_children()
	var start_idx := -1
	for i in range(children.size()):
		var c = children[i]
		if c is Label and str(c.text).begins_with("附加内容"):
			start_idx = i
			break
	
	if start_idx == -1:
		pass
	else:
		for i in range(children.size() - 1, start_idx - 1, -1):
			children[i].queue_free()
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	if has_method("_ensure_extras_v5"):
		_ensure_extras_v5()


func _v18_shrink_settings():
	var settings = $TabContainer/Settings
	if settings == null: return
	var stack: Array = [settings]
	var n_opt := 0
	var n_lbl := 0
	var n_btn := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is OptionButton:
				n.custom_minimum_size = Vector2(40, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n_opt += 1
			elif n is Label:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n_lbl += 1
			elif n is Button:
				var txt: String = str(n.text)
				if txt == "刷新统计" or "Preset" in str(n.name) or "Usage" in str(n.name) or "Add" in str(n.name) or "Del" in str(n.name) or "Edit" in str(n.name):
					n.custom_minimum_size = Vector2(60, 28)
					n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					n.clip_text = true
					n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					n_btn += 1
			elif n is LineEdit:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
			elif n is TextEdit:
				# 高度保留，宽度缩
				var h: float = n.custom_minimum_size.y
				if h <= 0.0 or h > 200.0:
					h = 120.0
				n.custom_minimum_size = Vector2(0, h)
		for c in n.get_children():
			stack.append(c)


func _v18_dump_settings():
	var chat = $TabContainer.get_node_or_null("Chat")
	var settings = $TabContainer.get_node_or_null("Settings")
	if chat == null or settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 140:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复19
# ═══════════════════════════════════════════════════════════════

func _v19_remove_extra_separators():
	# 删除 SettingsContent 里相邻的 HSeparator（两个分隔线之间只有空白）
	var settings = $TabContainer/Settings
	if settings == null: return
	var inner = settings.find_child("SettingsContent", true, false)
	if inner == null:
		inner = settings
	var children = inner.get_children()
	var to_free: Array = []
	for i in range(children.size() - 1):
		var a = children[i]
		var b = children[i + 1]
		if a is HSeparator and b is HSeparator:
			to_free.append(b)
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()


func _v19_shrink_all_hard():
	var settings = $TabContainer/Settings
	if settings == null: return
	var stack: Array = [settings]
	var n_opt := 0
	var n_label := 0
	var n_btn := 0
	var n_edit := 0
	var n_textedit := 0
	var n_checkbox := 0
	var n_panel := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is OptionButton:
				n.custom_minimum_size = Vector2(30, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
				n_opt += 1
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n_checkbox += 1
			elif n is Label:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n_label += 1
			elif n is Button:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n_btn += 1
			elif n is LineEdit:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n_edit += 1
			elif n is TextEdit:
				var h: float = n.custom_minimum_size.y
				if h <= 0.0 or h > 150.0:
					h = 100.0
				n.custom_minimum_size = Vector2(0, h)
				n.size_flags_horizontal = Control.SIZE_FILL
				n_textedit += 1
			elif n is PanelContainer or n is MarginContainer:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n_panel += 1
		for c in n.get_children():
			stack.append(c)
	print("[AI助手-v19] 缩窄: Opt×", n_opt, " Label×", n_label, " Btn×", n_btn,
		" LineEdit×", n_edit, " TextEdit×", n_textedit,
		" CheckBox×", n_checkbox, " Panel×", n_panel)


func _v19_dump_settings():
	var chat = $TabContainer.get_node_or_null("Chat")
	var settings = $TabContainer.get_node_or_null("Settings")
	if chat == null or settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 100:
					pass
			stack.append(c)


func _v19_shrink_window():
	# 缩小整个 dock 的字体和标签尺寸
	var settings = $TabContainer/Settings
	if settings == null: return
	# 缩小 Label 字号
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Label:
			n.add_theme_font_size_override("font_size", 11)
		for c in n.get_children():
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复20：全面缩小 + 全局诊断
# ═══════════════════════════════════════════════════════════════

func _v20_shrink_everything():
	var total_opt := 0
	var total_label := 0
	var total_btn := 0
	var total_edit := 0
	var total_textedit := 0
	var total_checkbox := 0
	var total_panel := 0
	var total_sep := 0
	
	var stack: Array = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != self:
			# 所有 Control 的 x 最小宽度缩到 0
			if n is OptionButton:
				n.custom_minimum_size = Vector2(30, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
				total_opt += 1
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				total_checkbox += 1
			elif n is Label:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.add_theme_font_size_override("font_size", 10)
				total_label += 1
			elif n is Button:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.add_theme_font_size_override("font_size", 11)
				total_btn += 1
			elif n is LineEdit:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.add_theme_font_size_override("font_size", 11)
				total_edit += 1
			elif n is TextEdit:
				var h: float = n.custom_minimum_size.y
				if h <= 0.0 or h > 100.0:
					h = 80.0
				n.custom_minimum_size = Vector2(0, h)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.add_theme_font_size_override("font_size", 11)
				total_textedit += 1
			elif n is PanelContainer or n is MarginContainer:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				total_panel += 1
			elif n is HSeparator:
				n.custom_minimum_size = Vector2(0, 4)
				total_sep += 1
		
		for c in n.get_children():
			stack.append(c)
	
	print("[AI助手-v20] 缩窄: Opt×", total_opt, " Label×", total_label,
		" Btn×", total_btn, " LineEdit×", total_edit,
		" TextEdit×", total_textedit, " CheckBox×", total_checkbox,
		" Panel×", total_panel, " Sep×", total_sep)


func _v20_remove_dup_separators():
	# 遍历所有 VBoxContainer，删除相邻的 HSeparator
	var stack: Array = [self]
	var killed := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is VBoxContainer:
			var children = n.get_children()
			var to_free: Array = []
			for i in range(children.size() - 1):
				var a = children[i]
				var b = children[i + 1]
				if a is HSeparator and b is HSeparator:
					to_free.append(b)
			for x in to_free:
				if is_instance_valid(x):
					x.queue_free()
					killed += 1
		for c in n.get_children():
			stack.append(c)


func _v20_dump_all():
	# 打印所有 tab 页以及它们的 minimum_size
	var tc = $TabContainer
	if tc == null: return
	for child in tc.get_children():
		if child is Control:
			pass
	
	# 打印整个 dock 里所有 minimum_size > 100 的 Control
	var stack: Array = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control:
				var cms = c.get_combined_minimum_size()
				if cms.x > 100:
					# 找它的完整路径
					var path := str(c.get_path())
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复21：只对 Settings 页操作
# ═══════════════════════════════════════════════════════════════

func _v21_remove_all_separators():
	var settings = $TabContainer/Settings
	if settings == null: return
	var stack: Array = [settings]
	var killed := 0
	var to_free: Array = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is HSeparator:
			to_free.append(n)
		for c in n.get_children():
			stack.append(c)
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()
			killed += 1


func _v21_shrink_settings_only():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var opt_n := 0
	var lbl_n := 0
	var btn_n := 0
	var le_n := 0
	var te_n := 0
	var cb_n := 0
	var panel_n := 0
	
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is OptionButton:
				n.custom_minimum_size = Vector2(30, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
				opt_n += 1
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.add_theme_font_size_override("font_size", 11)
				cb_n += 1
			elif n is Label:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.add_theme_font_size_override("font_size", 10)
				lbl_n += 1
			elif n is Button:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.add_theme_font_size_override("font_size", 11)
				btn_n += 1
			elif n is LineEdit:
				# 输入框宽度全缩
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.add_theme_font_size_override("font_size", 11)
				le_n += 1
			elif n is TextEdit:
				var h: float = n.custom_minimum_size.y
				if h <= 0.0 or h > 100.0:
					h = 80.0
				n.custom_minimum_size = Vector2(0, h)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.add_theme_font_size_override("font_size", 11)
				te_n += 1
			elif n is PanelContainer or n is MarginContainer:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				panel_n += 1
		for c in n.get_children():
			stack.append(c)
	
	print("[AI助手-v21] Settings 缩窄: Opt×", opt_n, " Label×", lbl_n,
		" Btn×", btn_n, " LineEdit×", le_n, " TextEdit×", te_n,
		" CheckBox×", cb_n, " Panel×", panel_n)


func _v21_rebuild_extras():
	# 删除旧的附加内容 / 用量统计，重建
	var settings = $TabContainer/Settings
	if settings == null: return
	var scroll = settings.find_child("SettingsScroll", true, false)
	if scroll == null: return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null:
		inner = settings
	
	var children = inner.get_children()
	var start_idx := -1
	for i in range(children.size()):
		var c = children[i]
		if c is Label and str(c.text).begins_with("附加内容"):
			start_idx = i
			break
	
	if start_idx == -1:
		pass
	else:
		for i in range(children.size() - 1, start_idx - 1, -1):
			children[i].queue_free()
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	if has_method("_ensure_extras_v5"):
		_ensure_extras_v5()
	
	# 重建完立即再缩一遍
	await get_tree().process_frame
	await get_tree().process_frame
	_v21_shrink_settings_only()


func _v21_dump_settings():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 100:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复22：Settings 控件正常尺寸 + 自适应
# ═══════════════════════════════════════════════════════════════

func _v22_restore_settings_sizes():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var opt_n := 0
	var lbl_n := 0
	var btn_n := 0
	var le_n := 0
	var te_n := 0
	var cb_n := 0
	
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is OptionButton:
				# 下拉框：撑满父容器，最小宽 60
				n.custom_minimum_size = Vector2(60, 0)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
				n.remove_theme_font_size_override("font_size")
				opt_n += 1
			elif n is CheckBox:
				# CheckBox：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				n.remove_theme_font_size_override("font_size")
				cb_n += 1
			elif n is Label:
				# 标签：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				n.remove_theme_font_size_override("font_size")
				lbl_n += 1
			elif n is Button:
				# 按钮：按内容自然宽度
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				n.remove_theme_font_size_override("font_size")
				btn_n += 1
			elif n is LineEdit:
				# 输入框：撑满父容器，最小宽 80
				n.custom_minimum_size = Vector2(80, 0)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.remove_theme_font_size_override("font_size")
				le_n += 1
			elif n is TextEdit:
				# 多行输入框：撑满父容器，高 120
				n.custom_minimum_size = Vector2(0, 120)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.remove_theme_font_size_override("font_size")
				te_n += 1
			elif n is PanelContainer or n is MarginContainer:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
		for c in n.get_children():
			stack.append(c)
	
	print("[AI助手-v22] Settings 恢复: Opt×", opt_n, " Label×", lbl_n,
		" Btn×", btn_n, " LineEdit×", le_n, " TextEdit×", te_n,
		" CheckBox×", cb_n)


func _v22_fix_extras_sizes():
	# 专门处理附加内容 / 用量统计的控件
	var settings = $TabContainer/Settings
	if settings == null: return
	var scroll = settings.find_child("SettingsScroll", true, false)
	if scroll == null: return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null: return
	
	# 遍历 MyExtrasRoot（如果存在）
	var extras = inner.get_node_or_null("MyExtrasRoot")
	if extras == null:
		return
	
	var stack: Array = [extras]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control:
			if n is Button:
				# 刷新统计按钮：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = false
				n.remove_theme_font_size_override("font_size")
			elif n is Label:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.remove_theme_font_size_override("font_size")
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.remove_theme_font_size_override("font_size")
		for c in n.get_children():
			stack.append(c)


func _v22_dump():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 200:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复23：只恢复 Settings 页的尺寸（其他页完全不动）
# ═══════════════════════════════════════════════════════════════

func _v23_restore_settings():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var opt_n := 0
	var lbl_n := 0
	var btn_n := 0
	var le_n := 0
	var te_n := 0
	var cb_n := 0
	var panel_n := 0
	var sep_n := 0
	
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			# 清理所有之前脚本加的 font_size override
			n.remove_theme_font_size_override("font_size")
			n.remove_theme_font_size_override("normal_font_size")
			n.remove_theme_font_size_override("bold_font_size")
			
			if n is OptionButton:
				n.custom_minimum_size = Vector2(60, 32)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
				opt_n += 1
			elif n is LineEdit:
				n.custom_minimum_size = Vector2(80, 32)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le_n += 1
			elif n is TextEdit:
				n.custom_minimum_size = Vector2(0, 120)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
				te_n += 1
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				cb_n += 1
			elif n is Label:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				lbl_n += 1
			elif n is Button:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = false
				n.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				btn_n += 1
			elif n is PanelContainer or n is MarginContainer:
				n.custom_minimum_size = Vector2(0, n.custom_minimum_size.y)
				panel_n += 1
			elif n is HSeparator:
				n.custom_minimum_size = Vector2(0, 8)
				sep_n += 1
		for c in n.get_children():
			stack.append(c)
	
	print("[AI助手-v23] Settings 恢复: Opt×", opt_n, " Label×", lbl_n,
		" Btn×", btn_n, " LineEdit×", le_n, " TextEdit×", te_n,
		" CheckBox×", cb_n, " Panel×", panel_n, " Sep×", sep_n)
	
	# 打印实际最小宽度



# ═══════════════════════════════════════════════════════════════
# 修复24：只处理 Settings 页
# ═══════════════════════════════════════════════════════════════

func _v24_setup_settings():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var icon_base: String = "res://addons/gamedev_ai/assets/icons/"
	
	# ─── 1. 下拉框：自适应 ───
	if preset_selector != null:
		preset_selector.custom_minimum_size = Vector2(100, 32)
		preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_selector.clip_text = true
		preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preset_selector.fit_to_longest_item = false
	if provider_selector != null:
		provider_selector.custom_minimum_size = Vector2(100, 32)
		provider_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		provider_selector.clip_text = true
		provider_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		provider_selector.fit_to_longest_item = false
	if language_selector != null:
		language_selector.custom_minimum_size = Vector2(100, 32)
		language_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		language_selector.clip_text = true
		language_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		language_selector.fit_to_longest_item = false
	
	# ─── 2. 预设三按钮：只留图标 ───
	var add_pb = find_child("AddPresetBtn", true, false)
	var del_pb = find_child("DelPresetBtn", true, false)
	if add_pb != null and add_pb is Button:
		add_pb.text = ""
		add_pb.icon = _load_svg_icon(icon_base + "plus.svg", "ffffff", 0.7)
		add_pb.custom_minimum_size = Vector2(32, 32)
		add_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_pb.tooltip_text = "添加预设"
	if edit_preset_btn != null:
		edit_preset_btn.text = ""
		edit_preset_btn.icon = _load_svg_icon(icon_base + "rename.svg", "ffffff", 0.7)
		edit_preset_btn.custom_minimum_size = Vector2(32, 32)
		edit_preset_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		edit_preset_btn.tooltip_text = "编辑预设"
	if del_pb != null and del_pb is Button:
		del_pb.text = ""
		del_pb.icon = _load_svg_icon(icon_base + "delete.svg", "ffffff", 0.7)
		del_pb.custom_minimum_size = Vector2(32, 32)
		del_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		del_pb.tooltip_text = "删除预设"
	
	# ─── 3. API 输入框缩小 ───
	if api_input != null:
		api_input.custom_minimum_size = Vector2(60, 32)
		api_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if url_input != null:
		url_input.custom_minimum_size = Vector2(60, 32)
		url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if model_input != null:
		model_input.custom_minimum_size = Vector2(60, 32)
		model_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if preset_name_input != null:
		preset_name_input.custom_minimum_size = Vector2(60, 32)
		preset_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# ─── 4. 自定义指令输入框缩小 ───
	if custom_prompt_input != null:
		custom_prompt_input.custom_minimum_size = Vector2(0, 100)
		custom_prompt_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	


func _v24_dedupe_extras():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var scroll = settings.find_child("SettingsScroll", true, false)
	if scroll == null:
		return
	var inner = scroll.find_child("SettingsContent", true, false)
	if inner == null:
		inner = settings
	
	# 删重复的"附加内容" / "用量统计"
	var extras_seen := false
	var usage_seen := false
	var to_free: Array = []
	
	var stack: Array = [inner]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text).strip_edges()
				var is_extras: bool = t.begins_with("附加内容")
				var is_usage: bool = t.begins_with("用量统计")
				if is_extras:
					if extras_seen:
						var par = c.get_parent()
						if par != null and is_instance_valid(par) and not to_free.has(par):
							to_free.append(par)
					else:
						extras_seen = true
				elif is_usage:
					if usage_seen:
						var par2 = c.get_parent()
						if par2 != null and is_instance_valid(par2) and not to_free.has(par2):
							to_free.append(par2)
					else:
						usage_seen = true
			stack.append(c)
	
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()


func _v24_dump():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return



# ═══════════════════════════════════════════════════════════════
# 修复25：输入框宽度缩到 0.3 倍
# ═══════════════════════════════════════════════════════════════

func _v25_shrink_inputs():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var le_n := 0
	var te_n := 0
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is LineEdit:
				var cur_x: float = n.custom_minimum_size.x
				if cur_x <= 0.0:
					cur_x = 200.0   # 默认给 200 作为基数
				var new_x: float = cur_x * 0.3
				if new_x < 20.0:
					new_x = 20.0
				n.custom_minimum_size = Vector2(new_x, n.custom_minimum_size.y)
				le_n += 1
			elif n is TextEdit:
				var cur_x2: float = n.custom_minimum_size.x
				if cur_x2 <= 0.0:
					cur_x2 = 200.0
				var new_x2: float = cur_x2 * 0.3
				if new_x2 < 20.0:
					new_x2 = 20.0
				n.custom_minimum_size = Vector2(new_x2, n.custom_minimum_size.y)
				te_n += 1
		for c in n.get_children():
			stack.append(c)
	


func _v25_dump():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return



# ═══════════════════════════════════════════════════════════════
# 修复26：Settings 页所有控件最小宽度 < 200
# ═══════════════════════════════════════════════════════════════

func _v26_fix_settings():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var icon_base: String = "res://addons/gamedev_ai/assets/icons/"
	
	# ─── 1. 所有下拉框 → min 40 ───
	if preset_selector != null:
		preset_selector.custom_minimum_size = Vector2(40, 32)
		preset_selector.size_flags_horizontal = Control.SIZE_FILL
		preset_selector.clip_text = true
		preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preset_selector.fit_to_longest_item = false
	if provider_selector != null:
		provider_selector.custom_minimum_size = Vector2(40, 32)
		provider_selector.size_flags_horizontal = Control.SIZE_FILL
		provider_selector.clip_text = true
		provider_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		provider_selector.fit_to_longest_item = false
	if language_selector != null:
		language_selector.custom_minimum_size = Vector2(40, 32)
		language_selector.size_flags_horizontal = Control.SIZE_FILL
		language_selector.clip_text = true
		language_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		language_selector.fit_to_longest_item = false
	
	# ─── 2. 预设三按钮：图标 + 28×28 ───
	var add_pb = find_child("AddPresetBtn", true, false)
	var del_pb = find_child("DelPresetBtn", true, false)
	if add_pb != null and add_pb is Button:
		add_pb.text = ""
		add_pb.icon = _load_svg_icon(icon_base + "plus.svg", "ffffff", 0.7)
		add_pb.custom_minimum_size = Vector2(28, 28)
		add_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_pb.tooltip_text = "添加预设"
	if edit_preset_btn != null:
		edit_preset_btn.text = ""
		edit_preset_btn.icon = _load_svg_icon(icon_base + "rename.svg", "ffffff", 0.7)
		edit_preset_btn.custom_minimum_size = Vector2(28, 28)
		edit_preset_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		edit_preset_btn.tooltip_text = "编辑预设"
	if del_pb != null and del_pb is Button:
		del_pb.text = ""
		del_pb.icon = _load_svg_icon(icon_base + "delete.svg", "ffffff", 0.7)
		del_pb.custom_minimum_size = Vector2(28, 28)
		del_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		del_pb.tooltip_text = "删除预设"
	
	# ─── 3. 输入框 → min 40 ───
	if api_input != null:
		api_input.custom_minimum_size = Vector2(40, 32)
		api_input.size_flags_horizontal = Control.SIZE_FILL
	if url_input != null:
		url_input.custom_minimum_size = Vector2(40, 32)
		url_input.size_flags_horizontal = Control.SIZE_FILL
	if model_input != null:
		model_input.custom_minimum_size = Vector2(40, 32)
		model_input.size_flags_horizontal = Control.SIZE_FILL
	if preset_name_input != null:
		preset_name_input.custom_minimum_size = Vector2(40, 32)
		preset_name_input.size_flags_horizontal = Control.SIZE_FILL
	if custom_prompt_input != null:
		custom_prompt_input.custom_minimum_size = Vector2(0, 100)
		custom_prompt_input.size_flags_horizontal = Control.SIZE_FILL
	
	# ─── 4. 清理 Settings 内所有 Label 的最小宽度 ───
	# ─── 5. 强制刷新统计按钮 SHRINK_BEGIN ───
	var stack: Array = [settings]
	var lbl_n := 0
	var btn_n := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is Label:
				n.custom_minimum_size = Vector2(0, 0)
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				lbl_n += 1
			elif n is Button:
				var txt: String = str(n.text).strip_edges()
				if txt == "刷新统计":
					n.custom_minimum_size = Vector2(72, 28)
					n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					n.clip_text = true
					n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					btn_n += 1
				elif txt == "完成编辑" or txt == "Done Editing":
					n.custom_minimum_size = Vector2(72, 28)
					n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					n.clip_text = true
					n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					btn_n += 1
		for c in n.get_children():
			stack.append(c)
	


func _v26_dump_top():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Control and c != settings:
				var cms = c.get_combined_minimum_size()
				if cms.x > 100:
					pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复28：纯诊断，从 Settings 开始逐层打印
# ═══════════════════════════════════════════════════════════════

func _v28_dump_tree():
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null:
		return
	
	
	# 深度优先，打印缩进
	var stack: Array = [[settings, 0]]
	while stack.size() > 0:
		var entry = stack.pop_back()
		var n: Node = entry[0]
		var depth: int = entry[1]
		
		if n is Control:
			var indent: String = "  ".repeat(depth)
			var cm: Vector2 = n.custom_minimum_size
			var ms: Vector2 = n.get_combined_minimum_size()
			var flags: int = n.size_flags_horizontal
			var cls: String = n.get_class()
			var nm: String = str(n.name)
		
		# 收集子节点（倒序推入，正序弹出）
		var children = n.get_children()
		for i in range(children.size() - 1, -1, -1):
			stack.append([children[i], depth + 1])
	



# ═══════════════════════════════════════════════════════════════
# 修复29：缩短 CheckBox 文本
# ═══════════════════════════════════════════════════════════════

func _v29_shorten_checkboxes():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var stack: Array = [settings]
	var n := 0
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			if c is CheckBox:
				# 缩短文本 + tooltip 保留完整
				var t: String = str(c.text)
				if t.begins_with("发送消息时附带当前时间"):
					c.text = "发送时附带当前时间"
					c.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
					n += 1
				elif t.begins_with("消息下方显示消耗"):
					c.text = "显示 Token 数"
					c.tooltip_text = "消息下方显示消耗 Token 数"
					n += 1
				elif t.begins_with("消息下方显示发送"):
					c.text = "显示收发时间"
					c.tooltip_text = "消息下方显示发送/接收时间"
					n += 1
				# 强制缩小字体 + 强制 shrink
				c.add_theme_font_size_override("font_size", 12)
				c.custom_minimum_size = Vector2(0, 0)
				c.clip_text = true
				c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			stack.append(c)
	


func _v29_dump():
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings == null: return
	var stack: Array = [settings]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			if c is CheckBox:
				pass
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复30：最终布局
# ═══════════════════════════════════════════════════════════════

func _v30_final():
	# ─── 1. 下拉框：EXPAND_FILL 自适应 ───
	if chat_preset_selector != null:
		chat_preset_selector.custom_minimum_size = Vector2(60, 0)
		chat_preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_preset_selector.clip_text = true
		chat_preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chat_preset_selector.fit_to_longest_item = false
	if preset_selector != null:
		preset_selector.custom_minimum_size = Vector2(60, 0)
		preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_selector.clip_text = true
		preset_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preset_selector.fit_to_longest_item = false
	if provider_selector != null:
		provider_selector.custom_minimum_size = Vector2(60, 0)
		provider_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		provider_selector.clip_text = true
		provider_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		provider_selector.fit_to_longest_item = false
	if language_selector != null:
		language_selector.custom_minimum_size = Vector2(60, 0)
		language_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		language_selector.clip_text = true
		language_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		language_selector.fit_to_longest_item = false
	
	# ─── 2. Settings 里所有文本控件应用省略号 ───
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is Label:
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			elif n is Button:
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			elif n is CheckBox:
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.custom_minimum_size = Vector2(0, 0)
			elif n is LineEdit:
				pass
		for c in n.get_children():
			stack.append(c)
	
	# ─── 3. 删除双重 MyExtrasRoot ───
	_v30_dedupe_extras_root(settings)


func _v30_dedupe_extras_root(settings: Control):
	# 找所有名字为 MyExtrasRoot 的节点
	var roots: Array = []
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if String(n.name) == "MyExtrasRoot":
			roots.append(n)
		for c in n.get_children():
			stack.append(c)
	
	if roots.size() <= 1:
		return
	
	# 保留第一个（在树里位置最靠上的），其余 queue_free
	# 先按路径排序（浅的优先）
	roots.sort_custom(func(a, b):
		return str(a.get_path()).length() < str(b.get_path()).length()
	)
	for i in range(1, roots.size()):
		if is_instance_valid(roots[i]):
			roots[i].queue_free()


func _v30_dedupe_extras_label(settings: Control):
	# 补充：找所有"附加内容" Label，保留第一个 VBox，删其余
	var extras_parents: Array = []
	var usage_parents: Array = []
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text).strip_edges()
				if t.begins_with("附加内容"):
					var p = c.get_parent()
					if p != null and not extras_parents.has(p):
						extras_parents.append(p)
				elif t.begins_with("用量统计"):
					var p2 = c.get_parent()
					if p2 != null and not usage_parents.has(p2):
						usage_parents.append(p2)
			stack.append(c)
	
	# 保留第一个，其余删
	if extras_parents.size() > 1:
		for i in range(1, extras_parents.size()):
			if is_instance_valid(extras_parents[i]):
				extras_parents[i].queue_free()
	if usage_parents.size() > 1:
		for i in range(1, usage_parents.size()):
			if is_instance_valid(usage_parents[i]):
				usage_parents[i].queue_free()


func _v30_trigger_dedupe():
	await get_tree().process_frame
	await get_tree().process_frame
	var settings = $TabContainer.get_node_or_null("Settings")
	if settings != null:
		_v30_dedupe_extras_root(settings)
		_v30_dedupe_extras_label(settings)



# ═══════════════════════════════════════════════════════════════
# 修复32
# ═══════════════════════════════════════════════════════════════

func _v32_fix_all():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var icon_base: String = "res://addons/gamedev_ai/assets/icons/"
	
	# ─── 1. 恢复标题文本 ───
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text).strip_edges()
				if t == "":
					# 看看周围有没有可识别的上下文
					var par = c.get_parent()
					if par != null:
						var pname: String = str(par.name)
						if "Usage" in pname or "usage" in pname:
							c.text = "用量统计"
						elif "Additional" in pname or "Extras" in pname:
							c.text = "附加内容"
			stack.append(c)
	
	# 专门找 MyExtrasRoot，恢复/确认标题
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras != null:
		# 遍历 extras 里的所有 Label，检查是否有"用量统计"和"附加内容"
		var has_extras_title := false
		var has_usage_title := false
		var usage_summary: Label = null
		var usage_refresh: Button = null
		var extras_labels: Array = []
		var stack2: Array = [extras]
		while stack2.size() > 0:
			var n2: Node = stack2.pop_back()
			if n2 is Label:
				extras_labels.append(n2)
				var tt: String = str(n2.text)
				if tt.begins_with("附加内容"):
					has_extras_title = true
				elif tt.begins_with("用量统计"):
					has_usage_title = true
				elif tt == "" or tt.begins_with("（"):
					# 可能是被误删的标题或摘要
					usage_summary = n2
			elif n2 is Button and str(n2.name) == "UsageRefreshBtn":
				usage_refresh = n2
			for c2 in n2.get_children():
				stack2.append(c2)
		
		# 找空的 Label，补成"用量统计"
		if not has_usage_title:
			# 找 title 名字的 Label
			for l in extras_labels:
				if str(l.name) == "UsageTitle":
					l.text = "用量统计"
					has_usage_title = true
					break
			# 如果没有名字匹配的，在 UsageSummary 之前插一个
			if not has_usage_title and usage_summary != null:
				var parent = usage_summary.get_parent()
				if parent is VBoxContainer:
					var idx: int = usage_summary.get_index()
					var new_lbl := Label.new()
					new_lbl.name = "UsageTitle"
					new_lbl.text = "用量统计"
					new_lbl.add_theme_font_size_override("font_size", 14)
					new_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
					parent.add_child(new_lbl)
					parent.move_child(new_lbl, idx)
		
		if not has_extras_title:
			for l in extras_labels:
				if str(l.name) == "ExtrasTitle":
					l.text = "附加内容"
					has_extras_title = true
					break
	
	# ─── 2. 预设三按钮：图标 + 32×32 ───
	var add_pb = find_child("AddPresetBtn", true, false)
	var del_pb = find_child("DelPresetBtn", true, false)
	if add_pb != null and add_pb is Button:
		add_pb.text = ""
		add_pb.icon = _load_svg_icon(icon_base + "plus.svg", "ffffff", 0.7)
		add_pb.custom_minimum_size = Vector2(32, 32)
		add_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_pb.tooltip_text = "添加预设"
	if edit_preset_btn != null:
		edit_preset_btn.text = ""
		edit_preset_btn.icon = _load_svg_icon(icon_base + "rename.svg", "ffffff", 0.7)
		edit_preset_btn.custom_minimum_size = Vector2(32, 32)
		edit_preset_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		edit_preset_btn.tooltip_text = "编辑预设"
	if del_pb != null and del_pb is Button:
		del_pb.text = ""
		del_pb.icon = _load_svg_icon(icon_base + "delete.svg", "ffffff", 0.7)
		del_pb.custom_minimum_size = Vector2(32, 32)
		del_pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		del_pb.tooltip_text = "删除预设"
	
	# ─── 3. 缩小 Settings 里所有撑宽的控件 ───
	var stack3: Array = [settings]
	while stack3.size() > 0:
		var n3: Node = stack3.pop_back()
		if n3 is Control and n3 != settings:
			if n3 is OptionButton:
				n3.custom_minimum_size = Vector2(50, 28)
				n3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n3.clip_text = true
				n3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n3.fit_to_longest_item = false
			elif n3 is LineEdit:
				n3.custom_minimum_size = Vector2(60, 28)
				n3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n3 is TextEdit:
				n3.custom_minimum_size = Vector2(0, 80)
				n3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n3 is CheckBox:
				# 缩短文本
				var cbt: String = str(n3.text)
				if cbt.begins_with("发送消息时"):
					n3.text = "附带时间"
					n3.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
				elif cbt.begins_with("消息下方显示消耗"):
					n3.text = "显示 Token 数"
					n3.tooltip_text = "消息下方显示消耗 Token 数"
				elif cbt.begins_with("消息下方显示发送"):
					n3.text = "显示收发时间"
					n3.tooltip_text = "消息下方显示发送/接收时间"
				n3.add_theme_font_size_override("font_size", 12)
				n3.custom_minimum_size = Vector2(0, 0)
				n3.clip_text = true
				n3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			elif n3 is Button:
				# 除预设三按钮外，其余按钮缩窄
				if n3 != add_pb and n3 != edit_preset_btn and n3 != del_pb:
					n3.custom_minimum_size = Vector2(60, 28)
					n3.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					n3.clip_text = true
					n3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			elif n3 is Label:
				n3.custom_minimum_size = Vector2(0, 0)
				n3.clip_text = true
				n3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for c3 in n3.get_children():
			stack3.append(c3)
	
	# ─── 4. 打印 top 5 撑宽控件 ───
	await get_tree().process_frame
	await get_tree().process_frame
	var items: Array = []
	var stack4: Array = [settings]
	while stack4.size() > 0:
		var n4: Node = stack4.pop_back()
		for c4 in n4.get_children():
			if c4 is Control and c4 != settings:
				var ms: Vector2 = c4.get_combined_minimum_size()
				if ms.x > 80:
					items.append({"name": str(c4.name), "cls": c4.get_class(), "ms": ms.x})
			stack4.append(c4)
	items.sort_custom(func(a, b): return a["ms"] > b["ms"])
	pass
	pass
	for k in range(min(5, items.size())):
		pass



# ═══════════════════════════════════════════════════════════════
# 修复33：三个 tab 页统一最小宽度 = 160
# ═══════════════════════════════════════════════════════════════

const _V33_MIN_WIDTH: float = 160.0

func _v33_set_tab_widths():
	await get_tree().process_frame
	await get_tree().process_frame
	
	var tc = $TabContainer
	if tc == null:
		return
	
	var target_x: float = _V33_MIN_WIDTH
	var tabs: Array = []
	for child in tc.get_children():
		if child is Control:
			tabs.append(child)
			child.custom_minimum_size = Vector2(target_x, child.custom_minimum_size.y)
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	pass
	for t in tabs:
		pass
	
	# 诊断：哪些子控件 still 撑宽
	var settings = tc.get_node_or_null("Settings")
	if settings != null:
		var items: Array = []
		var stack: Array = [settings]
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			for c in n.get_children():
				if c is Control and c != settings:
					var ms: Vector2 = c.get_combined_minimum_size()
					if ms.x > 100:
						items.append({"name": str(c.name), "cls": c.get_class(), "ms": ms.x})
				stack.append(c)
		items.sort_custom(func(a, b): return a["ms"] > b["ms"])
		pass
		for k in range(min(5, items.size())):
			pass



# ═══════════════════════════════════════════════════════════════
# 修复35：Tab 宽度 + 自动审批 + 备份 / 撤销系统
# ═══════════════════════════════════════════════════════════════

const BACKUP_DIR: String = "res://.gamedev_ai/backups"
const _V34_DEFAULT_WIDTH: float = 200.0
const _V34_WIDTH_RATIO: float = 0.8
const _V34_DESTRUCTIVE_TOOLS: Array = [
	"edit_script", "patch_script", "create_script",
	"remove_file", "replace_selection", "move_files_batch"
]

var _auto_approve: bool = false
var _v34_backups: Dictionary = {}


func _v34_gen_code() -> String:
	var chars: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code: String = ""
	for i in range(8):
		code += chars[randi() % chars.length()]
	return code


func _v34_set_tab_widths():
	await get_tree().process_frame
	await get_tree().process_frame
	
	var tc = $TabContainer
	if tc == null:
		return
	var target_w: float = _V34_DEFAULT_WIDTH * _V34_WIDTH_RATIO
	tc.custom_minimum_size = Vector2(target_w, 0)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tc is Control:
		tc.clip_contents = true
	
	for child in tc.get_children():
		if child is Control:
			child.custom_minimum_size = Vector2(target_w, 0)
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _v34_set_auto_approve(v: bool):
	_auto_approve = v
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("gamedev_ai/auto_approve", v)
	if has_method("_v39_auto_approve_toast"):
		_v39_auto_approve_toast(v)
	else:
		_show_toast("[color=green]自动审批： " + ("开启" if v else "关闭") + "[/color]")


func _v34_load_auto_approve():
	var settings = EditorInterface.get_editor_settings()
	if settings.has_setting("gamedev_ai/auto_approve"):
		_auto_approve = settings.get_setting("gamedev_ai/auto_approve")


func _v34_on_menu_id(id: int):
	if id == 100:
		_v34_set_auto_approve(not _auto_approve)
		var popup = prompt_settings_btn.get_popup()
		for i in range(popup.item_count):
			if popup.get_item_id(i) == 100:
				popup.set_item_checked(i, _auto_approve)
				break


func _v34_add_auto_approve_menu():
	if prompt_settings_btn == null:
		return
	var popup = prompt_settings_btn.get_popup()
	# 幂等：如果已经有"自动审批（危险）"就跳过
	for i in range(popup.item_count):
		if popup.get_item_text(i) == "自动审批（危险）":
			return
	popup.add_separator()
	popup.add_check_item("自动审批（危险）", 100)
	popup.set_item_checked(popup.item_count - 1, _auto_approve)
	popup.add_check_item("无限重试", 101)
	popup.set_item_checked(popup.item_count - 1, _infinite_retry)
	popup.add_check_item("完全自动化", 102)
	popup.set_item_checked(popup.item_count - 1, _full_auto)
func _v34_ensure_backup_dir():
	if not DirAccess.dir_exists_absolute(BACKUP_DIR):
		DirAccess.make_dir_recursive_absolute(BACKUP_DIR)


func _v34_clear_backups_on_startup():
	var dir = DirAccess.open(BACKUP_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			DirAccess.remove_absolute(BACKUP_DIR + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()


func _v34_backup_before_tool(tool_name: String, args: Dictionary, tool_id: String) -> String:
	if not (tool_name in _V34_DESTRUCTIVE_TOOLS):
		return ""
	var path: String = str(args.get("path", ""))
	if path == "" or not path.begins_with("res://"):
		return ""
	
	var action: String = "edit"
	if tool_name == "create_script":
		action = "create"
	elif tool_name == "remove_file":
		action = "delete"
	
	var original: String = ""
	var existed: bool = FileAccess.file_exists(path)
	if existed:
		var f = FileAccess.open(path, FileAccess.READ)
		if f != null:
			original = f.get_as_text()
			f.close()
	
	if not existed and action != "create":
		return ""
	
	var code: String = _v34_gen_code()
	_v34_ensure_backup_dir()
	
	_v34_backups[code] = {
		"tool_call_id": tool_id,
		"tool_name": tool_name,
		"path": path,
		"original": original,
		"existed": existed,
		"action": action,
		"time": Time.get_datetime_string_from_system()
	}
	
	var backup_file: String = BACKUP_DIR + "/" + tool_id + ".json"
	var bf = FileAccess.open(backup_file, FileAccess.WRITE)
	if bf != null:
		bf.store_string(JSON.stringify({
			"tool_call_id": tool_id,
			"undo_code": code,
			"tool_name": tool_name,
			"path": path,
			"original": original,
			"existed": existed,
			"action": action,
			"time": Time.get_datetime_string_from_system()
		}, "  "))
		bf.close()
	
	return code


func _v34_find_backup(tool_id: String, undo_code: String) -> Dictionary:
	if _v34_backups.has(undo_code):
		var b = _v34_backups[undo_code]
		if str(b.get("tool_call_id", "")) == tool_id:
			return b
	var f_path: String = BACKUP_DIR + "/" + tool_id + ".json"
	if not FileAccess.file_exists(f_path):
		return {}
	var f = FileAccess.open(f_path, FileAccess.READ)
	if f == null:
		return {}
	var txt = f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if data is Dictionary and str(data.get("undo_code", "")) == undo_code:
		return data
	return {}


func _v34_handle_undo(args: Dictionary) -> String:
	var tool_id: String = str(args.get("tool_call_id", ""))
	var code: String = str(args.get("undo_code", ""))
	if tool_id == "" or code == "":
		return "撤销失败：缺少 tool_call_id 或 undo_code"
	
	var b: Dictionary = _v34_find_backup(tool_id, code)
	if b.is_empty():
		return "撤销失败：未找到匹配的备份（tool_id=" + tool_id + " code=" + code + "）"
	
	var path: String = str(b.get("path", ""))
	var original: String = str(b.get("original", ""))
	var existed: bool = bool(b.get("existed", false))
	var action: String = str(b.get("action", "edit"))
	
	if action == "create":
		if FileAccess.file_exists(path):
			var err = DirAccess.remove_absolute(path)
			if err != OK:
				return "撤销失败：无法删除 " + path
		return "撤销成功：已删除工具 " + tool_id + " 创建的文件 " + path
	elif action == "delete":
		var wf = FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			return "撤销失败：无法写入 " + path
		wf.store_string(original)
		wf.close()
		return "撤销成功：已恢复工具 " + tool_id + " 删除的文件 " + path
	else:
		if not existed:
			return "撤销失败：编辑前文件不存在"
		var wf2 = FileAccess.open(path, FileAccess.WRITE)
		if wf2 == null:
			return "撤销失败：无法写入 " + path
		wf2.store_string(original)
		wf2.close()
		return "撤销成功：已恢复工具 " + tool_id + " 修改的文件 " + path


func _v34_init():
	_v34_set_tab_widths()
	_v34_clear_backups_on_startup()
	_v34_load_auto_approve()
	_v34_add_auto_approve_menu()



# ═══════════════════════════════════════════════════════════════
# 修复36：Settings 控件恢复 + tab 宽度
# ═══════════════════════════════════════════════════════════════

func _v36_restore_settings():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is LineEdit:
				n.custom_minimum_size = Vector2(80, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n is TextEdit:
				n.custom_minimum_size = Vector2(0, 120)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
			elif n is OptionButton:
				n.custom_minimum_size = Vector2(60, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is Label:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is Button:
				n.custom_minimum_size = Vector2(0, 28)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for c in n.get_children():
			stack.append(c)


func _v36_set_tab_widths():
	await get_tree().process_frame
	var tc = $TabContainer
	if tc == null:
		return
	var target_w: float = 200.0 * 0.8
	tc.custom_minimum_size = Vector2(target_w, 0)
	if tc is Control:
		tc.clip_contents = true
	for child in tc.get_children():
		if child is Control:
			child.custom_minimum_size = Vector2(target_w, 0)
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _v36_init():
	_v36_set_tab_widths()
	_v36_restore_settings()



# ═══════════════════════════════════════════════════════════════
# 修复38：Settings 控件自适应铺满
# ═══════════════════════════════════════════════════════════════

func _v38_fix_settings_layout():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is LineEdit:
				# 输入框：撑满父容器
				n.custom_minimum_size = Vector2(0, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
			elif n is TextEdit:
				# 多行输入框：撑满宽度，高度固定
				n.custom_minimum_size = Vector2(0, 120)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
				n.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			elif n is OptionButton:
				# 下拉框：撑满父容器
				n.custom_minimum_size = Vector2(0, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
			elif n is CheckBox:
				# 复选框：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is Label:
				# 标签：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is Button:
				# 按钮：按内容
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			elif n is PanelContainer or n is MarginContainer:
				# 容器：撑满父容器
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n is VBoxContainer:
				# 垂直容器：撑满宽度
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n is HBoxContainer:
				# 水平容器：撑满宽度
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n is GridContainer:
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n is ScrollContainer:
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for c in n.get_children():
			stack.append(c)
	
	# 二次遍历确保子容器内的控件
	await get_tree().process_frame
	var stack2: Array = [settings]
	while stack2.size() > 0:
		var n2: Node = stack2.pop_back()
		if n2 is Control and n2 != settings:
			if n2 is LineEdit or n2 is OptionButton:
				if n2.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
					n2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif n2 is TextEdit:
				n2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for c2 in n2.get_children():
			stack2.append(c2)



# ═══════════════════════════════════════════════════════════════
# 修复39：恢复文本 + 自适应 + 自动审批说明
# ═══════════════════════════════════════════════════════════════

func _v39_restore_texts():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	# 找 MyExtrasRoot
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras == null:
		return
	
	var stack: Array = [extras]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Label:
			var t: String = str(n.text).strip_edges()
			var nm: String = str(n.name)
			# 恢复标题
			if nm == "UsageTitle" and (t == "" or not t.begins_with("用量统计")):
				n.text = "用量统计"
				n.add_theme_font_size_override("font_size", 14)
				n.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
				n.clip_text = false
			elif nm == "ExtrasTitle" and (t == "" or not t.begins_with("附加内容")):
				n.text = "附加内容"
				n.add_theme_font_size_override("font_size", 14)
				n.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
				n.clip_text = false
			elif nm == "UsageSummaryV5":
				n.text = "（暂无数据）" if t == "" else t
			# 通用：任何 Label 显示为"…"或空且名字包含 Usage
			if "usage" in nm.to_lower() and (t == "" or t == "…"):
				n.text = "用量统计"
				n.clip_text = false
		elif n is CheckBox:
			# 恢复三个 CheckBox 的完整文本
			var ct: String = str(n.text).strip_edges()
			if ct == "" or ct == "附带时间":
				n.text = "发送时附带当前时间"
				n.tooltip_text = "发送消息时附带当前时间（将会降低缓存命中率）"
			elif ct == "显示 Token 数" or ct == "":
				n.text = "显示 Token 数"
				n.tooltip_text = "消息下方显示消耗 Token 数"
			elif ct == "显示收发时间" or ct == "":
				n.text = "显示收发时间"
				n.tooltip_text = "消息下方显示发送/接收时间"
			n.add_theme_font_size_override("font_size", 12)
			n.custom_minimum_size = Vector2(0, 0)
			n.size_flags_horizontal = Control.SIZE_FILL
			n.clip_text = false
		elif n is Button:
			var bt: String = str(n.text).strip_edges()
			var bn: String = str(n.name)
			if bn == "UsageRefreshBtn" or bt == "" or bt == "…":
				n.text = "刷新统计"
				n.tooltip_text = "重新读取用量记录并刷新显示"
				n.custom_minimum_size = Vector2(80, 28)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				n.clip_text = false
		for c in n.get_children():
			stack.append(c)


func _v39_fix_extras_sizes():
	# 附加内容里的控件恢复正常尺寸
	var settings = $TabContainer/Settings
	if settings == null: return
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras == null: return
	var stack: Array = [extras]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control:
			if n is Label:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is CheckBox:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_FILL
			elif n is Button:
				n.custom_minimum_size = Vector2(0, 0)
				n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			elif n is PanelContainer or n is VBoxContainer:
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for c in n.get_children():
			stack.append(c)


func _v39_fix_settings_layout():
	# Settings 内所有输入框和下拉框撑满
	var settings = $TabContainer/Settings
	if settings == null: return
	var stack: Array = [settings]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and n != settings:
			if n is LineEdit:
				n.custom_minimum_size = Vector2(0, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
			elif n is TextEdit:
				n.custom_minimum_size = Vector2(0, 120)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.size_flags_vertical = Control.SIZE_FILL
			elif n is OptionButton:
				n.custom_minimum_size = Vector2(0, 28)
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				n.clip_text = true
				n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				n.fit_to_longest_item = false
			elif n is PanelContainer or n is VBoxContainer \
				or n is HBoxContainer or n is GridContainer:
				if n.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN:
					n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for c in n.get_children():
			stack.append(c)


func _v39_auto_approve_toast(v: bool):
	if v:
		_show_toast("[color=orange]自动审批已开启[/color]\n[color=gray]所有工具调用（含删除/编辑/创建）将自动通过，无需确认[/color]")
	else:
		_show_toast("[color=green]自动审批已关闭[/color]\n[color=gray]危险操作会再次弹出确认框[/color]")


func _v39_init():
	_v39_restore_texts()
	_v39_fix_extras_sizes()
	_v39_fix_settings_layout()



# ═══════════════════════════════════════════════════════════════
# 修复40：token 显示 + 删除用量统计
# ═══════════════════════════════════════════════════════════════

var _v40_last_ai_wrapper: VBoxContainer = null


func _v40_track_ai_wrapper(wrapper: VBoxContainer, role: String):
	if role == "ai" or role == "system":
		_v40_last_ai_wrapper = wrapper


func _v40_on_token_usage(usage: Dictionary):
	var prompt_t: int = int(usage.get("prompt_tokens", 0))
	var completion_t: int = int(usage.get("completion_tokens", 0))
	var total_t: int = int(usage.get("total_tokens", 0))
	var cached_t: int = int(usage.get("cached_tokens", 0))
	
	# 保存到最新 AI wrapper 的 meta（无论开关，都保存）
	var wrapper = _v40_last_ai_wrapper
	if wrapper == null or not is_instance_valid(wrapper):
		return
	var footer = wrapper.get_meta("footer", null)
	if footer == null or not is_instance_valid(footer):
		return
	
	wrapper.set_meta("token_data", {
		"prompt": prompt_t,
		"completion": completion_t,
		"total": total_t,
		"cached": cached_t,
		"time": Time.get_datetime_string_from_system(false, true)
	})
	
	# 显示由开关控制
	if _show_token_enabled:
		var arrow: String = "↓"
		var cache_str: String = " (Cache " + str(cached_t) + ")" if cached_t > 0 else ""
		var txt: String = arrow + str(total_t) + cache_str
		if _show_recv_time_enabled:
			txt += "，" + Time.get_datetime_string_from_system(false, true)
		footer.text = txt
		footer.visible = true
	else:
		footer.visible = false


func _v40_remove_usage_section():
	var settings = $TabContainer/Settings
	if settings == null: return
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras == null: return
	
	# 找 "用量统计" Label 的 index，从该 Label 前一个节点（分隔线）开始删到末尾
	var children = extras.get_children()
	var start_idx: int = -1
	for i in range(children.size()):
		var c = children[i]
		if c is Label:
			var t: String = str(c.text).strip_edges()
			var nm: String = str(c.name)
			if t.begins_with("用量统计") or nm == "UsageTitle":
				start_idx = i
				break
	
	if start_idx == -1:
		return
	
	# 如果有前一个 HSeparator，也一起删
	if start_idx > 0 and children[start_idx - 1] is HSeparator:
		start_idx -= 1
	
	for i in range(children.size() - 1, start_idx - 1, -1):
		children[i].queue_free()
	pass



# ═══════════════════════════════════════════════════════════════
# 修复41
# ═══════════════════════════════════════════════════════════════

func _v41_remove_usage_aggressive():
	var settings = $TabContainer/Settings
	if settings == null: return
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras == null: return
	
	# 从 extras 里找所有含"用量统计"的 Label，全部标记
	var to_free: Array = []
	var stack: Array = [extras]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label:
				var t: String = str(c.text).strip_edges()
				var nm: String = str(c.name)
				if t.begins_with("用量统计") or nm == "UsageTitle":
					# 加整个父 VBox
					var p = c.get_parent()
					if p != null and is_instance_valid(p) and not to_free.has(p):
						to_free.append(p)
			stack.append(c)
	
	# 每个父 VBox 若是 MyExtrasRoot 的直接子节点，就删它
	for n in to_free:
		if is_instance_valid(n):
			# 如果 n == extras，那不能删整个；只删 n 里的相关部分
			if n == extras:
				# 从含"用量统计"Label 的位置开始删到末尾
				var children = extras.get_children()
				var idx := -1
				for i in range(children.size()):
					if children[i] is Label:
						var tt: String = str(children[i].text).strip_edges()
						var nn: String = str(children[i].name)
						if tt.begins_with("用量统计") or nn == "UsageTitle":
							idx = i
							break
				if idx >= 0:
					# 如果前一个是 HSeparator 也删
					if idx > 0 and children[idx - 1] is HSeparator:
						idx -= 1
					for i in range(children.size() - 1, idx - 1, -1):
						children[i].queue_free()
			else:
				n.queue_free()
	pass


func _v41_fix_extras_checkboxes():
	# 放大附加内容里的 CheckBox 文本
	var settings = $TabContainer/Settings
	if settings == null: return
	var extras = settings.find_child("MyExtrasRoot", true, false)
	if extras == null: return
	var stack: Array = [extras]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is CheckBox:
			n.add_theme_font_size_override("font_size", 14)
			n.add_theme_font_size_override("normal_font_size", 14)
			var ic = n.get_theme_icon("checked")
			if ic != null:
				pass
		for c in n.get_children():
			stack.append(c)


func _v41_init():
	await get_tree().process_frame
	await get_tree().process_frame
	_v41_remove_usage_aggressive()
	_v41_fix_extras_checkboxes()



# ═══════════════════════════════════════════════════════════════
# 修复42：强删用量统计
# ═══════════════════════════════════════════════════════════════

func _v42_kill_usage():
	var settings = $TabContainer/Settings
	if settings == null:
		return
	# 收集所有含"用量统计"文本的 Label（不论层级）
	var stack: Array = [settings]
	var labels: Array = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Label and str(c.text).strip_edges().begins_with("用量统计"):
				labels.append(c)
			stack.append(c)
	
	if labels.is_empty():
		return
	
	for lbl in labels:
		if not is_instance_valid(lbl):
			continue
		var par = lbl.get_parent()
		if par == null:
			continue
		var children = par.get_children()
		var idx: int = lbl.get_index()
		# 前面是 HSeparator 也一并删
		if idx > 0 and children[idx - 1] is HSeparator:
			idx -= 1
		# 从后往前删到末尾
		for i in range(children.size() - 1, idx - 1, -1):
			var c = children[i]
			if c == null or not is_instance_valid(c):
				continue
			par.remove_child(c)
			c.queue_free()



func _v43_init():
	# 强制 close_edit_btn 文本
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"
		close_edit_btn.custom_minimum_size = Vector2(96, 28)
		close_edit_btn.clip_text = false
	# 确保重新加载设置
	if has_method("_load_presets"):
		_load_presets()



# ═══════════════════════════════════════════════════════════════
# 修复45b：隐藏"当前选择"标签，不删代码
# ═══════════════════════════════════════════════════════════════

func _v45b_hide_selection():
	if selection_status == null:
		return
	if not is_instance_valid(selection_status):
		return
	selection_status.visible = false


func _v46_hide_selection():
	if selection_status == null:
		return
	if not is_instance_valid(selection_status):
		return
	selection_status.visible = false
	selection_status.modulate.a = 0.0



# ═══════════════════════════════════════════════════════════════
# 修复47：硬编码中文 UI 文本（不依赖 locale_manager）
# ═══════════════════════════════════════════════════════════════

func _v47_fix_chinese_ui():
	# 1. Tab 标题
	var tc = $TabContainer
	if tc != null and tc is TabContainer:
		if tc.get_tab_count() >= 1:
			tc.set_tab_title(0, "对话管理")
		if tc.get_tab_count() >= 2:
			tc.set_tab_title(1, "对话")
		if tc.get_tab_count() >= 3:
			tc.set_tab_title(2, "设置")
	
	# 2. 输入框 placeholder
	if input_field != null:
		input_field.placeholder_text = "在此输入消息…（Shift+Enter 发送）"
	
	# 3. 系统提示词标签
	var cust_lbl = find_child("CustomPromptLabel", true, false)
	if cust_lbl != null and cust_lbl is Label:
		cust_lbl.text = "系统提示词："
	
	# 4. 系统提示词输入框 placeholder
	if custom_prompt_input != null:
		custom_prompt_input.placeholder_text = "例如：总是用中文回答。专注于 2D 平台跳跃模式…"
	
	# 5. 语言标签
	var lang_lbl = find_child("LanguageLabel", true, false)
	if lang_lbl != null and lang_lbl is Label:
		lang_lbl.text = "语言："
	
	# 6. 预设标签
	var preset_lbl = find_child("PresetLabel", true, false)
	if preset_lbl != null and preset_lbl is Label:
		preset_lbl.text = "预设："
	
	# 7. 其他标签
	var name_lbl = find_child("NameLabel", true, false)
	if name_lbl != null and name_lbl is Label:
		name_lbl.text = "预设名称："
	var prov_lbl = find_child("ProviderLabel", true, false)
	if prov_lbl != null and prov_lbl is Label:
		prov_lbl.text = "供应商："
	var api_lbl = find_child("ApiLabel", true, false)
	if api_lbl != null and api_lbl is Label:
		api_lbl.text = "API 密钥："
	var model_lbl = find_child("ModelLabel", true, false)
	if model_lbl != null and model_lbl is Label:
		model_lbl.text = "模型名称："
	var url_lbl = find_child("UrlLabel", true, false)
	if url_lbl != null and url_lbl is Label:
		url_lbl.text = "基础 URL："
	
	# 8. 附加内容 / 用量统计标题
	var extras = find_child("MyExtrasRoot", true, false)
	if extras != null:
		for c in extras.get_children():
			if c is Label:
				var t: String = str(c.text)
				if t.begins_with("Additional") or t.begins_with("附加"):
					c.text = "附加内容"
				elif t.begins_with("Usage") or t.begins_with("用量"):
					c.text = "用量统计"
	
	# 9. 保存/编辑按钮
	if close_edit_btn != null:
		close_edit_btn.text = "完成编辑"

func _v51_hide_selection_forever():
	var real = get_node_or_null("SelectionStatus")
	# 从常见父容器查找
	if real == null:
		real = find_child("SelectionStatus", true, false)
	if real != null and is_instance_valid(real):
		var par = real.get_parent()
		if par != null:
			par.remove_child(real)
			real.queue_free()
	# 替换引用为假 Label（防止后续访问报错）
	var dummy := Label.new()
	dummy.name = "SelectionStatus_Dummy"
	dummy.visible = false
	dummy.modulate.a = 0.0
	dummy.custom_minimum_size = Vector2(0, 0)
	add_child(dummy)
	selection_status = dummy



# ═══════════════════════════════════════════════════════════════
# 修复52：无限重试 + 完全自动化
# ═══════════════════════════════════════════════════════════════

var _infinite_retry: bool = false
var _full_auto: bool = false


func _refresh_menu_checks():
	if prompt_settings_btn == null:
		return
	var popup = prompt_settings_btn.get_popup()
	for i in range(popup.item_count):
		var id: int = popup.get_item_id(i)
		if id == 100:
			popup.set_item_checked(i, _auto_approve)
		elif id == 101:
			popup.set_item_checked(i, _infinite_retry)
		elif id == 102:
			popup.set_item_checked(i, _full_auto)


func _v52_set_infinite_retry(v: bool):
	_infinite_retry = v
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("gamedev_ai/infinite_retry", v)
	if v:
		_show_toast("[color=orange]无限重试已开启[/color]\n[color=gray]请求失败后将每隔 5 秒无限重试，直到收到正常响应。收到正常响应立即停止[/color]")
	else:
		_show_toast("[color=green]无限重试已关闭[/color]\n[color=gray]恢复为最多 5 次递增重试（3/6/9/12/15 秒）[/color]")


func _v52_set_full_auto(v: bool):
	_full_auto = v
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("gamedev_ai/full_auto", v)
	if v:
		# 强制开启自动审批
		_auto_approve = true
		settings.set_setting("gamedev_ai/auto_approve", true)
		_show_toast("[color=orange]完全自动化已开启[/color]
[color=gray]强制开启自动审批；所有 AI 修改（含 Diff 预览）将自动应用[/color]")
	else:
		_show_toast("[color=green]完全自动化已关闭[/color]
[color=gray]恢复人工确认 Diff 预览；自动审批恢复可独立控制[/color]")
func _v52_load_switches():
	var settings = EditorInterface.get_editor_settings()
	if settings.has_setting("gamedev_ai/infinite_retry"):
		_infinite_retry = settings.get_setting("gamedev_ai/infinite_retry")
	if settings.has_setting("gamedev_ai/full_auto"):
		_full_auto = settings.get_setting("gamedev_ai/full_auto")
	# 完全自动化 → 强制开启自动审批
	if _full_auto:
		_auto_approve = true


func _v52_init():
	_v52_load_switches()
	_refresh_menu_checks()



# ═══════════════════════════════════════════════════════════════
# 修复53：无限重试 Token 化 + 完全自动化强制审批
# ═══════════════════════════════════════════════════════════════

var _v53_retry_timer: Timer = null


func _v53_ensure_retry_timer():
	if _v53_retry_timer != null and is_instance_valid(_v53_retry_timer):
		return
	_v53_retry_timer = Timer.new()
	_v53_retry_timer.name = "V53RetryTimer"
	_v53_retry_timer.one_shot = true
	_v53_retry_timer.wait_time = 5.0
	_v53_retry_timer.timeout.connect(_v58_on_retry_timeout)
	add_child(_v53_retry_timer)


func _v53_start_infinite_retry_timer():
	_v53_ensure_retry_timer()
	if _v53_retry_timer.is_stopped():
		_v53_retry_timer.start()


func _v53_on_retry_timeout():
	if _is_stopped:
		_v53_stop_all_retries()
		return
	if not _infinite_retry:
		_v53_stop_all_retries()
		return
	if gemini_client and not _last_send_payload.is_empty():
		_update_ui_state(true)
		var tools = _get_filtered_tools()
		gemini_client.send_prompt(_last_send_payload["final_prompt"], _last_send_payload["context"], tools, [])
		_set_tool_progress("💭 接收响应中…")
	else:
		_v53_stop_all_retries()


func _v53_is_in_retry_loop() -> bool:
	if _v53_retry_timer == null:
		return false
	if not is_instance_valid(_v53_retry_timer):
		return false
	return not _v53_retry_timer.is_stopped()


func _v53_stop_all_retries():
	if _v53_retry_timer != null and is_instance_valid(_v53_retry_timer):
		if not _v53_retry_timer.is_stopped():
			_v53_retry_timer.stop()
	_is_retrying = false
	_retry_count = 0
	_is_stopped = true
	_last_send_payload = {}
	_clear_tool_progress()



# ═══════════════════════════════════════════════════════════════
# 修复54/55：Response 前缀工具
# ═══════════════════════════════════════════════════════════════

func _v54_strip_response_prefix_from_bb(text: String) -> String:
	var t: String = text
	for _i in range(6):
		var before: String = t
		t = t.strip_edges()
		var low: String = t.to_lower()
		if low.begins_with("[b]response:[/b]"):
			t = t.substr(16)
		elif low.begins_with("[b]response[/b]:"):
			t = t.substr(16)
		elif low.begins_with("**response:**"):
			t = t.substr(13)
		elif low.begins_with("**response**:"):
			t = t.substr(13)
		elif low.begins_with("response:"):
			t = t.substr(9)
		elif low.begins_with("response："):
			t = t.substr(9)
		else:
			break
		if t == before:
			break
	return t.strip_edges()



# ═══════════════════════════════════════════════════════════════
# 修复57：上下文总结 + 滚动优化
# ═══════════════════════════════════════════════════════════════



func _v57_add_summary_button():
	var header = $TabContainer/Chat.get_node_or_null("ChatHeaderHBox")
	if header == null:
		return
	if header.get_node_or_null("SummaryContextBtn") != null:
		return
	var btn := Button.new()
	btn.name = "SummaryContextBtn"
	btn.flat = false
	btn.custom_minimum_size = Vector2(40, 32)
	btn.icon = _load_svg_icon("res://addons/gamedev_ai/assets/icons/compress.svg", "ffffff", 0.75)
	btn.tooltip_text = "总结对话（压缩上下文）"
	btn.pressed.connect(_v57_generate_summary)
	header.add_child(btn)
	pass


func _v57_generate_summary():
	if _v57_is_generating_summary:
		_show_toast("[color=yellow]正在总结中…[/color]")
		return
	
	var conversation: String = ""
	for c in chat_vbox.get_children():
		if not c.has_meta("role"):
			continue
		var role: String = str(c.get_meta("role"))
		if role == "summary":
			continue
		var lbl = c.get_meta("label", null)
		if not is_instance_valid(lbl):
			continue
		var txt: String = lbl.get_parsed_text()
		if txt.strip_edges() == "":
			continue
		conversation += ("用户：" if role == "user" else "AI：") + txt + "\n\n"
	
	if conversation.strip_edges() == "":
		_show_toast("[color=yellow]没有可总结的内容[/color]")
		return
	
	var preset = presets.get(active_preset_name, {})
	var provider = int(preset.get("provider", 0))
	var api_key = str(preset.get("api_key", ""))
	var base_url = str(preset.get("base_url", ""))
	var model = str(preset.get("model_name", ""))
	
	var summary_prompt = "你是一个对话总结助手。请将以下对话总结为简明摘要，保留关键信息：\n- 用户的主要目标\n- 已完成事项\n- 重要决策\n- 待办事项\n只输出摘要内容，不要任何前缀说明。\n\n=== 对话内容 ===\n" + conversation
	
	_v57_is_generating_summary = true
	_show_toast("[color=cyan]正在生成对话总结…[/color]")
	
	if _v57_summary_http == null:
		_v57_summary_http = HTTPRequest.new()
		_v57_summary_http.use_threads = true
		_v57_summary_http.timeout = 360.0
		add_child(_v57_summary_http)
		_v57_summary_http.request_completed.connect(_v57_on_summary_response)
	
	var url := ""
	var headers := ["Content-Type: application/json"]
	var body := ""
	
	if provider == 0:
		var m: String = model if model != "" else "gemini-1.5-pro"
		if base_url != "":
			url = base_url.rstrip("/") + "/v1beta/models/" + m + ":generateContent"
		else:
			url = "http://127.0.0.1:8000/v1beta/models/" + m + ":generateContent"
		body = JSON.stringify({"contents": [{"role": "user", "parts": [{"text": summary_prompt}]}]})
	else:
		var m2: String = model if model != "" else "gpt-4o"
		if base_url != "":
			url = base_url.rstrip("/") + "/v1/chat/completions"
		else:
			url = "https://api.openai.com/v1/chat/completions"
		if api_key != "":
			headers.append("Authorization: Bearer " + api_key)
		body = JSON.stringify({"model": m2, "messages": [{"role": "user", "content": summary_prompt}]})
	
	var err = _v57_summary_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_v57_is_generating_summary = false
		_show_toast("[color=red]总结请求失败：" + str(err) + "[/color]")


func _v57_on_summary_response(_result, code, _headers, body):
	_v57_is_generating_summary = false
	if code != 200:
		_show_toast("[color=red]总结失败（" + str(code) + "）[/color]")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	var text := ""
	if json and json.has("candidates"):
		var parts = json["candidates"][0].get("content", {}).get("parts", [])
		for part in parts:
			if part.has("text"):
				text += part["text"]
	elif json and json.has("choices"):
		text = json["choices"][0].get("message", {}).get("content", "")
	if text.strip_edges() == "":
		_show_toast("[color=red]总结内容为空[/color]")
		return
	_v61_render_summary(text.strip_edges())
	_show_toast("[color=green]对话总结已生成[/color]")


func _on_token_usage(usage: Dictionary):
	if not gemini_client:
		return
	var prompt_t: int = int(usage.get("prompt_tokens", 0))
	var completion_t: int = int(usage.get("completion_tokens", 0))
	var total_t: int = int(usage.get("total_tokens", 0))
	var cached_t: int = int(usage.get("cached_tokens", 0))
	
	var wrapper: VBoxContainer = null
	var children = chat_vbox.get_children()
	for i in range(children.size() - 1, -1, -1):
		if children[i].has_meta("footer"):
			wrapper = children[i]
			break
	if wrapper == null:
		return
	var footer = wrapper.get_meta("footer", null)
	if footer == null or not is_instance_valid(footer):
		return
	
	wrapper.set_meta("token_data", {
		"prompt": prompt_t,
		"completion": completion_t,
		"total": total_t,
		"cached": cached_t,
		"time": Time.get_datetime_string_from_system(false, true)
	})
	wrapper.set_meta("updated_at", wrapper.get_meta("token_data")["time"])
	
	if _show_token_enabled:
		var cache_str: String = " (Cache " + str(cached_t) + ")" if cached_t > 0 else ""
		var txt: String = "↑" + str(prompt_t) + " ↓" + str(completion_t) + cache_str
		if _show_recv_time_enabled:
			txt += "，" + str(wrapper.get_meta("token_data")["time"])
		footer.text = txt
		footer.visible = true
	elif _show_time_enabled:
		footer.text = str(wrapper.get_meta("updated_at"))
		footer.visible = true


func _v40_refresh_all_footers():
	var stack: Array = [chat_vbox]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.has_meta("token_data"):
			var footer = n.get_meta("footer", null)
			if footer != null and is_instance_valid(footer):
				if _show_token_enabled:
					var td: Dictionary = n.get_meta("token_data", {})
					var cache_str: String = " (Cache " + str(int(td.get("cached", 0))) + ")" if int(td.get("cached", 0)) > 0 else ""
					var txt: String = "↑" + str(int(td.get("prompt", 0))) + " ↓" + str(int(td.get("completion", 0))) + cache_str
					if _show_recv_time_enabled:
						txt += "，" + str(td.get("time", ""))
					footer.text = txt
					footer.visible = true
				elif _show_time_enabled:
					footer.text = str(n.get_meta("updated_at", ""))
					footer.visible = true
				else:
					footer.visible = false
		for c in n.get_children():
			stack.append(c)



# ═══════════════════════════════════════════════════════════════
# 修复60：补全 v58 系列函数
# ═══════════════════════════════════════════════════════════════

var _v57_summary_http: HTTPRequest = null
var _v57_is_generating_summary: bool = false
var _v57_retry_display_count: int = 0


func _v58_generate_summary(target_bubble):
	var conversation: String = ""
	for c in chat_vbox.get_children():
		if c == target_bubble:
			break
		if c.has_meta("is_summary"):
			continue
		if not c.has_meta("role"):
			continue
		var role: String = str(c.get_meta("role"))
		if role == "summary":
			continue
		var lbl = c.get_meta("label", null)
		if not is_instance_valid(lbl):
			continue
		var txt: String = lbl.get_parsed_text()
		if txt.strip_edges() == "":
			continue
		conversation += ("用户：" if role == "user" else "AI：") + txt + "\n\n"
	
	if conversation.strip_edges() == "":
		_show_toast("[color=yellow]没有可总结的内容[/color]")
		return
	
	if _v57_is_generating_summary:
		_show_toast("[color=yellow]正在总结中…[/color]")
		return
	
	var preset = presets.get(active_preset_name, {})
	var provider = int(preset.get("provider", 0))
	var api_key = str(preset.get("api_key", ""))
	var base_url = str(preset.get("base_url", ""))
	var model = str(preset.get("model_name", ""))
	
	var summary_prompt = "你是一个对话总结助手。请将以下对话总结为简明摘要，保留关键信息：\n- 用户的主要目标\n- 已完成事项\n- 重要决策\n- 待办事项\n只输出摘要内容，不要任何前缀说明。\n\n=== 对话内容 ===\n" + conversation
	
	_v57_is_generating_summary = true
	_show_toast("[color=cyan]正在生成对话总结…[/color]")
	
	if _v57_summary_http == null:
		_v57_summary_http = HTTPRequest.new()
		_v57_summary_http.use_threads = true
		_v57_summary_http.timeout = 360.0
		add_child(_v57_summary_http)
		_v57_summary_http.request_completed.connect(_v58_on_summary_response)
	
	var url := ""
	var headers := ["Content-Type: application/json"]
	var body := ""
	
	if provider == 0:
		var m: String = model if model != "" else "gemini-2.0-flash"
		if base_url != "":
			url = base_url.rstrip("/") + "/v1beta/models/" + m + ":generateContent"
		else:
			url = "https://generativelanguage.googleapis.com/v1beta/models/" + m + ":generateContent"
		if api_key != "":
			if "?" in url:
				url += "&key=" + api_key
			else:
				url += "?key=" + api_key
		body = JSON.stringify({"contents": [{"role": "user", "parts": [{"text": summary_prompt}]}]})
	else:
		var m2: String = model if model != "" else "gpt-4o-mini"
		if base_url != "":
			url = base_url.rstrip("/") + "/v1/chat/completions"
		else:
			url = "https://api.openai.com/v1/chat/completions"
		if api_key != "":
			headers.append("Authorization: Bearer " + api_key)
		body = JSON.stringify({"model": m2, "messages": [{"role": "user", "content": summary_prompt}]})
	
	var err = _v57_summary_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_v57_is_generating_summary = false
		_show_toast("[color=red]总结请求失败：" + str(err) + "[/color]")


func _v58_on_summary_response(_result, code, _headers, body):
	_v57_is_generating_summary = false
	if code != 200:
		_show_toast("[color=red]总结失败（HTTP " + str(code) + "）[/color]")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	var text := ""
	if json and json.has("candidates"):
		var parts = json["candidates"][0].get("content", {}).get("parts", [])
		for part in parts:
			if part.has("text"):
				text += part["text"]
	elif json and json.has("choices"):
		text = json["choices"][0].get("message", {}).get("content", "")
	if text.strip_edges() == "":
		_show_toast("[color=red]总结内容为空[/color]")
		return
	_v61_render_summary(text.strip_edges())
	_show_toast("[color=green]对话总结已生成[/color]")


func _v57_show_summary_dialog(divider):
	var old = get_node_or_null("__SummaryDialog")
	if old != null:
		old.queue_free()
	
	var panel := PanelContainer.new()
	panel.name = "__SummaryDialog"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(640, 520)
	
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	st.border_color = Color(0.35, 0.55, 0.95, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", st)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var ttl := Label.new()
	ttl.text = "对话总结"
	ttl.add_theme_font_size_override("font_size", 14)
	vb.add_child(ttl)
	
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(600, 400)
	te.text = str(divider.get_meta("summary_text", ""))
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(te)
	
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 6)
	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(72, 32)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(72, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(72, 32)
	hb.add_child(del_btn)
	hb.add_child(cancel_btn)
	hb.add_child(save_btn)
	vb.add_child(hb)
	panel.add_child(vb)
	add_child(panel)
	
	var vp = get_viewport()
	var vps: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2((vps.x - panel.size.x) * 0.5, (vps.y - panel.size.y) * 0.5)
	
	save_btn.pressed.connect(func():
		var new_text: String = te.text.strip_edges()
		if new_text == "":
			_show_toast("[color=red]总结内容不能为空[/color]")
			return
		divider.set_meta("summary_text", new_text)
		var lbl = divider.get_meta("label", null)
		if is_instance_valid(lbl):
			lbl.text = new_text
		_show_toast("[color=green]总结已保存[/color]")
		panel.queue_free()
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
	del_btn.pressed.connect(func():
		if is_instance_valid(divider):
			divider.queue_free()
		_show_toast("[color=orange]对话总结已删除[/color]")
		panel.queue_free()
	)


func _v58_schedule_infinite_retry(wait_s: float):
	_v53_ensure_retry_timer()
	if _v53_retry_timer == null:
		return
	_v53_retry_timer.wait_time = wait_s
	_v53_retry_timer.start()


func _v58_on_retry_timeout():
	if _is_stopped:
		_v53_stop_all_retries()
		return
	if not _infinite_retry:
		_v53_stop_all_retries()
		return
	if gemini_client and not _last_send_payload.is_empty():
		_update_ui_state(true)
		var tools = _get_filtered_tools()
		gemini_client.send_prompt(_last_send_payload["final_prompt"], _last_send_payload["context"], tools, [])
		_set_tool_progress("💭 接收响应中…（重试第 " + str(_v57_retry_display_count) + " 次）")
	else:
		_v53_stop_all_retries()


func _v58_get_next_api_key(preset: Dictionary) -> String:
	var keys: Array = preset.get("api_keys", [])
	var idx: int = int(preset.get("api_key_index", 0))
	if keys.is_empty():
		return str(preset.get("api_key", ""))
	if idx < 0 or idx >= keys.size():
		idx = 0
	var key: String = str(keys[idx])
	idx = (idx + 1) % keys.size()
	preset["api_key_index"] = idx
	return key


func _v58_add_key_row(parent: VBoxContainer, initial_value: String, removable: bool):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var le := LineEdit.new()
	le.text = initial_value
	le.secret = true
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(28, 28)
	if removable:
		btn.text = "-"
		btn.tooltip_text = "删除此密钥"
		btn.pressed.connect(func(): row.queue_free())
	else:
		btn.text = "+"
		btn.tooltip_text = "新增一个密钥"
		btn.pressed.connect(func():
			_v58_add_key_row(parent, "", true)
		)
	row.add_child(btn)
	parent.add_child(row)


func _v58_startup_tips():
	print_rich("""
[color=cyan]💡 [b]提示[/b][/color]
如需展开折叠的标签（如思考过程 / 工具调用 / 结果）：
  1. 鼠标滑过标签外显内容，拖动选中整段文字
  2. 点击被选中的部分，即可触发展开/折叠
  若点击无效，请尝试选中后再单击一次。
""")


func _v57_init():
	pass



# ═══════════════════════════════════════════════════════════════
# 修复61：总结对话（用当前 preset 配置）
# ═══════════════════════════════════════════════════════════════



func _v61_refresh_menu_checks():
	if prompt_settings_btn == null:
		return
	var popup = prompt_settings_btn.get_popup()
	for i in range(popup.item_count):
		var id: int = popup.get_item_id(i)
		if id == 100:
			popup.set_item_checked(i, _auto_approve)
		elif id == 101:
			popup.set_item_checked(i, _infinite_retry)
		elif id == 102:
			popup.set_item_checked(i, _full_auto)



# ═══════════════════════════════════════════════════════════════
# 修复61：多密钥 UI
# ═══════════════════════════════════════════════════════════════



# ═══════════════════════════════════════════════════════════════
# 修复63：多密钥 UI（独立区块）
# ═══════════════════════════════════════════════════════════════

var _v61_key_rows: Array = []
var _v61_key_container: VBoxContainer = null


func _v61_setup_multikey_ui():
	if api_input == null:
		return
	var grid = api_input.get_parent()
	if grid == null:
		return
	if grid.get_node_or_null("__V63KeySection") != null or \
		(grid.get_parent() != null and grid.get_parent().get_node_or_null("__V63KeySection") != null):
		return
	
	# ─── 1. api_input 换成 HBox（input + 加号）───
	var api_row = HBoxContainer.new()
	api_row.name = "__V61FirstKeyRow"
	api_row.add_theme_constant_override("separation", 4)
	api_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var idx_in_grid: int = api_input.get_index()
	grid.remove_child(api_input)
	api_row.add_child(api_input)
	api_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var add_btn := Button.new()
	add_btn.name = "__V61AddBtn"
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(28, 28)
	add_btn.tooltip_text = "新增一个密钥"
	add_btn.pressed.connect(func(): _v61_add_key_row(""))
	api_row.add_child(add_btn)
	
	grid.add_child(api_row)
	grid.move_child(api_row, idx_in_grid)
	
	# ─── 2. 额外密钥区块放在 GridContainer 之后 ───
	var outer = grid.get_parent()
	if outer == null:
		return
	
	var key_section := VBoxContainer.new()
	key_section.name = "__V63KeySection"
	key_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_section.add_theme_constant_override("separation", 4)
	
	var header := Label.new()
	header.text = "其他密钥（自动轮询，报错切换）："
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	key_section.add_child(header)
	
	var key_list := VBoxContainer.new()
	key_list.name = "__V61KeyList"
	key_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_list.add_theme_constant_override("separation", 4)
	key_section.add_child(key_list)
	_v61_key_container = key_list
	
	outer.add_child(key_section)
	var grid_idx: int = grid.get_index()
	outer.move_child(key_section, grid_idx + 1)


func _v61_add_key_row(initial_value: String):
	if _v61_key_container == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var le := LineEdit.new()
	le.text = initial_value
	le.secret = true
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(_t): _on_config_changed(""))
	row.add_child(le)
	var btn := Button.new()
	btn.text = "-"
	btn.custom_minimum_size = Vector2(28, 28)
	btn.tooltip_text = "删除此密钥"
	var row_ref = row
	btn.pressed.connect(func():
		_v61_key_rows.erase(row_ref)
		row_ref.queue_free()
		_on_config_changed("")
	)
	row.add_child(btn)
	_v61_key_container.add_child(row)
	_v61_key_rows.append(row)


func _v61_collect_all_keys() -> Array:
	var keys: Array = []
	if api_input != null:
		var first: String = api_input.text.strip_edges()
		if first != "":
			keys.append(first)
	for row in _v61_key_rows:
		if is_instance_valid(row):
			var le = row.get_child(0)
			if le is LineEdit:
				var v: String = le.text.strip_edges()
				if v != "":
					keys.append(v)
	return keys


func _v61_load_keys_to_ui(keys: Array):
	for row in _v61_key_rows:
		if is_instance_valid(row):
			row.queue_free()
	_v61_key_rows.clear()
	if api_input != null:
		api_input.text = str(keys[0]) if keys.size() > 0 else ""
	for i in range(1, keys.size()):
		_v61_add_key_row(str(keys[i]))


func _v61_on_preset_selected_hook(index: int):
	var config: Dictionary = presets.get(active_preset_name, {})
	var keys: Array = config.get("api_keys", [])
	if keys.is_empty():
		var single: String = str(config.get("api_key", ""))
		keys = [single] if single != "" else [""]
	_v61_load_keys_to_ui(keys)


func _v61_on_config_save_hook():
	if active_preset_name == "" or not presets.has(active_preset_name):
		return
	var keys: Array = _v61_collect_all_keys()
	presets[active_preset_name]["api_keys"] = keys
	if keys.size() > 0:
		presets[active_preset_name]["api_key"] = keys[0]


# ═══════════════════════════════════════════════════════════════
# 总结 history（按 provider 生成不同格式）
# ═══════════════════════════════════════════════════════════════



# ═══════════════════════════════════════════════════════════════
# 修复64：总结（系统提示词）+ 文件命名 + 加载 + 进度
# ═══════════════════════════════════════════════════════════════

var _v61_summary_http: HTTPRequest = null
var _v61_is_generating_summary: bool = false
var _v61_retry_display_count: int = 0
var _v64_summary_progress: String = ""


# ─── 文件名：用"对话 {title}.json" ───
func _v66_get_session_file_id() -> String:
	if _session_file_id != "":
		return _session_file_id
	if gemini_client:
		for key in ["session_id", "current_session_id", "session_uuid"]:
			if key in gemini_client:
				var v = gemini_client.get(key)
				if v != null and str(v) != "":
					var s := str(v)
					# 若是时间戳格式（全数字_下划线），重新生成
					if s.find("_") == -1 or not s.split("_")[0].is_valid_int():
						_session_file_id = s
						return _session_file_id
	var title: String = ""
	for child in chat_vbox.get_children():
		if child.has_meta("role") and str(child.get_meta("role")) == "user":
			var lbl = child.get_meta("label", null)
			if is_instance_valid(lbl):
				title = lbl.get_parsed_text().strip_edges()
				if title != "":
					break
	if title == "":
		title = "新对话"
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\t"]:
		title = title.replace(ch, "_")
	if title.length() > 20:
		title = title.substr(0, 20)
	var base_name: String = "对话 " + title
	var final_name: String = base_name
	var counter: int = 1
	while FileAccess.file_exists(HISTORY_DIR + "/" + final_name + ".json"):
		counter += 1
		final_name = base_name + "_" + str(counter)
		if counter > 999:
			break
	_session_file_id = final_name
	return _session_file_id


# ─── 加载对话 ───
func _v66_rebuild_chat_from_transcript():
	_clear_chat()
	_pending_history_entries.clear()
	if _load_more_btn and is_instance_valid(_load_more_btn):
		_load_more_btn.queue_free()
		_load_more_btn = null
	if gemini_client == null or not ("transcript" in gemini_client):
		return
	var all_entries = gemini_client.transcript
	if not (all_entries is Array) or all_entries.is_empty():
		return
	var last_summary_idx: int = -1
	for i in range(all_entries.size() - 1, -1, -1):
		var e = all_entries[i]
		if e is Dictionary and str(e.get("role", "")) == "summary":
			last_summary_idx = i
			break
	var to_render: Array = []
	if last_summary_idx >= 0:
		to_render = all_entries.slice(last_summary_idx)
		_pending_history_entries = all_entries.slice(0, last_summary_idx)
		if not _pending_history_entries.is_empty():
			_v66_add_load_more_button()
	else:
		if all_entries.size() > 5:
			_pending_history_entries = all_entries.slice(0, all_entries.size() - 5)
			to_render = all_entries.slice(all_entries.size() - 5)
			_v66_add_load_more_button()
		else:
			to_render = all_entries
	for entry in to_render:
		_v66_render_msg(entry)


func _v61_show_summary_dialog(divider):
	var old = get_node_or_null("__SummaryDialog")
	if old != null:
		old.queue_free()
	var panel := PanelContainer.new()
	panel.name = "__SummaryDialog"
	panel.top_level = true
	panel.z_index = 300
	panel.size = Vector2(640, 520)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.11, 0.12, 0.16, 0.99)
	st.border_color = Color(0.35, 0.55, 0.95, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var ttl := Label.new()
	ttl.text = "对话总结"
	ttl.add_theme_font_size_override("font_size", 14)
	vb.add_child(ttl)
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(600, 400)
	te.text = str(divider.get_meta("summary_text", ""))
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(te)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 6)
	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(72, 32)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(72, 32)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(72, 32)
	hb.add_child(del_btn)
	hb.add_child(cancel_btn)
	hb.add_child(save_btn)
	vb.add_child(hb)
	panel.add_child(vb)
	add_child(panel)
	var vp = get_viewport()
	var vps: Vector2 = vp.get_visible_rect().size if vp else Vector2(800, 600)
	panel.global_position = Vector2((vps.x - panel.size.x) * 0.5, (vps.y - panel.size.y) * 0.5)
	save_btn.pressed.connect(func():
		var new_text: String = te.text.strip_edges()
		if new_text == "":
			_show_toast("[color=red]总结内容不能为空[/color]")
			return
		divider.set_meta("summary_text", new_text)
		var lbl = divider.get_meta("label", null)
		if is_instance_valid(lbl):
			lbl.text = new_text
		_show_toast("[color=green]总结已保存[/color]")
		panel.queue_free()
	)
	cancel_btn.pressed.connect(func(): panel.queue_free())
	del_btn.pressed.connect(func():
		if is_instance_valid(divider):
			divider.queue_free()
		_show_toast("[color=orange]对话总结已删除[/color]")
		panel.queue_free()
	)


# ─── 总结 = 发送系统提示词 ───
func _v61_get_summary_text() -> String:
	var result: String = ""
	for c in chat_vbox.get_children():
		if c.has_meta("is_summary") and bool(c.get_meta("is_summary")):
			result = str(c.get_meta("summary_text", ""))
	return result


func _v61_has_summary() -> bool:
	for c in chat_vbox.get_children():
		if c.has_meta("is_summary") and bool(c.get_meta("is_summary")):
			return true
	return false


func _v61_apply_summary_history():
	if not gemini_client or not ("history" in gemini_client):
		return
	var children = chat_vbox.get_children()
	var last_idx: int = children.size() - 1
	if last_idx >= 0 and children[last_idx].has_meta("is_summary"):
		last_idx = -1
	var provider_index: int = 0
	var preset = presets.get(active_preset_name, {})
	if preset is Dictionary:
		provider_index = int(preset.get("provider", 0))
	var is_openai: bool = (provider_index != 0)
	var new_hist: Array = []
	for i in range(children.size()):
		if i == last_idx:
			break
		var c = children[i]
		if c.has_meta("is_summary") and bool(c.get_meta("is_summary")):
			new_hist.clear()
			continue
		if not c.has_meta("role"):
			continue
		var role: String = str(c.get_meta("role"))
		if role == "summary":
			continue
		var lbl = c.get_meta("label", null)
		if not is_instance_valid(lbl):
			continue
		var txt: String = lbl.get_parsed_text()
		if txt.strip_edges() == "":
			continue
		new_hist.append(_v61_build_hist_entry(role, txt, is_openai))
	gemini_client.set("history", new_hist)
	# 再强制把 summary 插到开头
	_v69_force_summary_into_history()


func _v61_build_hist_entry(role: String, text: String, is_openai: bool) -> Dictionary:
	if is_openai:
		var r2: String = role
		if r2 == "model":
			r2 = "assistant"
		return {"role": r2, "content": text}
	else:
		var r3: String = role
		if r3 == "assistant":
			r3 = "model"
		return {"role": r3, "parts": [{"text": text}]}


# ─── 生成总结（进度 + 可取消）───
func _v61_generate_summary(target_bubble):
	if _v61_is_generating_summary:
		_show_toast("[color=yellow]正在总结中，请勿重复点击[/color]")
		return
	var conversation: String = ""
	for c in chat_vbox.get_children():
		if c == target_bubble:
			break
		if c.has_meta("is_summary"):
			continue
		if not c.has_meta("role"):
			continue
		var role: String = str(c.get_meta("role"))
		if role == "summary":
			continue
		var lbl = c.get_meta("label", null)
		if not is_instance_valid(lbl):
			continue
		var txt: String = lbl.get_parsed_text()
		if txt.strip_edges() == "":
			continue
		conversation += ("用户：" if role == "user" else "AI：") + txt + "\n\n"
	if conversation.strip_edges() == "":
		_show_toast("[color=yellow]没有可总结的内容[/color]")
		return
	var preset: Dictionary = presets.get(active_preset_name, {})
	if preset.is_empty():
		_show_toast("[color=red]未选择预设[/color]")
		return
	var provider: int = int(preset.get("provider", 0))
	var base_url: String = str(preset.get("base_url", ""))
	var model: String = str(preset.get("model_name", ""))
	var api_key: String = _v58_get_next_api_key(preset)
	if api_key == "":
		api_key = str(preset.get("api_key", ""))
	presets[active_preset_name] = preset
	_save_presets()
	var summary_prompt = "你是一个对话总结助手。请将以下对话总结为简明摘要，保留关键信息：\n- 用户的主要目标\n- 已完成事项\n- 重要决策\n- 待办事项\n只输出摘要内容，不要任何前缀说明。\n\n=== 对话内容 ===\n" + conversation
	_v61_is_generating_summary = true
	_update_ui_state(true)   # 发送按钮变终止
	_set_tool_progress("💭 正在准备总结…")
	
	if _v61_summary_http == null:
		_v61_summary_http = HTTPRequest.new()
		_v61_summary_http.use_threads = true
		_v61_summary_http.timeout = 360.0
		add_child(_v61_summary_http)
		_v61_summary_http.request_completed.connect(_v61_on_summary_response)
	
	var url := ""
	var headers := ["Content-Type: application/json"]
	var body := ""
	if provider == 0:
		var m: String = model if model != "" else "gemini-1.5-flash"
		if base_url != "":
			url = base_url.rstrip("/") + "/v1beta/models/" + m + ":generateContent"
		else:
			url = "https://generativelanguage.googleapis.com/v1beta/models/" + m + ":generateContent"
		if api_key != "":
			url += ("&key=" if "?" in url else "?key=") + api_key
		body = JSON.stringify({"contents": [{"role": "user", "parts": [{"text": summary_prompt}]}]})
	else:
		var m2: String = model if model != "" else "gpt-4o-mini"
		if base_url != "":
			url = base_url.rstrip("/") + "/chat/completions"
		else:
			url = "https://api.openai.com/v1/chat/completions"
		if not url.ends_with("/chat/completions"):
			url = url.rstrip("/") + "/chat/completions"
		if api_key != "":
			headers.append("Authorization: Bearer " + api_key)
		body = JSON.stringify({"model": m2, "messages": [{"role": "user", "content": summary_prompt}]})
	
	_set_tool_progress("💭 正在连接 API…")
	await get_tree().create_timer(0.4).timeout
	if not _v61_is_generating_summary:
		return
	_set_tool_progress("💭 等待 AI 输出总结…")
	
	var err = _v61_summary_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_v61_is_generating_summary = false
		_update_ui_state(false)
		_clear_tool_progress()
		_show_toast("[color=red]总结请求失败：" + str(err) + "[/color]")


func _v61_on_summary_response(_result, code, _headers, body):
	_v61_is_generating_summary = false
	_update_ui_state(false)
	_clear_tool_progress()
	if code != 200:
		_show_toast("[color=red]总结失败（HTTP " + str(code) + "）[/color]")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	var text := ""
	if json and json.has("candidates"):
		var parts = json["candidates"][0].get("content", {}).get("parts", [])
		for part in parts:
			if part.has("text"):
				text += part["text"]
	elif json and json.has("choices"):
		text = json["choices"][0].get("message", {}).get("content", "")
	if text.strip_edges() == "":
		_show_toast("[color=red]总结内容为空[/color]")
		return
	_v61_render_summary(text.strip_edges())
	_show_toast("[color=green]对话总结已生成[/color]")


func _v61_cancel_summary():
	_v61_is_generating_summary = false
	if _v61_summary_http != null and is_instance_valid(_v61_summary_http):
		if _v61_summary_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			_v61_summary_http.cancel_request()
	_update_ui_state(false)
	_clear_tool_progress()
	_show_toast("[color=orange]已取消总结[/color]")



# ═══════════════════════════════════════════════════════════════
# 修复66：文件命名 + 加载插入位置 + URL 顺序 + summary 双保险
# ═══════════════════════════════════════════════════════════════

func _v66_v66_get_session_file_id() -> String:
	if _session_file_id != "":
		return _session_file_id
	# 优先根据首条用户消息命名
	var title: String = ""
	for child in chat_vbox.get_children():
		if child.has_meta("role") and str(child.get_meta("role")) == "user":
			var lbl = child.get_meta("label", null)
			if is_instance_valid(lbl):
				title = lbl.get_parsed_text().strip_edges()
				if title != "":
					break
	if title == "":
		title = "新对话"
	# 清洗文件名
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\t", "\r"]:
		title = title.replace(ch, "_")
	if title.length() > 24:
		title = title.substr(0, 24)
	var base_name: String = "对话 " + title
	var final_name: String = base_name
	var counter: int = 1
	while FileAccess.file_exists(HISTORY_DIR + "/" + final_name + ".json"):
		counter += 1
		final_name = base_name + "_" + str(counter)
		if counter > 999:
			break
	_session_file_id = final_name
	return _session_file_id


func _v66_v66_on_new_chat_pressed():
	if gemini_client:
		if gemini_client.has_method("new_session"):
			gemini_client.new_session()
		# 立即清掉 provider 自动生成的 session_id
		if "current_session_id" in gemini_client:
			gemini_client.set("current_session_id", "")
		_clear_chat()
		_session_file_id = ""
		_last_reasoning_full = ""
		_show_toast("[color=gray]已开始新对话[/color]")
		_update_ui_state(false)
	_refresh_conversations_list()


func _v66_render_msg(entry, insert_index: int = -1):
	if not (entry is Dictionary):
		return
	var role: String = str(entry.get("role", "user"))
	var text: String = str(entry.get("text", ""))
	var blocks = entry.get("blocks", [])
	if role == "summary":
		_v61_render_summary(text, insert_index)
		return
	if role == "user":
		_log_user_message(text, -1, insert_index)
		return
	if role == "ai" or role == "model" or role == "system" or role == "assistant":
		_add_to_chat("\n[b]Response:[/b]\n", "ai", insert_index)
		var clean_text: String = _strip_response_prefix(str(text))
		if clean_text.strip_edges() != "":
			_add_to_chat(_markdown_to_bbcode(clean_text) + "\n", "ai", insert_index)
		if blocks is Array:
			for b in blocks:
				if not (b is Dictionary):
					continue
				var lbl: String = str(b.get("label", ""))
				var content: String = str(b.get("content", ""))
				var color: String = str(b.get("color", "gray"))
				var expanded: bool = bool(b.get("expanded", false))
				if content == "" and lbl == "":
					continue
				_append_collapsible_block(lbl, content, color, expanded)
		return
	_log_user_message(text, -1, insert_index)


func _v66_v66_rebuild_chat_from_transcript():
	_clear_chat()
	_pending_history_entries.clear()
	if _load_more_btn and is_instance_valid(_load_more_btn):
		_load_more_btn.queue_free()
		_load_more_btn = null
	if gemini_client == null or not ("transcript" in gemini_client):
		return
	var all_entries = gemini_client.transcript
	if not (all_entries is Array) or all_entries.is_empty():
		return
	var last_summary_idx: int = -1
	for i in range(all_entries.size() - 1, -1, -1):
		var e = all_entries[i]
		if e is Dictionary and str(e.get("role", "")) == "summary":
			last_summary_idx = i
			break
	var to_render: Array = []
	if last_summary_idx >= 0:
		to_render = all_entries.slice(last_summary_idx)
		_pending_history_entries = all_entries.slice(0, last_summary_idx)
	else:
		if all_entries.size() > 5:
			_pending_history_entries = all_entries.slice(0, all_entries.size() - 5)
			to_render = all_entries.slice(all_entries.size() - 5)
		else:
			to_render = all_entries
	# 先渲染所有消息
	for entry in to_render:
		_v66_render_msg(entry)
	# 最后加 load_more_btn（放最前）
	if not _pending_history_entries.is_empty():
		_v66_v66_add_load_more_button()


func _v66_v66_add_load_more_button():
	if _load_more_btn and is_instance_valid(_load_more_btn):
		_load_more_btn.queue_free()
		_load_more_btn = null
	_load_more_btn = Button.new()
	var text_msg: String = locale_manager.tr("load_older_messages") if locale_manager and locale_manager.has_method("tr") else "加载以上消息"
	_load_more_btn.text = str(_pending_history_entries.size()) + " " + text_msg
	_load_more_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_load_more_btn.pressed.connect(_v66_load_older_messages)
	chat_vbox.add_child(_load_more_btn)
	chat_vbox.move_child(_load_more_btn, 0)


func _v66_v66_load_older_messages():
	if _pending_history_entries.is_empty() or _load_more_btn == null or _load_more_btn.disabled:
		return
	_load_more_btn.disabled = true
	_load_more_btn.text = "加载中…"
	await get_tree().process_frame
	var old_scroll = chat_scroll.scroll_vertical
	var old_height = chat_vbox.size.y
	var total: int = _pending_history_entries.size()
	var batch_start: int = max(0, total - 5)
	var batch_end: int = total
	for i in range(total - 1, batch_start - 1, -1):
		var e = _pending_history_entries[i]
		if e is Dictionary and str(e.get("role", "")) == "summary":
			batch_start = i
			break
	var batch: Array = _pending_history_entries.slice(batch_start, batch_end)
	if batch_start == 0:
		_pending_history_entries.clear()
	else:
		_pending_history_entries.resize(batch_start)
	# 插入位置：load_more_btn 之后（= index 1）
	var insert_at: int = 1
	for entry in batch:
		_v66_render_msg(entry, insert_at)
		insert_at += 1
	if _pending_history_entries.is_empty():
		_load_more_btn.queue_free()
		_load_more_btn = null
	else:
		_load_more_btn.disabled = false
		_load_more_btn.text = str(_pending_history_entries.size()) + " 条更早消息"
	await get_tree().process_frame
	await get_tree().process_frame
	chat_scroll.scroll_vertical = old_scroll + (chat_vbox.size_y_or(old_height))


func chat_vbox_size_y_or(_fallback: float) -> float:
	return chat_vbox.size.y


# ─── 总结双保险：system + history 第一条 ───
func _v66_apply_summary_as_context():
	if not gemini_client or not ("history" in gemini_client):
		return
	var summary_text: String = _v61_get_summary_text()
	if summary_text == "":
		return
	var hist: Array = gemini_client.get("history")
	if not (hist is Array):
		return
	# 判断 provider
	var provider_index: int = 0
	var preset = presets.get(active_preset_name, {})
	if preset is Dictionary:
		provider_index = int(preset.get("provider", 0))
	var is_openai: bool = (provider_index != 0)
	# 检查 hist 前面是否已经有 summary 标记
	var has_marker: bool = false
	if hist.size() > 0 and hist[0] is Dictionary:
		var first_text: String = ""
		if is_openai:
			first_text = str(hist[0].get("content", ""))
		else:
			var parts = hist[0].get("parts", [])
			if parts is Array and parts.size() > 0:
				first_text = str(parts[0].get("text", ""))
		if "[之前对话的摘要" in first_text:
			has_marker = true
	if has_marker:
		return
	# 插入摘要
	var summary_entry_user = _v61_build_hist_entry("user",
		"[之前对话的摘要，供上下文参考]\n" + summary_text, is_openai)
	var summary_entry_model = _v61_build_hist_entry("model",
		"收到，我已了解之前的对话背景。", is_openai)
	hist.insert(0, summary_entry_model)
	hist.insert(0, summary_entry_user)
	gemini_client.set("history", hist)


# ─── URL 位置调整 ───
func _v66_fix_url_position():
	# 找到 GridContainer 和 key_section
	var preset_edit = find_child("PresetEditPanel", true, false)
	if preset_edit == null:
		return
	var key_section = preset_edit.get_node_or_null("__V63KeySection")
	if key_section == null:
		# 也可能在别的位置，递归找
		key_section = _v66_find_by_name(self, "__V63KeySection")
		if key_section == null:
			return
	var settings_bar = find_child("SettingsBar", true, false)
	if settings_bar == null:
		return
	# 让 key_section 在 SettingsBar 之后
	var parent = settings_bar.get_parent()
	if parent == null:
		return
	if key_section.get_parent() != parent:
		key_section.reparent(parent)
	var idx: int = settings_bar.get_index()
	parent.move_child(key_section, idx + 1)


func _v66_find_by_name(node: Node, target: String) -> Node:
	if String(node.name) == target:
		return node
	for c in node.get_children():
		var r = _v66_find_by_name(c, target)
		if r != null:
			return r
	return null


func _v66_init():
	_v66_fix_url_position()

func _v61_render_summary(summary_text: String, insert_index: int = -1):
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.set_meta("role", "summary")
	wrapper.set_meta("is_summary", true)
	wrapper.set_meta("summary_text", summary_text)
	var sep := HSeparator.new()
	wrapper.add_child(sep)
	var btn := Button.new()
	btn.text = "📄 对话总结（点击查看/编辑）"
	btn.flat = true
	btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	btn.pressed.connect(func(): _v61_show_summary_dialog(wrapper))
	wrapper.add_child(btn)
	var sep2 := HSeparator.new()
	wrapper.add_child(sep2)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.visible = false
	lbl.text = summary_text
	wrapper.add_child(lbl)
	wrapper.set_meta("label", lbl)
	chat_vbox.add_child(wrapper)
	if insert_index != -1:
		chat_vbox.move_child(wrapper, insert_index)
		return
	# 只在"追加到底部"时才滚动到底
	await get_tree().process_frame
	var vbar = null
	if chat_scroll != null:
		vbar = chat_scroll.get_v_scroll_bar()
	if vbar:
		var near_bottom: bool = (vbar.max_value - vbar.value - vbar.page) < 100
		if near_bottom:
			vbar.value = vbar.max_value
func chat_vscroll_get_bar():
	if chat_scroll == null:
		return null
	return chat_scroll.get_v_scroll_bar()


# ═══ 修复68 wrapper ═══
func _on_new_chat_pressed():
	_v66_on_new_chat_pressed()

func _load_older_messages():
	_v66_load_older_messages()

func _rebuild_chat_from_transcript():
	_v66_rebuild_chat_from_transcript()

func _add_load_more_button():
	_v66_add_load_more_button()

func _get_session_file_id() -> String:
	return _v66_get_session_file_id()

func _v64_render_msg(entry, insert_index: int = -1):
	_v66_render_msg(entry, insert_index)



# ═══════════════════════════════════════════════════════════════
# 修复69：无限重试（独立计时器 + 用户终止丢弃）
# ═══════════════════════════════════════════════════════════════



# ═══════════════════════════════════════════════════════════════
# 修复70：无限重试 + 摘要格式
# ═══════════════════════════════════════════════════════════════

var _v69_retry_active: bool = false
var _v69_retry_cancelled: bool = false
var _v69_retry_timer: Timer = null
var _v69_retry_count: int = 0


func _v69_ensure_timer():
	if _v69_retry_timer != null and is_instance_valid(_v69_retry_timer):
		return
	_v69_retry_timer = Timer.new()
	_v69_retry_timer.name = "V69RetryTimer"
	_v69_retry_timer.one_shot = true
	_v69_retry_timer.wait_time = 5.0
	_v69_retry_timer.timeout.connect(_v69_on_retry_timeout)
	add_child(_v69_retry_timer)


func _v69_start_retry_wait(wait_s: float):
	_v69_ensure_timer()
	_v69_retry_active = true
	_v69_retry_cancelled = false
	_v69_retry_timer.stop()
	_v69_retry_timer.wait_time = wait_s
	_v69_retry_timer.start()
	# 强制"终止"样式（只在这里设一次，之后不再切换）
	_update_ui_state(true)


# 计时器到时：所有状态检查通过才发请求；否则清理
func _v69_on_retry_timeout():
	if _v69_retry_cancelled:
		_v69_cleanup_and_restore()
		return
	if _is_stopped:
		_v69_cleanup_and_restore()
		return
	if not _infinite_retry:
		_v69_cleanup_and_restore()
		return
	if not _v69_retry_active:
		_v69_cleanup_and_restore()
		return
	if _last_send_payload.is_empty():
		_v69_cleanup_and_restore()
		return
	if gemini_client == null:
		_v69_cleanup_and_restore()
		return
	# 输入框已恢复可编辑 → 用户已终止
	if input_field != null and input_field.editable == true:
		_v69_cleanup_and_restore()
		return
	# 发出请求；保持"终止"状态（不调 _update_ui_state，避免闪烁）
	var tools = _get_filtered_tools()
	gemini_client.send_prompt(_last_send_payload["final_prompt"], _last_send_payload["context"], tools, [])
	_set_tool_progress("💭 接收响应中…（第 " + str(_v69_retry_count) + " 次已发出）")


func _v69_cleanup_and_restore():
	if _v69_retry_timer != null and is_instance_valid(_v69_retry_timer):
		_v69_retry_timer.stop()
	_v69_retry_active = false
	_v69_retry_cancelled = false
	_v69_retry_count = 0
	_is_retrying = false
	_clear_tool_progress()
	_update_ui_state(false)


func _v69_stop_retry():
	_v69_retry_active = false
	_v69_retry_count = 0
	if _v69_retry_timer != null and is_instance_valid(_v69_retry_timer):
		_v69_retry_timer.stop()
	_clear_tool_progress()


func _v69_is_active() -> bool:
	return _v69_retry_active


# ─── 摘要注入 history（独特格式）───
func _v69_force_summary_into_history():
	# 这个函数保留做双保险：把摘要注入 history[0] 和 custom_instructions
	if not gemini_client:
		return
	var summary_text: String = ""
	if has_method("_v61_get_summary_text"):
		summary_text = _v61_get_summary_text()
	if summary_text.strip_edges() == "":
		return
	var hist = gemini_client.get("history")
	if not (hist is Array):
		return
	var provider_index: int = 0
	var preset = presets.get(active_preset_name, {})
	if preset is Dictionary:
		provider_index = int(preset.get("provider", 0))
	var is_openai: bool = (provider_index != 0)
	var wrapped: String = "───对话摘要───
" + summary_text + "
───对话摘要结束───"
	var cleaned: Array = []
	for e in hist:
		if e is Dictionary:
			var first_text: String = ""
			if is_openai:
				first_text = str(e.get("content", ""))
			else:
				var parts = e.get("parts", [])
				if parts is Array and parts.size() > 0 and parts[0] is Dictionary:
					first_text = str(parts[0].get("text", ""))
			if first_text.begins_with("───对话摘要───"):
				continue
			if first_text.begins_with("收到，我已了解之前的对话背景"):
				continue
		cleaned.append(e)
	var u = _v61_build_hist_entry("user", wrapped, is_openai)
	var m = _v61_build_hist_entry("model", "收到，我已了解之前的对话背景。", is_openai)
	cleaned.insert(0, m)
	cleaned.insert(0, u)
	gemini_client.set("history", cleaned)
	pass
func _v70_init():
	_v69_ensure_timer()
