extends Area2D
class_name BossBomb

signal hit_boss

@export var speed: float = 45.0

@onready var visual: Node2D = $Visual
@onready var label: Label = $Visual/Label

var is_launched: bool = false
var target_boss: Node2D
var float_time: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_launched:
		position.x -= speed * delta
		float_time += delta * 4.0
		if visual:
			visual.position.y = sin(float_time) * 4.0
		if position.x < -40.0:
			queue_free()
	else:
		# Rapidly fly toward Boss
		if target_boss and is_instance_valid(target_boss):
			var dir = (target_boss.global_position - global_position).normalized()
			global_position += dir * 420.0 * delta
			if global_position.distance_to(target_boss.global_position) < 25.0:
				if target_boss.has_method("take_damage"):
					target_boss.take_damage(1)
				hit_boss.emit()
				queue_free()
		else:
			position.x += 420.0 * delta
			if position.x > 360.0:
				queue_free()

func stop() -> void:
	set_physics_process(false)

func _on_body_entered(body: Node2D) -> void:
	if body is Bird and not is_launched and not body.is_dead:
		is_launched = true
		# Find the boss
		target_boss = get_tree().get_first_node_in_group("boss") as Node2D
		# Visual feedback
		scale = Vector2(1.3, 1.3)
		if label:
			label.text = "💥"
