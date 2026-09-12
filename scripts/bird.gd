extends CharacterBody2D
class_name Bird

signal died
signal shield_absorbed
signal double_score_toggled(active: bool)

@export var gravity: float = 900.0
@export var jump_impulse: float = -280.0
@export var max_fall_speed: float = 450.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var flap_particles: CPUParticles2D = $FlapParticles
@onready var death_particles: CPUParticles2D = $DeathParticles
@onready var shield_visual: Node2D = $ShieldVisual
@onready var star_aura: Node2D = $StarAura

var is_active: bool = false
var is_dead: bool = false
var is_ghost: bool = false
var idle_time: float = 0.0
var idle_start_y: float = 0.0

var current_skin: String = "yellow"
var has_shield: bool = false
var is_double_score: bool = false
var double_score_time: float = 0.0

var is_remote: bool = false
var target_remote_y: float = 0.0
var target_remote_rot: float = 0.0

func set_player_tag(tag_text: String, tag_color: Color = Color.WHITE) -> void:
	var label = get_node_or_null("PlayerTag") as Label
	if label:
		label.text = tag_text
		label.visible = (tag_text != "")
		label.modulate = tag_color

func sync_remote_state(remote_y: float, remote_rot: float) -> void:
	target_remote_y = remote_y
	target_remote_rot = remote_rot

func _ready() -> void:
	idle_start_y = position.y
	set_skin(current_skin)
	if shield_visual:
		shield_visual.visible = false
	if star_aura:
		star_aura.visible = false

func set_skin(skin_name: String) -> void:
	current_skin = skin_name
	if not animated_sprite:
		return
	
	var anim_name = "fly_" + skin_name
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)
	else:
		animated_sprite.play("fly_yellow")
	
	if death_particles:
		match skin_name:
			"blue":
				death_particles.color = Color(0.25, 0.65, 1.0, 1.0)
			"red":
				death_particles.color = Color(0.95, 0.25, 0.25, 1.0)
			_:
				death_particles.color = Color(0.95, 0.85, 0.2, 1.0)

func start_flying() -> void:
	is_active = true
	flap()

func flap() -> void:
	if is_dead and not is_ghost:
		return
	velocity.y = jump_impulse
	rotation_degrees = -25.0
	
	# Squash & stretch juice
	scale = Vector2(0.82, 1.24)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if flap_particles:
		flap_particles.restart()

func activate_shield() -> void:
	has_shield = true
	if shield_visual:
		shield_visual.visible = true

func hit_by_obstacle() -> bool:
	if is_ghost:
		return false
	if has_shield:
		has_shield = false
		if shield_visual:
			shield_visual.visible = false
		shield_absorbed.emit()
		return true
	die()
	return false

func activate_double_score() -> void:
	is_double_score = true
	double_score_time = 8.0
	if star_aura:
		star_aura.visible = true
	double_score_toggled.emit(true)

func turn_into_ghost() -> void:
	is_ghost = true
	is_dead = false
	collision_layer = 0
	collision_mask = 0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	modulate = Color(0.75, 0.95, 1.0, 0.5)
	if animated_sprite:
		animated_sprite.play()
	velocity.y = jump_impulse
	rotation_degrees = -20.0
	var label = get_node_or_null("PlayerTag") as Label
	if label:
		label.text = "👻 " + label.text.replace("👻", "").strip_edges()
		label.modulate = Color(0.7, 0.95, 1.0, 0.9)

func reset_from_ghost() -> void:
	is_ghost = false
	is_dead = false
	collision_layer = 1
	collision_mask = 1
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	modulate = Color(1.0, 1.0, 1.0, 1.0)

func die() -> void:
	if is_dead or is_ghost:
		return
	is_dead = true
	
	# Death impact squish
	scale = Vector2(1.30, 0.75)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.20)
	
	if animated_sprite:
		animated_sprite.stop()
	if death_particles:
		death_particles.restart()
	if shield_visual:
		shield_visual.visible = false
	if star_aura:
		star_aura.visible = false
	is_double_score = false
	double_score_toggled.emit(false)
	died.emit()

func _physics_process(delta: float) -> void:
	if is_double_score:
		double_score_time -= delta
		if double_score_time <= 0.0:
			is_double_score = false
			if star_aura:
				star_aura.visible = false
			double_score_toggled.emit(false)
	
	if has_shield and shield_visual:
		shield_visual.rotation += delta * 3.0
	
	if not is_active:
		idle_time += delta * 6.0
		position.y = idle_start_y + sin(idle_time) * 4.0
		return
	
	if is_remote:
		position.y = lerpf(position.y, target_remote_y, 25.0 * delta)
		rotation_degrees = lerpf(rotation_degrees, target_remote_rot, 25.0 * delta)
		return
	
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	move_and_slide()
	if is_ghost:
		position.y = clampf(position.y, 20.0, 385.0)
	
	if not is_dead:
		if velocity.y < 0:
			rotation_degrees = move_toward(rotation_degrees, -25.0, 450.0 * delta)
		else:
			rotation_degrees = move_toward(rotation_degrees, 80.0, 320.0 * delta)
	else:
		rotation_degrees = move_toward(rotation_degrees, 90.0, 500.0 * delta)
