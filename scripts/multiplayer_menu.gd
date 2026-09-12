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

func _ready() -> void:
	main_selection.visible = true
	online_lobby.visible = false
	if name_modal:
		name_modal.visible = false
	
	_update_player_name_ui()
	if not NetworkManager.has_custom_name():
		_show_name_modal()
	
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.room_error.connect(_on_room_error)
	
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

func _on_online_menu_pressed() -> void:
	_play_swoosh()
	main_selection.visible = false
	online_lobby.visible = true
	host_section.visible = false
	join_section.visible = false
	NetworkManager.connect_to_server()
	_update_server_status()

func _on_back_to_main_pressed() -> void:
	_play_swoosh()
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_back_to_selection_pressed() -> void:
	_play_swoosh()
	NetworkManager.disconnect_game()
	main_selection.visible = true
	online_lobby.visible = false
	host_section.visible = false
	join_section.visible = false

# --- HOST LOGIC ---
func _on_host_tab_pressed() -> void:
	_play_swoosh()
	host_section.visible = true
	join_section.visible = false
	room_code_label.text = "KOD ALINIYOR..."
	host_status_label.text = "⏳ Sunucudan oda kodu alınıyor..."
	NetworkManager.create_room()

func _on_room_created(code: String) -> void:
	room_code_label.text = "ODA KODU: %s" % code
	host_status_label.text = "📢 Arkadaşına bu kodu ver!\nKatıldığında maç otomatik başlar..."

# --- JOIN LOGIC ---
func _on_join_tab_pressed() -> void:
	_play_swoosh()
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
