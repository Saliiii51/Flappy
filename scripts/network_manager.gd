extends Node

signal room_created(room_code: String)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal game_started(sync_seed: int)
signal opponent_bird_synced(peer_id: int, pos_y: float, rot: float)
signal opponent_flapped(peer_id: int)
signal opponent_died(peer_id: int, final_score: int)
signal opponent_score_updated(score: int)
signal rematch_requested(sync_seed: int)
signal opponent_ready()
signal room_error(message: String)
signal match_searching()
signal match_cancelled()
signal ranks_received(entries: Array, total: int, scope: String, week: String, champ: Dictionary)

const WS_PORT: int = 8910
const PROFILE_SAVE_PATH: String = "user://player_profile.cfg"
# İnternet yayını için backend URL'si.
# 1. Öncelik: web'de window.FLAPPY_WS_URL tanımlıysa o kullanılır
#    (index.html'e <script>window.FLAPPY_WS_URL="wss://..."</script> ekle,
#    tekrar export gerekmez).
# 2. Buraya sabit URL yazarsan her yerde o kullanılır:
const PROD_WS_URL: String = ""

var ws: WebSocketPeer = null
var current_room_code: String = ""
var is_host_player: bool = false
var is_connected_to_server: bool = false
var current_seed: int = 0

var my_player_name: String = ""
var opponent_player_name: String = "Rakip"

# Match history & series tracking for the active room session
var session_history: Array[Dictionary] = []
var my_wins: int = 0
var opp_wins: int = 0
var ties: int = 0

func get_player_name() -> String:
	if my_player_name != "":
		return my_player_name
	var config = ConfigFile.new()
	if config.load(PROFILE_SAVE_PATH) == OK:
		my_player_name = config.get_value("profile", "name", "")
	if my_player_name == "":
		my_player_name = "Oyuncu"
	return my_player_name

func has_custom_name() -> bool:
	var config = ConfigFile.new()
	if config.load(PROFILE_SAVE_PATH) == OK:
		return config.has_section_key("profile", "name")
	return false

func save_player_name(new_name: String) -> void:
	var clean = new_name.strip_edges()
	if clean.length() > 12:
		clean = clean.substr(0, 12)
	if clean == "":
		clean = "Oyuncu"
	my_player_name = clean
	var config = ConfigFile.new()
	config.set_value("profile", "name", my_player_name)
	config.save(PROFILE_SAVE_PATH)

func get_mp_stats() -> Dictionary:
	var config = ConfigFile.new()
	var wins: int = 0
	var losses: int = 0
	var tie_count: int = 0
	var total: int = 0
	if config.load(PROFILE_SAVE_PATH) == OK:
		wins = int(config.get_value("multiplayer_stats", "wins", 0))
		losses = int(config.get_value("multiplayer_stats", "losses", 0))
		tie_count = int(config.get_value("multiplayer_stats", "ties", 0))
		total = int(config.get_value("multiplayer_stats", "total_matches", wins + losses + tie_count))
	
	var rate: float = 0.0
	if total > 0:
		rate = (float(wins) / float(total)) * 100.0
	
	return {
		"wins": wins,
		"losses": losses,
		"ties": tie_count,
		"total": total,
		"win_rate": rate
	}

func record_lifetime_mp_match(winner: String) -> void:
	var config = ConfigFile.new()
	config.load(PROFILE_SAVE_PATH)
	
	var wins: int = int(config.get_value("multiplayer_stats", "wins", 0))
	var losses: int = int(config.get_value("multiplayer_stats", "losses", 0))
	var tie_count: int = int(config.get_value("multiplayer_stats", "ties", 0))
	var total: int = int(config.get_value("multiplayer_stats", "total_matches", 0)) + 1
	
	if winner == "me":
		wins += 1
	elif winner == "opp":
		losses += 1
	else:
		tie_count += 1
	
	config.set_value("multiplayer_stats", "wins", wins)
	config.set_value("multiplayer_stats", "losses", losses)
	config.set_value("multiplayer_stats", "ties", tie_count)
	config.set_value("multiplayer_stats", "total_matches", total)
	config.save(PROFILE_SAVE_PATH)

func record_match(my_score: int, opp_score: int) -> Dictionary:
	var winner = "tie"
	if my_score > opp_score:
		my_wins += 1
		winner = "me"
	elif opp_score > my_score:
		opp_wins += 1
		winner = "opp"
	else:
		ties += 1
		winner = "tie"
	
	record_lifetime_mp_match(winner)
	
	var match_num = session_history.size() + 1
	var entry = {
		"match_num": match_num,
		"my_score": my_score,
		"opp_score": opp_score,
		"winner": winner
	}
	session_history.append(entry)
	return entry

func clear_session_history() -> void:
	session_history.clear()
	my_wins = 0
	opp_wins = 0
	ties = 0

func _ready() -> void:
	get_player_name()
	connect_to_server()

func _process(_delta: float) -> void:
	if ws:
		ws.poll()
		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not is_connected_to_server:
				is_connected_to_server = true
				connected_to_server.emit()
			
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet().get_string_from_utf8()
				_handle_server_message(packet)
				
		elif state == WebSocketPeer.STATE_CLOSED:
			if is_connected_to_server:
				is_connected_to_server = false
				server_disconnected.emit()
				player_disconnected.emit(2)

func get_server_url() -> String:
	# 1) Sabit prod URL varsa direkt kullan (en basit internet yayını)
	if PROD_WS_URL != "":
		return PROD_WS_URL
	# 2) Web'de index.html üzerinden override: window.FLAPPY_WS_URL
	if OS.has_feature("web"):
		var override_url = JavaScriptBridge.eval("window.FLAPPY_WS_URL || ''", true)
		if override_url != null and str(override_url) != "" and str(override_url) != "null":
			return str(override_url)
		var web_host = JavaScriptBridge.eval("window.location.hostname", true)
		var web_proto = JavaScriptBridge.eval("window.location.protocol", true)
		var host = "127.0.0.1"
		if web_host != null and str(web_host) != "" and str(web_host) != "null":
			host = str(web_host)
		# HTTPS sayfadan ws:// açmak tarayıcıda engellenir -> wss:// şart
		var is_https = (web_proto != null and str(web_proto).begins_with("https"))
		if is_https:
			# Backend ayrı hosttaysa yukarıdaki override/PROD_WS_URL kullanılmalı.
			# Aynı hostta reverse-proxy (/ws) yoksa yine de wss dene:
			return "wss://" + host + ":" + str(WS_PORT)
		return "ws://" + host + ":" + str(WS_PORT)
	# 3) Masaüstü / LAN: yerel IP bul
	var host_local = "127.0.0.1"
	var local_ip = get_local_ip()
	if local_ip != "":
		host_local = local_ip
	return "ws://" + host_local + ":" + str(WS_PORT)

func get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	return "127.0.0.1"

func connect_to_server() -> void:
	if ws and (ws.get_ready_state() == WebSocketPeer.STATE_OPEN or ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING):
		return
	ws = WebSocketPeer.new()
	var url = get_server_url()
	var err = ws.connect_to_url(url)
	if err != OK:
		connection_failed.emit()

func create_room() -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connect_to_server()
	clear_session_history()
	send_json({"type": "create_room", "name": get_player_name()})

func join_room(code: String) -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connect_to_server()
	clear_session_history()
	send_json({"type": "join_room", "room_code": code.strip_edges(), "name": get_player_name()})

func quick_match() -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connect_to_server()
	clear_session_history()
	send_json({"type": "quick_match", "name": get_player_name()})

func cancel_quick_match() -> void:
	send_json({"type": "cancel_match"})

func is_host() -> bool:
	return is_host_player

func send_bird_sync(pos_y: float, rot: float) -> void:
	send_json({
		"type": "sync",
		"pos_y": pos_y,
		"rot": rot
	})

func send_player_flap() -> void:
	send_json({"type": "flap"})

func send_player_died(final_score: int) -> void:
	send_json({
		"type": "died",
		"score": final_score
	})

func send_score_update(score: int) -> void:
	send_json({
		"type": "score_update",
		"score": score
	})

func send_rematch_ready() -> void:
	send_json({
		"type": "rematch_ready"
	})

func send_rematch(sync_seed: int) -> void:
	send_json({
		"type": "rematch",
		"seed": sync_seed
	})

func submit_rank_score(score: int) -> void:
	if score <= 0:
		return
	send_json({
		"type": "submit_score",
		"name": get_player_name(),
		"score": score
	})

func request_top_ranks(limit: int = 10, scope: String = "all") -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connect_to_server()
	if scope != "week":
		scope = "all"
	send_json({
		"type": "get_top",
		"limit": limit,
		"scope": scope
	})

func send_json(data: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(data))

func disconnect_game() -> void:
	current_room_code = ""
	is_host_player = false
	opponent_player_name = "Rakip"
	clear_session_history()

func _handle_server_message(raw_msg: String) -> void:
	var json = JSON.parse_string(raw_msg)
	if typeof(json) != TYPE_DICTIONARY:
		return
	
	var msg_type = json.get("type", "")
	match msg_type:
		"room_created":
			current_room_code = str(json.get("room_code", ""))
			is_host_player = true
			room_created.emit(current_room_code)
			
		"game_start":
			current_room_code = str(json.get("room_code", ""))
			current_seed = int(json.get("seed", 0))
			is_host_player = bool(json.get("is_host", false))
			my_player_name = str(json.get("my_name", get_player_name()))
			opponent_player_name = str(json.get("opponent_name", "Rakip"))
			player_connected.emit(2)
			game_started.emit(current_seed)

		"match_searching":
			match_searching.emit()

		"match_cancelled":
			match_cancelled.emit()
			
		"sync":
			var pos_y = float(json.get("pos_y", 0.0))
			var rot = float(json.get("rot", 0.0))
			opponent_bird_synced.emit(2, pos_y, rot)
			
		"flap":
			opponent_flapped.emit(2)
			
		"died":
			var score = int(json.get("score", 0))
			opponent_died.emit(2, score)
			
		"score_update":
			var score = int(json.get("score", 0))
			opponent_score_updated.emit(score)
			
		"opponent_ready":
			opponent_ready.emit()
			
		"rematch_start", "rematch":
			var s = int(json.get("seed", 0))
			current_seed = s
			rematch_requested.emit(s)
			
		"opponent_left":
			player_disconnected.emit(2)

		"rank_ok":
			pass # Skor kaydedildi, ayrıca işlem gerekmiyor

		"top_ranks":
			var entries = json.get("entries", [])
			var total = int(json.get("total", 0))
			var scope = str(json.get("scope", "all"))
			var week = str(json.get("week", ""))
			var champ = json.get("champ", {})
			if typeof(entries) != TYPE_ARRAY:
				entries = []
			if typeof(champ) != TYPE_DICTIONARY:
				champ = {}
			ranks_received.emit(entries, total, scope, week, champ)
			
		"error":
			var err_msg = str(json.get("message", "Bilinmeyen hata"))
			room_error.emit(err_msg)
