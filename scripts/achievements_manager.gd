extends Node
class_name AchievementsManager

signal achievement_unlocked(id: String, info: Dictionary)

const SAVE_PATH: String = "user://flappy_save.cfg"

const ACHIEVEMENTS: Dictionary = {
	"first_flight": {
		"title": "İlk Uçuş",
		"desc": "5 puana ulaştın!",
		"icon": "🐥"
	},
	"night_owl": {
		"title": "Gece Kuşu",
		"desc": "Gece moduna geçiş yaptın!",
		"icon": "🌙"
	},
	"shield_master": {
		"title": "Kalkan Ustası",
		"desc": "Kalkanla bir boruyu parçaladın!",
		"icon": "🛡️"
	},
	"star_power": {
		"title": "Yıldız Gücü",
		"desc": "Çift puan (2X) topladın!",
		"icon": "⭐"
	},
	"perfectionist": {
		"title": "Kusursuz Pilot",
		"desc": "Tam ortadan PERFECT geçiş yaptın!",
		"icon": "🎯"
	},
	"legend": {
		"title": "Efsanevi Kuş",
		"desc": "30 puana ulaştın!",
		"icon": "👑"
	},
	"boss_slayer": {
		"title": "Canavar Avcısı",
		"desc": "Mecha-Pipe Boss'unu mağlup ettin!",
		"icon": "👹"
	},
	"storm_rider": {
		"title": "Fırtına Binicisi",
		"desc": "Rüzgarı atlatıp uçmaya devam ettin!",
		"icon": "🌪️"
	},
	"fog_navigator": {
		"title": "Sis Gezgini",
		"desc": "Siste yolunu buldun!",
		"icon": "🌫️"
	}
}

var unlocked_ids: Array[String] = []

func _ready() -> void:
	load_achievements()

func is_unlocked(id: String) -> bool:
	return unlocked_ids.has(id)

func unlock(id: String) -> void:
	if not ACHIEVEMENTS.has(id):
		return
	if is_unlocked(id):
		return
	
	unlocked_ids.append(id)
	save_achievements()
	achievement_unlocked.emit(id, ACHIEVEMENTS[id])

func load_achievements() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		if config.has_section("achievements"):
			for key in config.get_section_keys("achievements"):
				if config.get_value("achievements", key, false) and not unlocked_ids.has(key):
					unlocked_ids.append(key)

func save_achievements() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		config = ConfigFile.new()
	
	for id in unlocked_ids:
		config.set_value("achievements", id, true)
	
	config.save(SAVE_PATH)
