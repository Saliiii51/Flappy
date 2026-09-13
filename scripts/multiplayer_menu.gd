extends Control

@onready var main_selection: Control = $Panel/VBox/MainSelection
@onready var online_lobby: Control = $Panel/VBox/OnlineLobby

@onready var player_name_label: Label = $Panel/VBox/ProfileBar/PlayerNameLabel
@onready var name_modal: Control = $NameModal
@onready var modal_name_input: LineEdit = $NameModal/Card/Margin/VBox/ModalNameInput

@onready var host_section: Control = $Panel/VBox/OnlineLobby/HostSection
@onready var join_section: Control = $Panel/VBox/OnlineLobby/JoinSection

@onready var server_status_label: Label = $Panel/VBox/OnlineLobby/ServerStatusLabel
@onready var room_code_label: Label = $Panel/VBox/OnlineLobby/HostSection/RoomCodeLabel
@onready var host_status_label: Label = $Panel/VBox/OnlineLobby/HostSection/HostStatusLabel

@onready var code_input: LineEdit = $Panel/VBox/OnlineLobby/JoinSection/CodeInput
@onready var join_btn: Button = $Panel/VBox/OnlineLobby/JoinSection/JoinBtn
@onready var join_status_label: Label = $Panel/VBox/OnlineLobby/JoinSection/JoinStatusLabel

@onready var audio_player: AudioStreamPlayer = $SwooshPlayer

var quick_section: VBoxContainer
var quick_btn: Button
var quick_status_label: Label
var quick_cancel_btn: Button
var is_searching: bool = false

var friends_section: VBoxContainer
var friend_input: LineEdit
var friends_list_box: VBoxContainer
var invite_banner: VBoxContainer
var invite_banner_label: Label
var pending_invite_name: String = ""
var incoming_invite_code: String = ""

func _ready() -> void:
	main_selection.visible = true
	online_lobby.visible = false
	if name_modal:
		name_modal.visible = false

	if code_input:
		code_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER

	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	var fade_tween = create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.35)
	fade_tween.tween_callback(fade.queue_free)
	
	_update_player_name_ui()
	if not NetworkManager.has_custom_name():
		_show_name_modal()
	
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.room_error.connect(_on_room_error)
	NetworkManager.match_searching.connect(_on_match_searching)
	NetworkManager.friends_received.connect(_on_friends_received)
	NetworkManager.invite_received.connect(_on_invite_received)
	NetworkManager.invite_sent.connect(_on_invite_sent)
	NetworkManager.invite_failed.connect(_on_invite_failed)

	_build_quick_section()
	_build_friends_section()
	
	_update_server_status()
	
	if modal_name_input:
		modal_name_input.text_submitted.connect(func(_t): _on_modal_save_pressed())
	if code_input:
		code_input.text_submitted.connect(func(_t): _on_join_btn_pressed())

func _update_server_status() -> void:
	if server_status_label:
		if NetworkManager.is_connected_to_server:
			server_status_label.text = "🟢 Sunucuya Bağlandı"
			server_status_label.modulate = Color(0.4, 1.0, 0.4)
		else:
			server_status_label.text = "🟡 Sunucuya Bağlanılıyor..."
			server_status_label.modulate = Color(1.0, 0.9, 0.3)

func _on_connected_to_server() -> void:
	_update_server_status()

func _on_connection_failed() -> void:
	if server_status_label:
		server_status_label.text = "🔴 Sunucuya Bağlanılamadı"
		server_status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_server_disconnected() -> void:
	if server_status_label:
		server_status_label.text = "🔴 Sunucu Bağlantısı Koptu"
		server_status_label.modulate = Color(1.0, 0.3, 0.3)

func _play_swoosh() -> void:
	if audio_player:
		audio_player.play()

func _on_local_versus_pressed() -> void:
	_play_swoosh()
	get_tree().change_scene_to_file("res://scenes/local_versus.tscn")

func _on_stickman_race_pressed() -> void:
	_play_swoosh()
	get_tree().change_scene_to_file("res://scenes/stickman_race.tscn")

# --- ARKADAŞLAR + DAVET ---
func _build_friends_section() -> void:
	if friends_section or online_lobby == null:
		return
	friends_section = VBoxContainer.new()
	friends_section.add_theme_constant_override("separation", 6)
	online_lobby.add_child(friends_section)
	online_lobby.move_child(friends_section, 3)

	var title := Label.new()
	title.text = "👥 ARKADAŞLAR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	friends_section.add_child(title)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	friends_section.add_child(add_row)

	friend_input = LineEdit.new()
	friend_input.placeholder_text = "Oyuncu adı"
	friend_input.max_length = 12
	friend_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend_input.text_submitted.connect(func(_t): _on_friend_add_pressed())
	add_row.add_child(friend_input)

	var add_btn := Button.new()
	add_btn.text = "➕ EKLE"
	add_btn.add_theme_font_size_override("font_size", 10)
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(_on_friend_add_pressed)
	add_row.add_child(add_btn)

	friends_list_box = VBoxContainer.new()
	friends_list_box.add_theme_constant_override("separation", 3)
	friends_section.add_child(friends_list_box)

	invite_banner = VBoxContainer.new()
	invite_banner.add_theme_constant_override("separation", 4)
	invite_banner.visible = false
	friends_section.add_child(invite_banner)

	invite_banner_label = Label.new()
	invite_banner_label.add_theme_font_size_override("font_size", 11)
	invite_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	invite_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite_banner.add_child(invite_banner_label)

	var invite_row := HBoxContainer.new()
	invite_row.add_theme_constant_override("separation", 6)
	invite_row.alignment = BoxContainer.ALIGNMENT_CENTER
	invite_banner.add_child(invite_row)

	var accept_btn := Button.new()
	accept_btn.text = "✅ KATIL"
	accept_btn.add_theme_font_size_override("font_size", 11)
	accept_btn.focus_mode = Control.FOCUS_NONE
	accept_btn.pressed.connect(_on_invite_accept_pressed)
	invite_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "❌ REDDET"
	decline_btn.add_theme_font_size_override("font_size", 11)
	decline_btn.focus_mode = Control.FOCUS_NONE
	decline_btn.pressed.connect(func(): invite_banner.visible = false)
	invite_row.add_child(decline_btn)

func _on_online_menu_pressed() -> void:
	_play_swoosh()
	main_selection.visible = false
	online_lobby.visible = true
	host_section.visible = false
	join_section.visible = false
	NetworkManager.connect_to_server()
	_update_server_status()
	NetworkManager.request_friends()

func _on_back_to_main_pressed() -> void:
	_play_swoosh()
	_cancel_search_if_active()
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_back_to_selection_pressed() -> void:
	_play_swoosh()
	_cancel_search_if_active()
	pending_invite_name = ""
	if invite_banner:
		invite_banner.visible = false
	NetworkManager.disconnect_game()
	main_selection.visible = true
	online_lobby.visible = false
	host_section.visible = false
	join_section.visible = false

# --- QUICK MATCH (rastgele eşleşme) ---
func _build_quick_section() -> void:
	if quick_section or online_lobby == null:
		return
	quick_section = VBoxContainer.new()
	quick_section.add_theme_constant_override("separation", 8)
	online_lobby.add_child(quick_section)
	online_lobby.move_child(quick_section, 2)

	quick_btn = Button.new()
	quick_btn.custom_minimum_size = Vector2(0, 42)
	quick_btn.add_theme_font_size_override("font_size", 12)
	quick_btn.text = "⚡ HIZLI EŞLEŞME\n(Rastgele Rakip)"
	quick_btn.pressed.connect(_on_quick_match_pressed)
	quick_section.add_child(quick_btn)

	quick_status_label = Label.new()
	quick_status_label.add_theme_font_size_override("font_size", 10)
	quick_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quick_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quick_status_label.visible = false
	quick_section.add_child(quick_status_label)

	quick_cancel_btn = Button.new()
	quick_cancel_btn.custom_minimum_size = Vector2(0, 30)
	quick_cancel_btn.add_theme_font_size_override("font_size", 11)
	quick_cancel_btn.text = "❌ VAZGEÇ"
	quick_cancel_btn.visible = false
	quick_cancel_btn.pressed.connect(_on_quick_cancel_pressed)
	quick_section.add_child(quick_cancel_btn)

func _on_quick_match_pressed() -> void:
	_play_swoosh()
	if is_searching:
		return
	is_searching = true
	host_section.visible = false
	join_section.visible = false
	quick_btn.disabled = true
	quick_btn.text = "🔍 RAKİP ARANIYOR..."
	quick_status_label.text = "⏳ Sunucuya bağlanılıyor..."
	quick_status_label.visible = true
	quick_cancel_btn.visible = true
	NetworkManager.quick_match()

func _on_match_searching() -> void:
	if not is_searching or quick_status_label == null:
		return
	quick_status_label.text = "🔍 Rakip aranıyor...\nBulunca maç otomatik başlar."

func _on_quick_cancel_pressed() -> void:
	_play_swoosh()
	_cancel_search_ui()
	NetworkManager.cancel_quick_match()

func _cancel_search_ui() -> void:
	is_searching = false
	if quick_btn:
		quick_btn.disabled = false
		quick_btn.text = "⚡ HIZLI EŞLEŞME\n(Rastgele Rakip)"
	if quick_status_label:
		quick_status_label.visible = false
	if quick_cancel_btn:
		quick_cancel_btn.visible = false

func _cancel_search_if_active() -> void:
	if is_searching:
		_cancel_search_ui()
		NetworkManager.cancel_quick_match()

func _on_friend_add_pressed() -> void:
	if friend_input == null:
		return
	_play_swoosh()
	NetworkManager.add_friend(friend_input.text)
	friend_input.text = ""

func _on_friends_received(friends: Array) -> void:
	if friends_list_box == null:
		return
	for child in friends_list_box.get_children():
		child.queue_free()
	if friends.is_empty():
		var lbl := Label.new()
		lbl.text = "Henüz arkadaş yok — isimle ekle."
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		friends_list_box.add_child(lbl)
		return
	for f in friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_lbl := Label.new()
		name_lbl.text = "👤 " + str(f)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		row.add_child(name_lbl)
		var invite_btn := Button.new()
		invite_btn.text = "✉️ DAVET"
		invite_btn.add_theme_font_size_override("font_size", 9)
		invite_btn.focus_mode = Control.FOCUS_NONE
		invite_btn.pressed.connect(_on_invite_pressed.bind(str(f)))
		row.add_child(invite_btn)
		var del_btn := Button.new()
		del_btn.text = "✖"
		del_btn.add_theme_font_size_override("font_size", 9)
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.pressed.connect(_on_friend_remove_pressed.bind(str(f)))
		row.add_child(del_btn)
		friends_list_box.add_child(row)

func _on_friend_remove_pressed(friend_name: String) -> void:
	_play_swoosh()
	NetworkManager.remove_friend(friend_name)

func _on_invite_pressed(friend_name: String) -> void:
	_play_swoosh()
	pending_invite_name = friend_name
	# Oda kur (host sekmesi davet sonrası kodu bildirecek)
	_on_host_tab_pressed()

func _on_invite_accept_pressed() -> void:
	_play_swoosh()
	if invite_banner:
		invite_banner.visible = false
	if incoming_invite_code != "":
		NetworkManager.join_room(incoming_invite_code)
		join_status_label.text = "⏳ Davet edilen odaya katılınıyor..."

func _on_invite_received(from_name: String, room_code: String) -> void:
	incoming_invite_code = room_code
	if invite_banner_label:
		invite_banner_label.text = "✉️ %s seni maça davet etti!" % from_name
	if invite_banner:
		invite_banner.visible = true
	_play_swoosh()

func _on_invite_sent(to_name: String) -> void:
	pending_invite_name = ""
	if host_status_label:
		host_status_label.text = "✉️ %s davet edildi!\nKatılması bekleniyor..." % to_name

func _on_invite_failed(to_name: String, reason: String) -> void:
	pending_invite_name = ""
	if host_status_label:
		if reason == "offline":
			host_status_label.text = "⚠️ %s şu an çevrimdışı." % to_name
		else:
			host_status_label.text = "⚠️ Davet gönderilemedi."

# --- HOST LOGIC ---
func _on_host_tab_pressed() -> void:
	_play_swoosh()
	_cancel_search_if_active()
	host_section.visible = true
	join_section.visible = false
	room_code_label.text = "KOD ALINIYOR..."
	host_status_label.text = "⏳ Sunucudan oda kodu alınıyor..."
	NetworkManager.create_room()

func _on_room_created(code: String) -> void:
	room_code_label.text = "ODA KODU: %s" % code
	host_status_label.text = "📢 Arkadaşına bu kodu ver!\nKatıldığında maç otomatik başlar..."
	if pending_invite_name != "":
		host_status_label.text = "✉️ %s davet ediliyor..." % pending_invite_name
		NetworkManager.send_invite(pending_invite_name, code)

# --- JOIN LOGIC ---
func _on_join_tab_pressed() -> void:
	_play_swoosh()
	_cancel_search_if_active()
	host_section.visible = false
	join_section.visible = true
	join_status_label.text = "Arkadaşının verdiği 4 haneli kodu gir."
	join_btn.disabled = false
	if code_input:
		code_input.text = ""

func _on_join_btn_pressed() -> void:
	_play_swoosh()
	var code = code_input.text.strip_edges()
	if code.is_empty():
		join_status_label.text = "⚠️ Lütfen bir oda kodu girin!"
		return
	
	join_status_label.text = "⏳ Odaya bağlanılıyor (%s)..." % code
	join_btn.disabled = true
	NetworkManager.join_room(code)

func _on_room_error(msg: String) -> void:
	join_status_label.text = "❌ " + msg
	join_btn.disabled = false

func _on_game_started(_sync_seed: int) -> void:
	_play_swoosh()
	get_tree().change_scene_to_file("res://scenes/online_battle.tscn")

func _update_player_name_ui() -> void:
	if player_name_label:
		player_name_label.text = "👤 Oyuncu: %s" % NetworkManager.get_player_name()

func _show_name_modal() -> void:
	if name_modal:
		modal_name_input.text = NetworkManager.get_player_name()
		
		var stats = NetworkManager.get_mp_stats()
		var w_lbl = name_modal.find_child("ModalWinsLabel", true, false) as Label
		var l_lbl = name_modal.find_child("ModalLossesLabel", true, false) as Label
		var t_lbl = name_modal.find_child("ModalTiesLabel", true, false) as Label
		var tot_lbl = name_modal.find_child("ModalTotalLabel", true, false) as Label
		var r_lbl = name_modal.find_child("ModalWinRateLabel", true, false) as Label
		
		if w_lbl:
			w_lbl.text = "👑 Galibiyet: %d" % stats["wins"]
		if l_lbl:
			l_lbl.text = "💀 Mağlubiyet: %d" % stats["losses"]
		if t_lbl:
			t_lbl.text = "🤝 Beraberlik: %d" % stats["ties"]
		if tot_lbl:
			tot_lbl.text = "🎮 Toplam Maç: %d" % stats["total"]
		if r_lbl:
			r_lbl.text = "📈 Kazanma Oranı: %%%.1f" % stats["win_rate"]
		
		name_modal.visible = true
		modal_name_input.grab_focus()

func _on_edit_name_pressed() -> void:
	_play_swoosh()
	_show_name_modal()

func _on_modal_save_pressed() -> void:
	_play_swoosh()
	var new_name = modal_name_input.text.strip_edges()
	if new_name != "":
		NetworkManager.save_player_name(new_name)
	_update_player_name_ui()
	name_modal.visible = false
