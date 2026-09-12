extends Node2D
class_name MechaBoss

signal health_changed(current_hp: int, max_hp: int)
signal defeated
signal shoot_projectile(spawn_pos: Vector2)
signal spawn_bomb(spawn_pos: Vector2)

enum State { ENTERING, ATTACKING, OVERHEAT, DEAD }

@export var max_health: int = 3

@onready var visual: Node2D = $Visual
@onready var core_eye: Polygon2D = $Visual/CoreEye
@onready var thruster_particles: CPUParticles2D = $Visual/Thrusters
@onready var steam_particles: CPUParticles2D = $Visual/SteamParticles
@onready var explosion_particles: CPUParticles2D = $ExplosionParticles
@onready var hit_box: Area2D = $HitBox

var health: int = 3
var state: State = State.ENTERING
var hover_time: float = 0.0
var base_y: float = 230.0
var attack_timer: float = 1.8
var shots_fired: int = 0
var overheat_timer: float = 0.0

func _ready() -> void:
	add_to_group("boss")
	health = max_health
	position = Vector2(340.0, base_y)
	if steam_particles:
		steam_particles.emitting = false
	if hit_box and not hit_box.body_entered.is_connected(_on_hit_box_body_entered):
		hit_box.body_entered.connect(_on_hit_box_body_entered)

func _physics_process(delta: float) -> void:
	match state:
		State.ENTERING:
			position.x = move_toward(position.x, 215.0, 100.0 * delta)
			if position.x <= 216.0:
				state = State.ATTACKING
				health_changed.emit(health, max_health)
		
		State.ATTACKING:
			hover_time += delta * 2.2
			position.y = base_y + sin(hover_time) * 55.0
			
			attack_timer -= delta
			if attack_timer <= 0.0:
				fire_attack()
				attack_timer = 2.4
		
		State.OVERHEAT:
			hover_time += delta * 1.2
			position.y = base_y + sin(hover_time) * 20.0
			
			overheat_timer -= delta
			if overheat_timer <= 0.0:
				end_overheat()
		
		State.DEAD:
			pass

func fire_attack() -> void:
	if state != State.ATTACKING:
		return
	
	shots_fired += 1
	
	# Eye charge flash
	if core_eye:
		core_eye.color = Color(1.0, 1.0, 0.2, 1.0)
		var tween = create_tween()
		tween.tween_property(core_eye, "color", Color(1.0, 0.2, 0.1, 1.0), 0.25)
	
	var spawn_pos = global_position + Vector2(-30.0, 0.0)
	shoot_projectile.emit(spawn_pos)
	
	# After 2 shots, enter overheat vulnerability
	if shots_fired >= 2:
		start_overheat()

func start_overheat() -> void:
	state = State.OVERHEAT
	overheat_timer = 3.6
	shots_fired = 0
	
	if steam_particles:
		steam_particles.emitting = true
	
	if core_eye:
		core_eye.color = Color(0.3, 0.8, 1.0, 1.0)
	
	# Spawn interactive bomb for the player to counter-attack
	var bomb_y = randf_range(160.0, 310.0)
	spawn_bomb.emit(Vector2(190.0, bomb_y))

func end_overheat() -> void:
	if state != State.OVERHEAT:
		return
	state = State.ATTACKING
	attack_timer = 1.6
	if steam_particles:
		steam_particles.emitting = false
	if core_eye:
		core_eye.color = Color(1.0, 0.2, 0.1, 1.0)

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	
	# Hit flash & recoil
	var tween = create_tween()
	tween.tween_property(visual, "modulate", Color(2.5, 2.5, 2.5, 1.0), 0.08)
	tween.tween_property(visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	position.x += 12.0
	
	if health <= 0:
		die()

func die() -> void:
	state = State.DEAD
	if steam_particles:
		steam_particles.emitting = false
	if thruster_particles:
		thruster_particles.emitting = false
	if explosion_particles:
		explosion_particles.emitting = true
	
	defeated.emit()
	
	var tween = create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.45)
	tween.tween_callback(queue_free)

func stop() -> void:
	set_physics_process(false)

func _on_hit_box_body_entered(body: Node2D) -> void:
	if body is Bird and state != State.DEAD and not body.is_dead:
		body.hit_by_obstacle()
