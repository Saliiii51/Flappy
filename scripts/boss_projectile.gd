extends Area2D
class_name BossProjectile

@export var speed: float = 160.0

@onready var visual: Node2D = $Visual

var is_active: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	position.x -= speed * delta
	if position.x < -50.0:
		queue_free()

func stop() -> void:
	is_active = false
	set_physics_process(false)

func _on_body_entered(body: Node2D) -> void:
	if body is Bird and not body.is_dead:
		is_active = false
		var absorbed = body.hit_by_obstacle()
		# Small pop animation
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 0.1)
		tween.tween_callback(queue_free)
