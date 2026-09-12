extends Area2D
class_name PowerUp

enum Type { SHIELD, DOUBLE_SCORE }

@export var type: Type = Type.SHIELD
@export var speed: float = 120.0

@onready var visual_root: Node2D = $VisualRoot
@onready var label: Label = $VisualRoot/Label
@onready var aura: ColorRect = $VisualRoot/Aura

var is_moving: bool = true
var time_elapsed: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	setup_visuals()

func setup_type(p_type: Type) -> void:
	type = p_type
	setup_visuals()

func setup_visuals() -> void:
	if not label or not aura:
		return
	if type == Type.SHIELD:
		label.text = "🛡️"
		aura.color = Color(0.2, 0.7, 1.0, 0.35)
	else:
		label.text = "⭐"
		aura.color = Color(1.0, 0.85, 0.1, 0.4)

func _physics_process(delta: float) -> void:
	if not is_moving:
		return
	
	position.x -= speed * delta
	
	time_elapsed += delta * 5.0
	if visual_root:
		visual_root.position.y = sin(time_elapsed) * 4.0
	
	if position.x < -60.0:
		queue_free()

func stop() -> void:
	is_moving = false

func _on_body_entered(body: Node2D) -> void:
	if body is Bird and not body.is_dead:
		if type == Type.SHIELD:
			body.activate_shield()
		elif type == Type.DOUBLE_SCORE:
			body.activate_double_score()
		
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 0.15)
		tween.tween_callback(queue_free)
