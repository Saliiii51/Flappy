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
	
	game_over_panel.visible = false
	ghost_banner.visible = false
	countdown_label.visible = true
	
	_update_scores_ui()
	_start_countdown()

func _start_countdown() -> void:
	state = GameState.COUNTDOWN
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
	state = GameState.PLAYING
	my_bird.start_flying()
	opponent_bird.is_active = true
	
	if audio_manager.has_method("play_bgm"):
		audio_manager.play_bgm()
	
	pipe_spawner.start()

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
