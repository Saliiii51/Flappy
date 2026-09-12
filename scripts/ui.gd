extends CanvasLayer
class_name GameUI

signal restart_requested
signal skin_changed(skin_name: String)
signal achievements_menu_requested

var message_screen: TextureRect
var skin_selector: HBoxContainer
var prev_skin_btn: Button
var next_skin_btn: Button
var skin_label: Label
var mute_btn: Button
var achieve_menu_btn: Button
var double_score_indicator: Label
var multiplayer_btn: Button

var score_container: HBoxContainer
var score_label: Label
var perfect_label: Label
var achievement_popup: PanelContainer
var achieve_icon: Label
var achieve_title: Label
var achieve_desc: Label

var profile_btn: Button
var profile_modal: Control
var profile_name_input: LineEdit
var save_profile_btn: Button
var wins_label: Label
var losses_label: Label
var ties_label: Label
var total_matches_label: Label
var win_rate_label: Label

var achievements_modal: Control
var close_achieve_btn: Button
var achieve_list: VBoxContainer
var achieve_count_label: Label
var dim_overlay: ColorRect

var game_over_panel: Control
var medal_badge: Label
var new_record_badge: Label
var current_score_label: Label
var best_score_label: Label
var restart_hint: Label
var restart_btn: Button

var boss_warning_banner: Label
var boss_health_container: HBoxContainer
var boss_hp_label: Label
var boss_defeated_banner: Label

var digit_textures: Array[Texture2D] = []

const SKINS: Array[String] = ["yellow", "blue", "red"]
const SKIN_NAMES: Dictionary = {
	"yellow": "🟡 SARI KUŞ",
	"blue": "🔵 MAVİ KUŞ",
	"red": "🔴 KIRMIZI KUŞ"
}
var current_skin_idx: int = 0
var is_muted: bool = false
var is_showing_achievement: bool = false

func _ready() -> void:
	_init_node_references()
	
	for i in range(10):
		var path = "res://assets/sprites/%d.png" % i
		if ResourceLoader.exists(path):
			var tex = load(path) as Texture2D
			digit_textures.append(tex)
	
	if prev_skin_btn:
		prev_skin_btn.pressed.connect(_on_prev_skin_pressed)
	if next_skin_btn:
		next_skin_btn.pressed.connect(_on_next_skin_pressed)
	if mute_btn:
		mute_btn.pressed.connect(_on_mute_pressed)
	if achieve_menu_btn:
		achieve_menu_btn.pressed.connect(_on_achieve_menu_pressed)
	if close_achieve_btn:
		close_achieve_btn.pressed.connect(close_achievements_modal)
	if multiplayer_btn:
		multiplayer_btn.pressed.connect(_on_multiplayer_btn_pressed)
	
	if profile_btn:
		profile_btn.pressed.connect(open_profile_modal)
	if save_profile_btn:
		save_profile_btn.pressed.connect(save_and_close_profile)
	if profile_name_input:
		profile_name_input.text_submitted.connect(func(_t): save_and_close_profile())
	
	_update_profile_button_text()
	
	show_message()
	update_score(0)
	if game_over_panel:
		game_over_panel.visible = false
	if perfect_label:
		perfect_label.visible = false
	if achievements_modal:
		achievements_modal.visible = false
	if profile_modal:
		profile_modal.visible = false
	
	# Prompt profile creation on first game launch if no custom name set yet!
	if not NetworkManager.has_custom_name():
		open_profile_modal()

func _on_multiplayer_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn")

func _init_node_references() -> void:
	if not message_screen:
		message_screen = find_child("MessageScreen", true, false) as TextureRect
	if not skin_selector:
		skin_selector = find_child("SkinSelector", true, false) as HBoxContainer
	if not prev_skin_btn:
		prev_skin_btn = find_child("PrevSkinBtn", true, false) as Button
	if not next_skin_btn:
		next_skin_btn = find_child("NextSkinBtn", true, false) as Button
	if not skin_label:
		skin_label = find_child("SkinLabel", true, false) as Label
	if not mute_btn:
		mute_btn = find_child("MuteButton", true, false) as Button
	if not achieve_menu_btn:
		achieve_menu_btn = find_child("AchieveMenuButton", true, false) as Button
	if not double_score_indicator:
		double_score_indicator = find_child("DoubleScoreIndicator", true, false) as Label
	if not multiplayer_btn:
		multiplayer_btn = find_child("MultiplayerButton", true, false) as Button
	
	if not score_container:
		score_container = find_child("ScoreContainer", true, false) as HBoxContainer
	if not score_label:
		score_label = find_child("ScoreLabel", true, false) as Label
	if not perfect_label:
		perfect_label = find_child("PerfectLabel", true, false) as Label
	if not achievement_popup:
		achievement_popup = find_child("AchievementPopup", true, false) as PanelContainer
	if not achieve_icon:
		achieve_icon = find_child("AchieveIcon", true, false) as Label
	if not achieve_title:
		achieve_title = find_child("AchieveTitle", true, false) as Label
	if not achieve_desc:
		achieve_desc = find_child("AchieveDesc", true, false) as Label
	
	if not achievements_modal:
		achievements_modal = find_child("AchievementsModal", true, false) as Control
	if not close_achieve_btn:
		close_achieve_btn = find_child("CloseAchieveBtn", true, false) as Button
	if not achieve_list:
		achieve_list = find_child("AchieveList", true, false) as VBoxContainer
	if not achieve_count_label:
		achieve_count_label = find_child("AchieveCountLabel", true, false) as Label
	
	if not profile_btn:
		profile_btn = find_child("ProfileButton", true, false) as Button
	if not profile_modal:
		profile_modal = find_child("ProfileModal", true, false) as Control
	if not profile_name_input:
		profile_name_input = find_child("ProfileNameInput", true, false) as LineEdit
	if not save_profile_btn:
		save_profile_btn = find_child("SaveProfileBtn", true, false) as Button
	if not wins_label:
		wins_label = find_child("WinsLabel", true, false) as Label
	if not losses_label:
		losses_label = find_child("LossesLabel", true, false) as Label
	if not ties_label:
		ties_label = find_child("TiesLabel", true, false) as Label
	if not total_matches_label:
		total_matches_label = find_child("TotalMatchesLabel", true, false) as Label
	if not win_rate_label:
		win_rate_label = find_child("WinRateLabel", true, false) as Label
	
	if not game_over_panel:
		game_over_panel = find_child("GameOverPanel", true, false) as Control
	if not medal_badge:
		medal_badge = find_child("MedalBadge", true, false) as Label
	if not new_record_badge:
		new_record_badge = find_child("NewRecordBadge", true, false) as Label
	if not current_score_label:
		current_score_label = find_child("CurrentScoreLabel", true, false) as Label
	if not best_score_label:
		best_score_label = find_child("BestScoreLabel", true, false) as Label
	if not restart_hint:
		restart_hint = find_child("RestartHint", true, false) as Label
	if not restart_btn:
		restart_btn = find_child("RestartBtn", true, false) as Button
	if restart_btn and not restart_btn.pressed.is_connected(_on_restart_btn_pressed):
		restart_btn.pressed.connect(_on_restart_btn_pressed)
	if game_over_panel and not game_over_panel.gui_input.is_connected(_on_game_over_panel_gui_input):
		game_over_panel.gui_input.connect(_on_game_over_panel_gui_input)
	
	if not boss_warning_banner:
		boss_warning_banner = find_child("BossWarningBanner", true, false) as Label
	if not boss_health_container:
		boss_health_container = find_child("BossHealthContainer", true, false) as HBoxContainer
	if not boss_hp_label:
		boss_hp_label = find_child("BossHPLabel", true, false) as Label
	if not boss_defeated_banner:
		boss_defeated_banner = find_child("BossDefeatedBanner", true, false) as Label

func show_boss_warning() -> void:
	_init_node_references()
	if not boss_warning_banner:
		return
	boss_warning_banner.visible = true
	boss_warning_banner.modulate.a = 1.0
	var tween = create_tween()
	# Flash effect
	for i in range(4):
		tween.tween_property(boss_warning_banner, "modulate:a", 0.2, 0.15)
		tween.tween_property(boss_warning_banner, "modulate:a", 1.0, 0.15)
	tween.tween_property(boss_warning_banner, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): boss_warning_banner.visible = false)

func update_boss_health(current_hp: int, max_hp: int) -> void:
	_init_node_references()
	if not boss_health_container or not boss_hp_label:
		return
	boss_health_container.visible = (current_hp > 0)
	var hearts = ""
	for i in range(max_hp):
		if i < current_hp:
			hearts += "❤️"
		else:
			hearts += "🖤"
	boss_hp_label.text = hearts

func show_boss_defeated() -> void:
	_init_node_references()
	if boss_health_container:
		boss_health_container.visible = false
	if not boss_defeated_banner:
		return
	boss_defeated_banner.visible = true
	boss_defeated_banner.modulate.a = 1.0
	boss_defeated_banner.scale = Vector2(1.3, 1.3)
	var tween = create_tween()
	tween.tween_property(boss_defeated_banner, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_interval(2.2)
	tween.tween_property(boss_defeated_banner, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): boss_defeated_banner.visible = false)

func hide_boss_ui() -> void:
	_init_node_references()
	if boss_warning_banner:
		boss_warning_banner.visible = false
	if boss_health_container:
		boss_health_container.visible = false
	if boss_defeated_banner:
		boss_defeated_banner.visible = false

func set_initial_skin(skin_name: String) -> void:
	var idx = SKINS.find(skin_name)
	if idx >= 0:
		current_skin_idx = idx
	_update_skin_display()

func _update_skin_display() -> void:
	_init_node_references()
	var skin_id = SKINS[current_skin_idx]
	if skin_label:
		skin_label.text = SKIN_NAMES.get(skin_id, "KUŞ")

func _on_prev_skin_pressed() -> void:
	current_skin_idx = (current_skin_idx - 1 + SKINS.size()) % SKINS.size()
	_update_skin_display()
	skin_changed.emit(SKINS[current_skin_idx])

func _on_next_skin_pressed() -> void:
	current_skin_idx = (current_skin_idx + 1) % SKINS.size()
	_update_skin_display()
	skin_changed.emit(SKINS[current_skin_idx])

func _on_mute_pressed() -> void:
	is_muted = not is_muted
	AudioServer.set_bus_mute(0, is_muted)
	if mute_btn:
		mute_btn.text = "🔇" if is_muted else "🔊"

func _on_achieve_menu_pressed() -> void:
	achievements_menu_requested.emit()

func close_achievements_modal() -> void:
	_init_node_references()
	if achievements_modal:
		achievements_modal.visible = false

func open_achievements_modal(achieve_dict: Dictionary, unlocked_ids: Array) -> void:
	_init_node_references()
	if not achievements_modal or not achieve_list:
		return
	
	# Clear previous list
	for child in achieve_list.get_children():
		child.queue_free()
	
	var unlocked_count = 0
	var total_count = achieve_dict.size()
	
	for key in achieve_dict.keys():
		var info = achieve_dict[key] as Dictionary
		var is_unlocked = unlocked_ids.has(key)
		if is_unlocked:
			unlocked_count += 1
		
		var item_panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		if is_unlocked:
			style.bg_color = Color(0.24, 0.20, 0.32, 0.9)
			style.border_color = Color(1.0, 0.85, 0.2, 0.8)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
		else:
			style.bg_color = Color(0.14, 0.13, 0.18, 0.8)
			style.border_color = Color(0.3, 0.3, 0.35, 0.5)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
		item_panel.add_theme_stylebox_override("panel", style)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 6)
		item_panel.add_child(margin)
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		margin.add_child(row)
		
		var icon_lbl = Label.new()
		icon_lbl.text = info.get("icon", "🏆") if is_unlocked else "🔒"
		icon_lbl.add_theme_font_size_override("font_size", 18)
		row.add_child(icon_lbl)
		
		var text_col = VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 2)
		row.add_child(text_col)
		
		var title_lbl = Label.new()
		title_lbl.text = info.get("title", "")
		title_lbl.add_theme_font_size_override("font_size", 11)
		if is_unlocked:
			title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		else:
			title_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 1.0))
		text_col.add_child(title_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = info.get("desc", "")
		desc_lbl.add_theme_font_size_override("font_size", 9)
		if is_unlocked:
			desc_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		else:
			desc_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 1.0))
		text_col.add_child(desc_lbl)
		
		var status_lbl = Label.new()
		status_lbl.text = "✅" if is_unlocked else "🔒"
		status_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(status_lbl)
		
		achieve_list.add_child(item_panel)
	
	if achieve_count_label:
		achieve_count_label.text = "Kazanılan: %d / %d" % [unlocked_count, total_count]
	
	achievements_modal.visible = true

func show_message() -> void:
	_init_node_references()
	if message_screen:
		message_screen.visible = true
	if skin_selector:
		skin_selector.visible = true
	if multiplayer_btn:
		multiplayer_btn.visible = true
	if score_container:
		score_container.visible = false
	if score_label:
		score_label.visible = false
	if game_over_panel:
		game_over_panel.visible = false
	if double_score_indicator:
		double_score_indicator.visible = false
	if perfect_label:
		perfect_label.visible = false
	if profile_btn:
		profile_btn.visible = true
	hide_boss_ui()

func hide_message() -> void:
	_init_node_references()
	if message_screen:
		message_screen.visible = false
	if skin_selector:
		skin_selector.visible = false
	if multiplayer_btn:
		multiplayer_btn.visible = false
	if achievements_modal:
		achievements_modal.visible = false
	if profile_btn:
		profile_btn.visible = false
	if profile_modal:
		profile_modal.visible = false
	update_score(0)

func _update_profile_button_text() -> void:
	if profile_btn:
		var pname = NetworkManager.get_player_name()
		profile_btn.text = "👤 " + pname

func open_profile_modal() -> void:
	_init_node_references()
	if not profile_modal:
		return
	
	var current_name = NetworkManager.get_player_name()
	if profile_name_input:
		profile_name_input.text = current_name
		profile_name_input.grab_focus()
	
	var stats = NetworkManager.get_mp_stats()
	if wins_label:
		wins_label.text = "👑 Galibiyet: %d" % stats["wins"]
	if losses_label:
		losses_label.text = "💀 Mağlubiyet: %d" % stats["losses"]
	if ties_label:
		ties_label.text = "🤝 Beraberlik: %d" % stats["ties"]
	if total_matches_label:
		total_matches_label.text = "🎮 Toplam Maç: %d" % stats["total"]
	if win_rate_label:
		win_rate_label.text = "📈 Kazanma Oranı: %%%.1f" % stats["win_rate"]
	
	profile_modal.visible = true

func save_and_close_profile() -> void:
	if profile_name_input:
		var new_name = profile_name_input.text.strip_edges()
		if new_name != "":
			NetworkManager.save_player_name(new_name)
	_update_profile_button_text()
	if profile_modal:
		profile_modal.visible = false

func close_profile_modal() -> void:
	if profile_modal:
		profile_modal.visible = false
	if digit_textures.size() == 10:
		if score_container:
			score_container.visible = true
		if score_label:
			score_label.visible = false
	else:
		if score_container:
			score_container.visible = false
		if score_label:
			score_label.visible = true

func set_double_score_indicator(active: bool) -> void:
	_init_node_references()
	if double_score_indicator:
		double_score_indicator.visible = active

func update_score(score: int) -> void:
	_init_node_references()
	if score_label:
		score_label.text = str(score)
	
	if score_container and digit_textures.size() == 10:
		for child in score_container.get_children():
			child.queue_free()
		
		var val_str = str(score)
		for c in val_str:
			var digit = int(c)
			if digit >= 0 and digit < digit_textures.size():
				var rect = TextureRect.new()
				rect.texture = digit_textures[digit]
				rect.stretch_mode = TextureRect.STRETCH_KEEP
				rect.custom_minimum_size = Vector2(24, 36)
				score_container.add_child(rect)
	
	var punch_node: Control = score_container if (score_container and score_container.visible) else score_label
	if punch_node:
		punch_node.scale = Vector2(1.24, 1.24)
		var tween = create_tween()
		tween.tween_property(punch_node, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_perfect_indicator(at_pos: Vector2) -> void:
	_init_node_references()
	if not perfect_label:
		return
	
	perfect_label.global_position = Vector2(clampf(at_pos.x - 70.0, 10.0, 140.0), at_pos.y - 30.0)
	perfect_label.visible = true
	perfect_label.modulate.a = 1.0
	perfect_label.scale = Vector2(1.3, 1.3)
	
	var tween = create_tween()
	tween.tween_property(perfect_label, "scale", Vector2(1.0, 1.0), 0.15)
	tween.parallel().tween_property(perfect_label, "position:y", perfect_label.position.y - 25.0, 0.5)
	tween.tween_property(perfect_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): perfect_label.visible = false)

func show_achievement_banner(info: Dictionary) -> void:
	_init_node_references()
	if not achievement_popup or is_showing_achievement:
		return
	
	is_showing_achievement = true
	if achieve_icon:
		achieve_icon.text = info.get("icon", "🏆")
	if achieve_title:
		achieve_title.text = "BAŞARIM: " + info.get("title", "")
	if achieve_desc:
		achieve_desc.text = info.get("desc", "")
	
	achievement_popup.position.y = -75.0
	var tween = create_tween()
	tween.tween_property(achievement_popup, "position:y", 12.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.4)
	tween.tween_property(achievement_popup, "position:y", -75.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): is_showing_achievement = false)

func show_game_over(final_score: int, high_score: int, is_new_record: bool = false) -> void:
	_init_node_references()
	
	if score_container:
		score_container.visible = false
	if score_label:
		score_label.visible = false
	if double_score_indicator:
		double_score_indicator.visible = false
	if perfect_label:
		perfect_label.visible = false
	
	if current_score_label:
		current_score_label.text = str(final_score)
	if best_score_label:
		best_score_label.text = str(high_score)
	
	if new_record_badge:
		new_record_badge.visible = is_new_record
	
	if medal_badge:
		if final_score >= 40:
			medal_badge.text = "💎"
		elif final_score >= 30:
			medal_badge.text = "🥇"
		elif final_score >= 20:
			medal_badge.text = "🥈"
		elif final_score >= 10:
			medal_badge.text = "🥉"
		else:
			medal_badge.text = ""
	
	if game_over_panel:
		game_over_panel.visible = true
		game_over_panel.modulate.a = 0.0
		var tween = create_tween()
		if tween:
			tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.35)

func _on_restart_btn_pressed() -> void:
	restart_requested.emit()

func _on_game_over_panel_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		restart_requested.emit()
