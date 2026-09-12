extends Node2D

enum GameState { READY, PLAYING, GAME_OVER }

@onready var bird1: Bird = $Bird1
@onready var bird2: Bird = $Bird2
@onready var ground: Ground = $Ground
@onready var pipe_spawner: PipeSpawner = $PipeSpawner
@onready var pipes_container: Node2D = $PipesContainer
@onready var camera: Camera2D = $Camera2D
@onready var audio_manager: Node = $AudioManager

@onready var ui_start: Control = $VersusUI/StartScreen
@onready var ui_playing: Control = $VersusUI/PlayingScreen
@onready var ui_game_over: Control = $VersusUI/GameOverScreen
@onready var ghost_banner: Label = $VersusUI/GhostBanner
@onready var p1_score_label: Label = $VersusUI/PlayingScreen/P1Score
@onready var p2_score_label: Label = $VersusUI/PlayingScreen/P2Score

@onready var result_title: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ResultTitle
@onready var result_subtitle: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ResultSubtitle
@onready var p1_rank_label: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P1Box/P1RankLabel
@onready var p1_score_big: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P1Box/P1ScoreBig
@onready var p1_status_tag: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P1Box/P1StatusTag
@onready var p2_rank_label: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P2Box/P2RankLabel
@onready var p2_score_big: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P2Box/P2ScoreBig
@onready var p2_status_tag: Label = $VersusUI/GameOverScreen/Card/Margin/VBox/ScoresRow/P2Box/P2StatusTag

var state: GameState = GameState.READY
var p1_score: int = 0
var p2_score: int = 0

var p1_alive: bool = true
var p2_alive: bool = true
var can_restart: bool = false

func _ready() -> void:
	if bird1:
		bird1.set_skin("yellow")
		bird1.set_player_tag("P1", Color(1.0, 0.9, 0.2))
		bird1.died.connect(_on_bird1_died)
	
	if bird2:
		bird2.set_skin("blue")
		bird2.set_player_tag("P2", Color(0.3, 0.75, 1.0))
		bird2.died.connect(_on_bird2_died)
	
	if pipe_spawner:
		pipe_spawner.pipe_spawned.connect(_on_pipe_spawned)
	
	ui_start.visible = true
	ui_playing.visible = false
	ui_game_over.visible = false
	if ghost_banner:
		ghost_banner.visible = false
	
	_update_scores_ui()

func _unhandled_input(event: InputEvent) -> void:
	var p1_input = false
	var p2_input = false
	
	if event.is_action_pressed("flap_p1"):
		p1_input = true
	elif event.is_action_pressed("flap_p2"):
		p2_input = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == 1:
		var half_screen = get_viewport_rect().size.x / 2.0
		if event.position.x < half_screen:
			p1_input = true
		else:
			p2_input = true
	elif event is InputEventScreenTouch and event.pressed:
		var half_screen = get_viewport_rect().size.x / 2.0
		if event.position.x < half_screen:
			p1_input = true
		else:
			p2_input = true
	
	if state == GameState.READY:
		if p1_input or p2_input:
			start_game(p1_input, p2_input)
	elif state == GameState.PLAYING:
		if p1_input and bird1 and (p1_alive or bird1.is_ghost):
			bird1.flap()
			audio_manager.play_wing()
		if p2_input and bird2 and (p2_alive or bird2.is_ghost):
			bird2.flap()
			audio_manager.play_wing()
	elif state == GameState.GAME_OVER:
		if can_restart and (p1_input or p2_input):
			restart_match()

func start_game(p1_start: bool, p2_start: bool) -> void:
	state = GameState.PLAYING
	ui_start.visible = false
	ui_playing.visible = true
	
	bird1.start_flying()
	bird2.start_flying()
	
	if not p1_start:
		bird1.velocity.y = -180.0
	if not p2_start:
		bird2.velocity.y = -180.0
	
	audio_manager.play_wing()
	if audio_manager.has_method("play_bgm"):
		audio_manager.play_bgm()
	
	pipe_spawner.start()

func _on_pipe_spawned(pipe: PipePair) -> void:
	pipes_container.add_child(pipe)
	pipe.score_awarded.connect(_on_pipe_score_awarded)
	pipe.perfect_score_awarded.connect(func(_pos): _on_pipe_score_awarded())

func _on_pipe_score_awarded() -> void:
	if state != GameState.PLAYING:
		return
	if p1_alive:
		p1_score += 1
	if p2_alive:
		p2_score += 1
	_update_scores_ui()
	audio_manager.play_point()

func _on_bird1_died() -> void:
	if not p1_alive:
		return
	p1_alive = false
	audio_manager.play_hit()
	
	if p2_alive:
		bird1.turn_into_ghost()
		show_ghost_notification("👻 1. OYUNCU (P1) ELENDİ!\nHayalet olarak uçuyor, P2 devam ediyor!")
	else:
		_check_game_over()

func _on_bird2_died() -> void:
	if not p2_alive:
		return
	p2_alive = false
	audio_manager.play_hit()
	
	if p1_alive:
		bird2.turn_into_ghost()
		show_ghost_notification("👻 2. OYUNCU (P2) ELENDİ!\nHayalet olarak uçuyor, P1 devam ediyor!")
	else:
		_check_game_over()

func show_ghost_notification(msg: String) -> void:
	if ghost_banner:
		ghost_banner.text = msg
		ghost_banner.visible = true
		ghost_banner.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_property(ghost_banner, "modulate:a", 0.0, 0.8)
		tween.tween_callback(func(): ghost_banner.visible = false)

func _check_game_over() -> void:
	if not p1_alive and not p2_alive:
		get_tree().create_timer(0.6).timeout.connect(end_game)

func end_game() -> void:
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
	
	var diff = abs(p1_score - p2_score)
	if p1_score > p2_score:
		result_title.text = "👑 1. OYUNCU (P1) KAZANDI! 👑"
		result_title.modulate = Color(1.0, 0.9, 0.2)
		result_subtitle.text = "🔥 %d Puan Farkla Kazandı!" % diff
		
		p1_rank_label.text = "👑 1. SIRA"
		p1_rank_label.modulate = Color(1.0, 0.9, 0.2)
		p1_status_tag.text = "🏆 KAZANAN"
		p1_status_tag.modulate = Color(0.4, 1.0, 0.4)
		
		p2_rank_label.text = "2. SIRA"
		p2_rank_label.modulate = Color(0.7, 0.7, 0.7)
		p2_status_tag.text = "💀 ELENDİ"
		p2_status_tag.modulate = Color(1.0, 0.4, 0.4)
		audio_manager.play_point()
	elif p2_score > p1_score:
		result_title.text = "👑 2. OYUNCU (P2) KAZANDI! 👑"
		result_title.modulate = Color(0.3, 0.75, 1.0)
		result_subtitle.text = "🔥 %d Puan Farkla Kazandı!" % diff
		
		p2_rank_label.text = "👑 1. SIRA"
		p2_rank_label.modulate = Color(0.3, 0.75, 1.0)
		p2_status_tag.text = "🏆 KAZANAN"
		p2_status_tag.modulate = Color(0.4, 1.0, 0.4)
		
		p1_rank_label.text = "2. SIRA"
		p1_rank_label.modulate = Color(0.7, 0.7, 0.7)
		p1_status_tag.text = "💀 ELENDİ"
		p1_status_tag.modulate = Color(1.0, 0.4, 0.4)
		audio_manager.play_point()
	else:
		result_title.text = "🤝 DOSTLUK KAZANDI! 🤝"
		result_title.modulate = Color(0.4, 0.85, 1.0)
		result_subtitle.text = "Nefes kesen maç berabere bitti!"
		
		p1_rank_label.text = "1. SIRA"
		p1_rank_label.modulate = Color(0.4, 0.85, 1.0)
		p1_status_tag.text = "🤝 BERABERE"
		p1_status_tag.modulate = Color(0.4, 0.85, 1.0)
		
		p2_rank_label.text = "1. SIRA"
		p2_rank_label.modulate = Color(0.4, 0.85, 1.0)
		p2_status_tag.text = "🤝 BERABERE"
		p2_status_tag.modulate = Color(0.4, 0.85, 1.0)
	
	p1_score_big.text = str(p1_score)
	p2_score_big.text = str(p2_score)
	
	ui_playing.visible = false
	ui_game_over.visible = true
	
	get_tree().create_timer(0.5).timeout.connect(func():
		can_restart = true
	)

func _update_scores_ui() -> void:
	if p1_score_label:
		var tag = " (HAYALET)" if not p1_alive else ""
		p1_score_label.text = "P1: %d%s" % [p1_score, tag]
	if p2_score_label:
		var tag = " (HAYALET)" if not p2_alive else ""
		p2_score_label.text = "P2: %d%s" % [p2_score, tag]

func restart_match() -> void:
	audio_manager.play_swoosh()
	get_tree().reload_current_scene()

func go_to_main_menu() -> void:
	audio_manager.play_swoosh()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
