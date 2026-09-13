extends Node2D

enum GameState { COUNTDOWN, PLAYING, GAME_OVER }

@onready var my_bird: Bird = $MyBird
@onready var opponent_bird: Bird = $OpponentBird
@onready var ground: Ground = $Ground
@onready var pipe_spawner: PipeSpawner = $PipeSpawner
@onready var pipes_container: Node2D = $PipesContainer
@onready var audio_manager: Node = $AudioManager

@onready var countdown_label: Label = $BattleUI/CountdownLabel
@onready var my_score_label: Label = $BattleUI/PlayingScreen/MyScoreLabel
@onready var opp_score_label: Label = $BattleUI/PlayingScreen/OppScoreLabel
@onready var ghost_banner: Label = $BattleUI/GhostBanner

@onready var game_over_panel: Control = $BattleUI/GameOverScreen
@onready var result_title: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ResultTitle
@onready var result_subtitle: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ResultSubtitle
@onready var series_score_label: Label = $BattleUI/PlayingScreen/SeriesScoreLabel
@onready var series_score_banner: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/SeriesScoreBanner
@onready var history_list: VBoxContainer = $BattleUI/GameOverScreen/Card/Margin/VBox/HistoryBox/HistoryScroll/HistoryList

@onready var my_rank_label: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/MyBox/MyRankLabel
@onready var my_name_label: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/MyBox/MyNameLabel
@onready var my_score_big: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/MyBox/MyScoreBig
@onready var my_status_tag: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/MyBox/MyStatusTag
@onready var opp_rank_label: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/OppBox/OppRankLabel
@onready var opp_name_label: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/OppBox/OppNameLabel
@onready var opp_score_big: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/OppBox/OppScoreBig
@onready var opp_status_tag: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/ScoresRow/OppBox/OppStatusTag
@onready var rematch_status: Label = $BattleUI/GameOverScreen/Card/Margin/VBox/RematchStatus
@onready var rematch_btn: Button = $BattleUI/GameOverScreen/Card/Margin/VBox/RematchBtn

var state: GameState = GameState.COUNTDOWN
var my_score: int = 0
var opp_score: int = 0

var my_alive: bool = true
var opp_alive: bool = true
var my_final_score: int = 0
var opp_final_score: int = 0

var my_ready: bool = false
var opp_ready: bool = false

var my_name: String = "SEN"
var opp_name: String = "RAKİP"

var versus_card: PanelContainer
var versus_my_line: Label
var versus_opp_line: Label
var my_best: int = -1
var opp_best: int = -1
var opp_games: int = 0
var opp_badge_count: int = -1

var taunt_row: HBoxContainer
var chat_modal: Control
var chat_list: VBoxContainer
var chat_input: LineEdit
var chat_open_btn: Button
var has_unread_chat: bool = false

const TAUNTS: Array[String] = ["😎", "🔥", "💀", "👋"]
const QUICK_CHAT: Array[String] = ["GG! 🏆", "Tekrar? 🔄", "😎", "🔥", "Of! 😅"]

var sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.033 # ~30 updates per second

func _ready() -> void:
	if NetworkManager.current_seed != 0:
		seed(NetworkManager.current_seed)
	var is_host = NetworkManager.is_host()
	
	my_name = NetworkManager.my_player_name if NetworkManager.my_player_name != "" else "SEN"
	opp_name = NetworkManager.opponent_player_name if NetworkManager.opponent_player_name != "" else "RAKİP"
	
	if is_host:
		my_bird.position = Vector2(65, 220)
		my_bird.set_skin("yellow")
		my_bird.set_player_tag(my_name, Color(1.0, 0.9, 0.2))
		
		opponent_bird.position = Vector2(105, 220)
		opponent_bird.set_skin("blue")
		opponent_bird.set_player_tag(opp_name, Color(0.3, 0.75, 1.0))
	else:
		my_bird.position = Vector2(105, 220)
		my_bird.set_skin("blue")
		my_bird.set_player_tag(my_name, Color(0.3, 0.75, 1.0))
		
		opponent_bird.position = Vector2(65, 220)
		opponent_bird.set_skin("yellow")
		opponent_bird.set_player_tag(opp_name, Color(1.0, 0.9, 0.2))
	
	opponent_bird.is_remote = true
	opponent_bird.collision_layer = 0
	opponent_bird.collision_mask = 0
	if opponent_bird.collision_shape:
		opponent_bird.collision_shape.disabled = true
	
	my_bird.died.connect(_on_my_bird_died)
	if pipe_spawner:
		pipe_spawner.pipe_spawned.connect(_on_pipe_spawned)
	
	NetworkManager.opponent_bird_synced.connect(_on_opponent_bird_synced)
	NetworkManager.opponent_flapped.connect(_on_opponent_flapped)
	NetworkManager.opponent_died.connect(_on_opponent_died)
	NetworkManager.opponent_score_updated.connect(_on_opponent_score_updated)
	NetworkManager.opponent_ready.connect(_on_opponent_ready)
	NetworkManager.rematch_requested.connect(_on_rematch_requested)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.bests_received.connect(_on_bests_received)
	NetworkManager.opponent_badges_received.connect(_on_opponent_badges)
	NetworkManager.chat_received.connect(_on_chat_received)
	NetworkManager.taunt_received.connect(_on_taunt_received)

	_build_versus_card()
	_build_taunt_row()
	_build_chat_modal()
	NetworkManager.request_bests([my_name, opp_name])
	NetworkManager.send_my_badges()
	
	game_over_panel.visible = false
	ghost_banner.visible = false
	countdown_label.visible = true
	
	_update_scores_ui()
	_start_countdown()

func _start_countdown() -> void:
	state = GameState.COUNTDOWN
	if taunt_row:
		taunt_row.visible = true
	var tween = create_tween()
	
	countdown_label.text = "3"
	audio_manager.play_point()
	tween.tween_interval(1.0)
	
	tween.tween_callback(func():
		countdown_label.text = "2"
		audio_manager.play_point()
	)
	tween.tween_interval(1.0)
	
	tween.tween_callback(func():
		countdown_label.text = "1"
		audio_manager.play_point()
	)
	tween.tween_interval(1.0)
	
	tween.tween_callback(func():
		countdown_label.text = "UÇ!"
		audio_manager.play_wing()
		_start_match()
	)
	tween.tween_interval(0.6)
	tween.tween_callback(func():
		countdown_label.visible = false
	)

func _start_match() -> void:
	# Geri sayım tween'i geç ateşlenirse (iki oyuncu da ilk 3 sn'de
	# öldüyse) bitmiş maçı diriltmesin.
	if state != GameState.COUNTDOWN:
		return
	state = GameState.PLAYING
	my_bird.start_flying()
	opponent_bird.is_active = true

	if versus_card:
		versus_card.visible = false

	if audio_manager.has_method("play_bgm"):
		audio_manager.play_bgm()

	pipe_spawner.start()

func _build_versus_card() -> void:
	if versus_card:
		return
	versus_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.bg_color = Color(0.1, 0.1, 0.16, 0.88)
	style.border_color = Color(1.0, 0.85, 0.2, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	versus_card.add_theme_stylebox_override("panel", style)
	versus_card.offset_left = 34.0
	versus_card.offset_top = 118.0
	versus_card.offset_right = 254.0
	versus_card.offset_bottom = 208.0
	$BattleUI.add_child(versus_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	versus_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "⚔️ KARŞILAŞMA"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	versus_my_line = Label.new()
	versus_my_line.add_theme_font_size_override("font_size", 11)
	versus_my_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(versus_my_line)

	versus_opp_line = Label.new()
	versus_opp_line.add_theme_font_size_override("font_size", 11)
	versus_opp_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(versus_opp_line)

	_render_versus_card()

func _render_versus_card() -> void:
	if versus_my_line == null or versus_opp_line == null:
		return
	var my_txt = "%s: %s" % [my_name, ("En iyi: %d" % my_best) if my_best >= 0 else "bilgi bekleniyor..."]
	versus_my_line.text = "🟡 " + my_txt
	var opp_txt = "%s: %s" % [opp_name, ("En iyi: %d (%d maç)" % [opp_best, opp_games]) if opp_best >= 0 else "bilgi bekleniyor..."]
	if opp_badge_count >= 0:
		opp_txt += " 🏅%d" % opp_badge_count
	versus_opp_line.text = "🔵 " + opp_txt

func _on_bests_received(entries: Array) -> void:
	for e in entries:
		if not (e is Dictionary):
			continue
		var pname = str(e.get("name", ""))
		if pname == my_name:
			my_best = int(e.get("best", 0))
		elif pname == opp_name:
			opp_best = int(e.get("best", 0))
			opp_games = int(e.get("games", 0))
	_render_versus_card()

func _on_opponent_badges(badges: Array) -> void:
	opp_badge_count = badges.size()
	_render_versus_card()

# --- TEPKİLER (taunt) + SOHBET (chat) ---
func _build_taunt_row() -> void:
	if taunt_row:
		return
	taunt_row = HBoxContainer.new()
	taunt_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	taunt_row.offset_top = -158.0
	taunt_row.offset_bottom = -124.0
	taunt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	taunt_row.add_theme_constant_override("separation", 8)
	taunt_row.visible = false
	$BattleUI.add_child(taunt_row)
	for icon in TAUNTS:
		var b := Button.new()
		b.text = icon
		b.custom_minimum_size = Vector2(34, 34)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_taunt_pressed.bind(icon))
		taunt_row.add_child(b)

func _on_taunt_pressed(icon: String) -> void:
	NetworkManager.send_taunt(icon)
	_show_taunt_popup(icon, my_bird)

func _on_taunt_received(icon: String, _sender: String) -> void:
	_show_taunt_popup(icon, opponent_bird)
	audio_manager.play_point()

func _show_taunt_popup(icon: String, above: Node2D) -> void:
	if above == null:
		return
	var lbl := Label.new()
	lbl.text = icon
	lbl.add_theme_font_size_override("font_size", 26)
	$BattleUI.add_child(lbl)
	lbl.position = Vector2(clampf(above.position.x - 13.0, 8.0, 240.0), clampf(above.position.y - 70.0, 30.0, 380.0))
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 36.0, 0.9)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.2)
	tween.chain().tween_callback(lbl.queue_free)

func _build_chat_modal() -> void:
	if chat_modal:
		return
	chat_modal = Control.new()
	chat_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_modal.visible = false
	$BattleUI.add_child(chat_modal)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_modal.add_child(dim)
	dim.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			chat_modal.visible = false
	)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.bg_color = Color(0.12, 0.12, 0.18, 0.97)
	style.border_color = Color(0.4, 0.85, 1.0, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	panel.offset_left = 30.0
	panel.offset_top = 130.0
	panel.offset_right = 258.0
	panel.offset_bottom = 390.0
	chat_modal.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "💬 ODA SOHBETİ"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	chat_list = VBoxContainer.new()
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.add_theme_constant_override("separation", 2)
	scroll.add_child(chat_list)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	quick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(quick_row)
	for q in QUICK_CHAT:
		var qb := Button.new()
		qb.text = q
		qb.add_theme_font_size_override("font_size", 9)
		qb.focus_mode = Control.FOCUS_NONE
		qb.pressed.connect(_on_quick_chat_pressed.bind(q))
		quick_row.add_child(qb)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Mesaj yaz..."
	chat_input.max_length = 60
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(func(_t): _on_chat_send_pressed())
	input_row.add_child(chat_input)

	var send_btn := Button.new()
	send_btn.text = "➤"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(_on_chat_send_pressed)
	input_row.add_child(send_btn)

	# Sohbet açma butonu (maç sonu kartına eklenir)
	if rematch_btn and rematch_btn.get_parent():
		chat_open_btn = Button.new()
		chat_open_btn.text = "💬 SOHBET"
		chat_open_btn.add_theme_font_size_override("font_size", 11)
		chat_open_btn.focus_mode = Control.FOCUS_NONE
		chat_open_btn.pressed.connect(_on_chat_open_pressed)
		rematch_btn.get_parent().add_child(chat_open_btn)

func _on_quick_chat_pressed(text: String) -> void:
	_send_chat_text(text)

func _on_chat_send_pressed() -> void:
	if chat_input == null:
		return
	_send_chat_text(chat_input.text)
	chat_input.text = ""

func _send_chat_text(text: String) -> void:
	var clean = text.strip_edges()
	if clean == "":
		return
	NetworkManager.send_chat(clean)
	_append_chat("Sen", clean)

func _on_chat_received(text: String, sender: String) -> void:
	if chat_modal and chat_modal.visible:
		_append_chat(sender, text)
	else:
		has_unread_chat = true
		_refresh_chat_button()
		# Sohbet kapalıysa kısa bildirim göster
		show_ghost_notification("💬 %s: %s" % [sender, text])
	audio_manager.play_point()

func _append_chat(who: String, text: String) -> void:
	if chat_list == null:
		return
	var lbl := Label.new()
	lbl.text = "%s: %s" % [who, text]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_list.add_child(lbl)
	while chat_list.get_child_count() > 20:
		chat_list.get_child(0).queue_free()

func _on_chat_open_pressed() -> void:
	if chat_modal == null:
		return
	has_unread_chat = false
	_refresh_chat_button()
	chat_modal.visible = true
	if chat_input:
		chat_input.grab_focus()

func _refresh_chat_button() -> void:
	if chat_open_btn:
		chat_open_btn.text = "💬 SOHBET (•)" if has_unread_chat else "💬 SOHBET"

func _physics_process(delta: float) -> void:
	if state == GameState.PLAYING and my_bird:
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			NetworkManager.send_bird_sync(my_bird.position.y, my_bird.rotation_degrees)

func _unhandled_input(event: InputEvent) -> void:
	if state == GameState.PLAYING:
		if event.is_action_pressed("flap") or \
		   (event is InputEventMouseButton and event.pressed and event.button_index == 1) or \
		   (event is InputEventScreenTouch and event.pressed):
			if my_bird:
				my_bird.flap()
				audio_manager.play_wing()
				NetworkManager.send_player_flap()

func _on_pipe_spawned(pipe: PipePair) -> void:
	pipes_container.add_child(pipe)
	pipe.score_awarded.connect(_on_pipe_score_awarded)
	pipe.perfect_score_awarded.connect(func(_pos): _on_pipe_score_awarded())

func _on_pipe_score_awarded() -> void:
	if state != GameState.PLAYING:
		return
	if my_alive:
		my_score += 1
		my_final_score = my_score
		_update_scores_ui()
		audio_manager.play_point()
		NetworkManager.send_score_update(my_score)

func _on_my_bird_died() -> void:
	if not my_alive:
		return
	my_alive = false
	my_final_score = my_score
	audio_manager.play_hit()
	NetworkManager.send_player_died(my_final_score)
	
	if opp_alive:
		my_bird.turn_into_ghost()
		show_ghost_notification("👻 ELENDİN! (HAYALET OLARAK UÇMAYA DEVAM EDEBİLİRSİN)\nSkorun: %d | Rakip hala uçuyor..." % my_final_score)
	else:
		_check_match_end()

func _on_opponent_bird_synced(_peer_id: int, pos_y: float, rot: float) -> void:
	if opponent_bird:
		opponent_bird.sync_remote_state(pos_y, rot)

func _on_opponent_flapped(_peer_id: int) -> void:
	if opponent_bird:
		opponent_bird.flap()

func _on_opponent_died(_peer_id: int, final_score: int) -> void:
	if not opp_alive:
		return
	opp_alive = false
	opp_final_score = final_score
	opp_score = final_score
	_update_scores_ui()
	audio_manager.play_hit()
	
	if my_alive:
		if opponent_bird:
			opponent_bird.turn_into_ghost()
		show_ghost_notification("💀 RAKİP ELENDİ! (%d PUAN)\n🏆 Rekorunu kırmak için uçmaya devam et!" % final_score)
	else:
		_check_match_end()

func _on_opponent_score_updated(new_score: int) -> void:
	opp_score = new_score
	opp_final_score = new_score
	_update_scores_ui()

func show_ghost_notification(msg: String) -> void:
	if ghost_banner:
		ghost_banner.text = msg
		ghost_banner.visible = true
		ghost_banner.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_interval(3.5)
		tween.tween_property(ghost_banner, "modulate:a", 0.0, 0.8)
		tween.tween_callback(func(): ghost_banner.visible = false)

func _on_player_disconnected(_peer_id: int) -> void:
	if state == GameState.PLAYING:
		opp_alive = false
		end_match_forfeit("RAKİP OYUNDAN AYRILDI! (HÜKMEN KAZANDIN 👑)")

func _check_match_end() -> void:
	if not my_alive and not opp_alive:
		get_tree().create_timer(0.6).timeout.connect(end_match)

func end_match() -> void:
	if state == GameState.GAME_OVER:
		return
	state = GameState.GAME_OVER
	
	pipe_spawner.stop()
	ground.stop()
	for child in pipes_container.get_children():
		if child.has_method("stop"):
			child.stop()
	
	if audio_manager.has_method("stop_music"):
		audio_manager.stop_music()
	
	if ghost_banner:
		ghost_banner.visible = false

	if versus_card:
		versus_card.visible = false

	if taunt_row:
		taunt_row.visible = false
	
	# Record match in session history
	NetworkManager.record_match(my_final_score, opp_final_score)
	
	if series_score_banner:
		series_score_banner.text = "🏆 GENEL SERİ: %s %d - %d %s" % [my_name, NetworkManager.my_wins, NetworkManager.opp_wins, opp_name]
	
	_populate_history_list()
	
	my_name_label.text = my_name
	opp_name_label.text = opp_name
	my_score_big.text = str(my_final_score)
	opp_score_big.text = str(opp_final_score)
	
	my_ready = false
	opp_ready = false
	if rematch_btn:
		rematch_btn.disabled = false
		rematch_btn.text = "🔄 TEKRAR OYNA"
	if rematch_status:
		rematch_status.visible = false
	
	var diff = abs(my_final_score - opp_final_score)
	if my_final_score > opp_final_score:
		result_title.text = "👑 %s KAZANDI! 👑" % my_name.to_upper()
		result_title.modulate = Color(1.0, 0.85, 0.2)
		result_subtitle.text = "🔥 %d Puan Farkla Kazandın!" % diff
		
		my_rank_label.text = "👑 1. SIRA"
		my_rank_label.modulate = Color(1.0, 0.85, 0.2)
		my_status_tag.text = "🏆 KAZANAN"
		my_status_tag.modulate = Color(0.4, 1.0, 0.4)
		
		opp_rank_label.text = "2. SIRA"
		opp_rank_label.modulate = Color(0.7, 0.7, 0.7)
		opp_status_tag.text = "💀 ELENDİ"
		opp_status_tag.modulate = Color(1.0, 0.4, 0.4)
		audio_manager.play_point()
		
	elif opp_final_score > my_final_score:
		result_title.text = "👑 %s KAZANDI! 👑" % opp_name.to_upper()
		result_title.modulate = Color(1.0, 0.35, 0.35)
		result_subtitle.text = "%s %d Puan Farkla Kazandı" % [opp_name, diff]
		
		my_rank_label.text = "2. SIRA"
		my_rank_label.modulate = Color(0.7, 0.7, 0.7)
		my_status_tag.text = "💀 ELENDİ"
		my_status_tag.modulate = Color(1.0, 0.4, 0.4)
		
		opp_rank_label.text = "👑 1. SIRA"
		opp_rank_label.modulate = Color(1.0, 0.85, 0.2)
		opp_status_tag.text = "🏆 KAZANAN"
		opp_status_tag.modulate = Color(0.4, 1.0, 0.4)
		audio_manager.play_die()
		
	else:
		result_title.text = "🤝 BERABERE!"
		result_title.modulate = Color(0.4, 0.85, 1.0)
		result_subtitle.text = "Efsanevi Mücadele! (%d - %d)" % [my_final_score, opp_final_score]
		
		my_rank_label.text = "1. SIRA"
		my_rank_label.modulate = Color(0.4, 0.85, 1.0)
		my_status_tag.text = "🤝 BERABERE"
		my_status_tag.modulate = Color(0.4, 0.85, 1.0)
		
		opp_rank_label.text = "1. SIRA"
		opp_rank_label.modulate = Color(0.4, 0.85, 1.0)
		opp_status_tag.text = "🤝 BERABERE"
		opp_status_tag.modulate = Color(0.4, 0.85, 1.0)
	
	game_over_panel.visible = true

func _populate_history_list() -> void:
	if not history_list:
		return
	for child in history_list.get_children():
		child.queue_free()
	
	for entry in NetworkManager.session_history:
		var item = Label.new()
		var winner_str = ""
		var col = Color(0.9, 0.9, 0.9)
		if entry.winner == "me":
			winner_str = " (%s 👑)" % my_name
			col = Color(1.0, 0.88, 0.3)
		elif entry.winner == "opp":
			winner_str = " (%s 👑)" % opp_name
			col = Color(0.4, 0.8, 1.0)
		else:
			winner_str = " (Berabere 🤝)"
			col = Color(0.8, 0.8, 0.8)
		
		item.text = "%d. Maç: %s %d - %d %s%s" % [
			entry.match_num,
			my_name,
			entry.my_score,
			entry.opp_score,
			opp_name,
			winner_str
		]
		item.add_theme_font_size_override("font_size", 9)
		item.add_theme_color_override("font_color", col)
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		history_list.add_child(item)

func end_match_forfeit(banner_text: String) -> void:
	end_match()
	result_title.text = "👑 HÜKMİ ZAFER!"
	result_subtitle.text = banner_text

func _update_scores_ui() -> void:
	if my_score_label:
		var tag = " (HAYALET)" if not my_alive else ""
		my_score_label.text = "%s: %d%s" % [my_name, my_score, tag]
	if opp_score_label:
		var tag = " (HAYALET)" if not opp_alive else ""
		opp_score_label.text = "%s: %d%s" % [opp_name, opp_score, tag]
	if series_score_label:
		series_score_label.text = "%s %d - %d %s" % [my_name, NetworkManager.my_wins, NetworkManager.opp_wins, opp_name]

func request_rematch() -> void:
	if my_ready:
		return
	my_ready = true
	audio_manager.play_swoosh()
	NetworkManager.send_rematch_ready()
	_update_rematch_ui()

func _on_opponent_ready() -> void:
	opp_ready = true
	_update_rematch_ui()

func _update_rematch_ui() -> void:
	if not rematch_btn or not rematch_status:
		return
	
	if my_ready and not opp_ready:
		rematch_btn.disabled = true
		rematch_btn.text = "✅ HAZIRSIN"
		rematch_status.text = "⏳ %s bekleniyor..." % opp_name
		rematch_status.visible = true
	elif not my_ready and opp_ready:
		rematch_btn.disabled = false
		rematch_btn.text = "🔥 %s HAZIR! TEKRAR OYNA" % opp_name.to_upper()
		rematch_status.text = "⚡ %s tekrar oynamaya hazır!" % opp_name
		rematch_status.visible = true
	elif my_ready and opp_ready:
		rematch_btn.disabled = true
		rematch_btn.text = "⏳ BAŞLIYOR..."
		rematch_status.text = "🚀 Her iki oyuncu da hazır! Başlıyor..."
		rematch_status.visible = true

func _on_rematch_requested(sync_seed: int) -> void:
	restart_match(sync_seed)

func restart_match(sync_seed: int) -> void:
	NetworkManager.current_seed = sync_seed
	seed(sync_seed)
	audio_manager.play_swoosh()
	get_tree().reload_current_scene()

func leave_to_main_menu() -> void:
	NetworkManager.disconnect_game()
	audio_manager.play_swoosh()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
