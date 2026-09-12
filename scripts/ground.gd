extends Node2D
class_name Ground

signal bird_hit

@export var speed: float = 120.0

@onready var base1: Sprite2D = $Base1
@onready var base2: Sprite2D = $Base2

var is_moving: bool = true
const BASE_WIDTH: float = 336.0

func _ready() -> void:
	if base1 and base2:
		base1.position.x = BASE_WIDTH / 2.0
		base2.position.x = BASE_WIDTH + (BASE_WIDTH / 2.0)

func _physics_process(delta: float) -> void:
	if not is_moving:
		return
	
	base1.position.x -= speed * delta
	base2.position.x -= speed * delta
	
	if base1.position.x <= -BASE_WIDTH / 2.0:
		base1.position.x = base2.position.x + BASE_WIDTH
	
	if base2.position.x <= -BASE_WIDTH / 2.0:
		base2.position.x = base1.position.x + BASE_WIDTH

func stop() -> void:
	is_moving = false

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is Bird:
		bird_hit.emit()
		body.die()
