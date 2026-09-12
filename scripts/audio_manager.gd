extends Node

var wing_player: AudioStreamPlayer
var point_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var die_player: AudioStreamPlayer
var swoosh_player: AudioStreamPlayer

var bgm_player: AudioStreamPlayer
var boss_music_player: AudioStreamPlayer

func _ready() -> void:
	_init_players()
	_setup_loop(bgm_player)
	_setup_loop(boss_music_player)

func _init_players() -> void:
	if not wing_player:
		wing_player = get_node_or_null("Wing") as AudioStreamPlayer
	if not point_player:
		point_player = get_node_or_null("Point") as AudioStreamPlayer
	if not hit_player:
		hit_player = get_node_or_null("Hit") as AudioStreamPlayer
	if not die_player:
		die_player = get_node_or_null("Die") as AudioStreamPlayer
	if not swoosh_player:
		swoosh_player = get_node_or_null("Swoosh") as AudioStreamPlayer
	if not bgm_player:
		bgm_player = get_node_or_null("BGM") as AudioStreamPlayer
	if not boss_music_player:
		boss_music_player = get_node_or_null("BossMusic") as AudioStreamPlayer

func _setup_loop(player: AudioStreamPlayer) -> void:
	if not player or not player.stream:
		return
	if player.stream is AudioStreamWAV:
		var wav = player.stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	elif player.stream is AudioStreamOggVorbis:
		var ogg = player.stream as AudioStreamOggVorbis
		ogg.loop = true

func play_bgm() -> void:
	_init_players()
	if boss_music_player and boss_music_player.playing:
		boss_music_player.stop()
	
	if bgm_player and not bgm_player.playing:
		bgm_player.volume_db = -10.0
		bgm_player.play()

func play_boss_music() -> void:
	_init_players()
	if bgm_player and bgm_player.playing:
		bgm_player.stop()
	
	if boss_music_player and not boss_music_player.playing:
		boss_music_player.volume_db = -8.0
		boss_music_player.play()

func fade_back_to_bgm() -> void:
	_init_players()
	if boss_music_player and boss_music_player.playing:
		var tween = create_tween()
		if tween:
			tween.tween_property(boss_music_player, "volume_db", -30.0, 0.5)
			tween.tween_callback(boss_music_player.stop)
		else:
			boss_music_player.stop()
	
	if bgm_player:
		bgm_player.volume_db = -30.0
		bgm_player.play()
		var tween = create_tween()
		if tween:
			tween.tween_property(bgm_player, "volume_db", -10.0, 0.5)
		else:
			bgm_player.volume_db = -10.0

func stop_music() -> void:
	_init_players()
	if bgm_player and bgm_player.playing:
		bgm_player.stop()
	if boss_music_player and boss_music_player.playing:
		boss_music_player.stop()

func play_wing() -> void:
	_init_players()
	if wing_player:
		wing_player.play()

func play_point() -> void:
	_init_players()
	if point_player:
		point_player.play()

func play_hit() -> void:
	_init_players()
	if hit_player:
		hit_player.play()

func play_die() -> void:
	_init_players()
	if die_player:
		die_player.play()

func play_swoosh() -> void:
	_init_players()
	if swoosh_player:
		swoosh_player.play()
