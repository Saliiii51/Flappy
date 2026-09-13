extends Node

signal mission_star_earned(id: String, stars: int, info: Dictionary)

const SAVE_PATH: String = "user://flappy_missions.cfg"

const MISSIONS: Array = [
	{"id": "first_steps", "icon": "🐥", "title": "İlk Adımlar", "desc": "Uçuş tamamla", "type": "games", "goals": [1, 3, 10]},
	{"id": "score_hunter", "icon": "🎯", "title": "Skor Avcısı", "desc": "Tek uçuşta skor yap", "type": "best", "goals": [10, 25, 40]},
	{"id": "perfectionist_total", "icon": "✨", "title": "Mükemmeliyetçi", "desc": "Toplam PERFECT geçiş", "type": "perfect_total", "goals": [1, 5, 15]},
	{"id": "perfect_run", "icon": "🔥", "title": "Seri Mükemmel", "desc": "Tek uçuşta PERFECT yap", "type": "perfect_run", "goals": [1, 2, 3]},
	{"id": "shield_collector", "icon": "🛡️", "title": "Koleksiyoncu", "desc": "Kalkan topla", "type": "shield_total", "goals": [1, 5, 12]},
	{"id": "star_collector", "icon": "⭐", "title": "Yıldız Avcısı", "desc": "Yıldız topla", "type": "star_total", "goals": [1, 5, 12]},
	{"id": "boss_hunter", "icon": "👹", "title": "Boss Avcısı", "desc": "Boss yen", "type": "boss_total", "goals": [1, 3, 5]},
	{"id": "point_hoarder", "icon": "📦", "title": "Puan Biriktirici", "desc": "Toplam puan topla", "type": "total_score", "goals": [50, 200, 500]},
	{"id": "duelist", "icon": "⚔️", "title": "Düellocu", "desc": "Online maç kazan", "type": "mp_wins", "goals": [1, 5, 15]},
	{"id": "legend", "icon": "💎", "title": "Efsane", "desc": "Tek uçuşta dev skor", "type": "best", "goals": [60, 100, 150]},
	{"id": "marathon", "icon": "🎮", "title": "Maratoncu", "desc": "Çok uçuş tamamla", "type": "games", "goals": [20, 50, 100]},
	{"id": "survivor", "icon": "💥", "title": "Kurtulan", "desc": "Kalkanla darbeden kurtul", "type": "shield_break", "goals": [1, 3, 8]},
]

var games_played: int = 0
var best_score: int = 0
var total_score: int = 0
var best_perfect_run: int = 0
var total_perfects: int = 0
var boss_kills: int = 0
var shields_collected: int = 0
var stars_collected: int = 0
var shield_breaks: int = 0

func _ready() -> void:
	load_progress()

func progress_of(m: Dictionary) -> int:
	match String(m.get("type", "")):
		"games":
			return games_played
		"best":
			return best_score
		"total_score":
			return total_score
		"perfect_run":
			return best_perfect_run
		"perfect_total":
			return total_perfects
		"boss_total":
			return boss_kills
		"shield_total":
			return shields_collected
		"star_total":
			return stars_collected
		"shield_break":
			return shield_breaks
		"mp_wins":
			return NetworkManager.get_mp_stats().get("wins", 0)
	return 0

func stars_of(m: Dictionary) -> int:
	var p = progress_of(m)
	var stars = 0
	for g in m.get("goals", []):
		if p >= int(g):
			stars += 1
	return stars

func total_stars() -> int:
	var total = 0
	for m in MISSIONS:
		total += stars_of(m)
	return total

func stars_possible() -> int:
	return MISSIONS.size() * 3

func report_run(score: int, perfects: int, shields: int, stars: int, boss: bool) -> void:
	var before = _snapshot_stars()
	games_played += 1
	best_score = maxi(best_score, score)
	total_score += score
	best_perfect_run = maxi(best_perfect_run, perfects)
	total_perfects += perfects
	shields_collected += shields
	stars_collected += stars
	if boss:
		boss_kills += 1
	save_progress()
	_emit_new_stars(before)

func add_shield_break() -> void:
	var before = _snapshot_stars()
	shield_breaks += 1
	save_progress()
	_emit_new_stars(before)

func _snapshot_stars() -> Dictionary:
	var s = {}
	for m in MISSIONS:
		s[String(m.get("id", ""))] = stars_of(m)
	return s

func _emit_new_stars(before: Dictionary) -> void:
	for m in MISSIONS:
		var id = String(m.get("id", ""))
		if stars_of(m) > int(before.get(id, 0)):
			mission_star_earned.emit(id, stars_of(m), m)

func mission_info(id: String) -> Dictionary:
	for m in MISSIONS:
		if String(m.get("id", "")) == id:
			return m
	return {}

func load_progress() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	games_played = int(config.get_value("stats", "games", 0))
	best_score = int(config.get_value("stats", "best", 0))
	total_score = int(config.get_value("stats", "total", 0))
	best_perfect_run = int(config.get_value("stats", "perfect_run", 0))
	total_perfects = int(config.get_value("stats", "perfect_total", 0))
	boss_kills = int(config.get_value("stats", "boss", 0))
	shields_collected = int(config.get_value("stats", "shields", 0))
	stars_collected = int(config.get_value("stats", "stars", 0))
	shield_breaks = int(config.get_value("stats", "breaks", 0))

func save_progress() -> void:
	var config = ConfigFile.new()
	config.set_value("stats", "games", games_played)
	config.set_value("stats", "best", best_score)
	config.set_value("stats", "total", total_score)
	config.set_value("stats", "perfect_run", best_perfect_run)
	config.set_value("stats", "perfect_total", total_perfects)
	config.set_value("stats", "boss", boss_kills)
	config.set_value("stats", "shields", shields_collected)
	config.set_value("stats", "stars", stars_collected)
	config.set_value("stats", "breaks", shield_breaks)
	config.save(SAVE_PATH)
