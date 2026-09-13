extends CharacterBody2D
class_name StickmanRunner

signal jumped(runner: StickmanRunner)

const GRAVITY: float = 1100.0
const JUMP_VEL: float = -400.0
const MAX_FALL: float = 650.0

var racer_name: String = "BOT"
var body_color: Color = Color.WHITE
var is_player: bool = false
var racing: bool = false
var finished: bool = false
var finish_time: float = 0.0
var race_time: float = 0.0
var run_speed: float = 140.0
var speed_factor: float = 1.0
var run_phase: float = 0.0
var respawn_pos: Vector2 = Vector2.ZERO
var anticipate: float = 95.0
var coyote: float = 0.0
var jump_buffer: float = 0.0

var gap_ray: RayCast2D
var wall_ray: RayCast2D

func setup(p_name: String, color: Color, player: bool, speed: float, anticipate_dist: float) -> void:
	racer_name = p_name
	body_color = color
	is_player = player
	run_speed = speed
	anticipate = anticipate_dist

func _ready() -> void:
	add_to_group("racers")
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 7.0
	capsule.height = 30.0
	shape.shape = capsule
	shape.position = Vector2(0, -16)
	add_child(shape)

	gap_ray = RayCast2D.new()
	gap_ray.position = Vector2(10, -2)
	gap_ray.target_position = Vector2(anticipate, 70)
	gap_ray.collision_mask = 1
	add_child(gap_ray)

	wall_ray = RayCast2D.new()
	wall_ray.position = Vector2(8, -8)
	wall_ray.target_position = Vector2(anticipate * 0.75, 0)
	wall_ray.collision_mask = 1
	add_child(wall_ray)

	var tag := Label.new()
	tag.text = racer_name
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", Color.WHITE)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 3)
	tag.position = Vector2(-20, -54)
	tag.z_index = 5
	add_child(tag)

func start_race() -> void:
	racing = true
	finished = false
	race_time = 0.0
	velocity = Vector2.ZERO

func press_jump() -> void:
	jump_buffer = 0.1

func release_jump() -> void:
	if velocity.y < -120.0:
		velocity.y *= 0.45

func do_respawn() -> void:
	position = respawn_pos
	velocity = Vector2.ZERO
	coyote = 0.0
	jump_buffer = 0.0

func _physics_process(delta: float) -> void:
	if not racing:
		return
	if finished:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
		queue_redraw()
		return

	race_time += delta
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	if is_on_floor():
		coyote = 0.08
	else:
		coyote -= delta
	jump_buffer -= delta

	if not is_player:
		_bot_brain()

	if jump_buffer > 0.0 and coyote > 0.0:
		velocity.y = JUMP_VEL
		jump_buffer = 0.0
		coyote = 0.0
		jumped.emit(self)

	velocity.x = run_speed * speed_factor
	move_and_slide()
	run_phase += delta * (6.0 + absf(velocity.x) / 14.0)
	queue_redraw()

	if position.y > 640.0:
		do_respawn()

func _bot_brain() -> void:
	if not is_on_floor():
		return
	wall_ray.target_position.x = anticipate * 0.75
	gap_ray.target_position.x = anticipate
	wall_ray.force_raycast_update()
	gap_ray.force_raycast_update()
	if wall_ray.is_colliding():
		press_jump()
		return
	if not gap_ray.is_colliding():
		press_jump()

func _draw() -> void:
	var dark := body_color.darkened(0.45)
	var air := not is_on_floor()
	# Kafa
	draw_circle(Vector2(0, -32), 7.0, dark)
	draw_circle(Vector2(0, -32), 5.5, body_color)
	# Gövde
	draw_line(Vector2(0, -26), Vector2(0, -12), dark, 5.0)
	draw_line(Vector2(0, -26), Vector2(0, -12), body_color, 3.0)
	var s1 = sin(run_phase)
	var s2 = sin(run_phase + PI)
	var arm_f: Vector2
	var arm_b: Vector2
	var leg_f: Vector2
	var leg_b: Vector2
	if air:
		arm_f = Vector2(9, -30)
		arm_b = Vector2(-9, -28)
		leg_f = Vector2(8, -4)
		leg_b = Vector2(-6, -6)
	else:
		arm_f = Vector2(10.0 * s1, -14.0 + 4.0 * absf(s2))
		arm_b = Vector2(10.0 * s2, -14.0 + 4.0 * absf(s1))
		leg_f = Vector2(10.0 * s1, 0)
		leg_b = Vector2(10.0 * s2, 0)
	# Kollar
	draw_line(Vector2(0, -22), arm_f, dark, 4.0)
	draw_line(Vector2(0, -22), arm_f, body_color, 2.5)
	draw_line(Vector2(0, -22), arm_b, dark, 4.0)
	draw_line(Vector2(0, -22), arm_b, body_color, 2.5)
	# Bacaklar
	draw_line(Vector2(0, -12), leg_f, dark, 4.0)
	draw_line(Vector2(0, -12), leg_f, body_color, 2.5)
	draw_line(Vector2(0, -12), leg_b, dark, 4.0)
	draw_line(Vector2(0, -12), leg_b, body_color, 2.5)
