extends Node2D
class_name CloudsManager

class Cloud:
	var position: Vector2
	var speed: float
	var size: Vector2
	var opacity: float

var clouds: Array[Cloud] = []

func _ready() -> void:
	clouds.append(_create_cloud(Vector2(40.0, 55.0), 16.0, Vector2(50.0, 22.0), 0.55))
	clouds.append(_create_cloud(Vector2(140.0, 105.0), 26.0, Vector2(62.0, 25.0), 0.70))
	clouds.append(_create_cloud(Vector2(230.0, 70.0), 20.0, Vector2(44.0, 18.0), 0.50))
	clouds.append(_create_cloud(Vector2(300.0, 135.0), 32.0, Vector2(56.0, 24.0), 0.65))

func _create_cloud(pos: Vector2, spd: float, sz: Vector2, op: float) -> Cloud:
	var c = Cloud.new()
	c.position = pos
	c.speed = spd
	c.size = sz
	c.opacity = op
	return c

func _process(delta: float) -> void:
	for c in clouds:
		c.position.x -= c.speed * delta
		if c.position.x < -80.0:
			c.position.x = 310.0 + randf_range(0.0, 40.0)
			c.position.y = randf_range(45.0, 155.0)
	queue_redraw()

func _draw() -> void:
	for c in clouds:
		var col = Color(1.0, 1.0, 1.0, c.opacity)
		var w = c.size.x
		var h = c.size.y
		var pos = c.position
		draw_circle(pos + Vector2(w * 0.25, h * 0.5), h * 0.45, col)
		draw_circle(pos + Vector2(w * 0.50, h * 0.35), h * 0.55, col)
		draw_circle(pos + Vector2(w * 0.75, h * 0.5), h * 0.45, col)
		draw_rect(Rect2(pos.x + w * 0.15, pos.y + h * 0.4, w * 0.7, h * 0.5), col)
