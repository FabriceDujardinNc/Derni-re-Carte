extends Node3D
## Billard jouable : vraie physique (les billes roulent et rebondissent),
## 4 poches aux coins, +1 point d'audace par bille empochée.
## On y joue DEBOUT : s'approcher, viser une bille, clic = frappe dans la
## direction du regard. En réseau, la physique tourne chez l'hôte et les
## positions sont synchronisées (billes gelées côté client).

const TABLE_SIZE := Vector2(2.2, 1.3)  # plateau (x, z)
const TABLE_HEIGHT := 0.8
const BALL_RADIUS := 0.06
const STRIKE_FORCE := 1.4
const SYNC_INTERVAL := 0.1

var _balls: Array[RigidBody3D] = []
var _last_striker = null
var _sync_accumulator := 0.0

func _ready() -> void:
	add_to_group("billiard")
	_build_table()
	_spawn_balls()
	if Net.client_mode():
		for ball in _balls:
			ball.freeze = true  # marionnettes : les positions viennent de l'hôte.

# ---------------------------------------------------------------- Construction

func _build_table() -> void:
	var felt := Color(0.1, 0.32, 0.5)  # feutre bleu : se distingue de la table de jeu.
	var wood := Color(0.28, 0.17, 0.11)
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.65
	bounce.friction = 0.35

	# Plateau visuel + collision.
	_add_box(Vector3(TABLE_SIZE.x + 0.3, 0.14, TABLE_SIZE.y + 0.3),
		Vector3(0, TABLE_HEIGHT - 0.07, 0), wood)
	_add_box(Vector3(TABLE_SIZE.x, 0.02, TABLE_SIZE.y),
		Vector3(0, TABLE_HEIGHT + 0.01, 0), felt)
	var surface := StaticBody3D.new()
	surface.physics_material_override = bounce
	var surface_shape := CollisionShape3D.new()
	var surface_box := BoxShape3D.new()
	surface_box.size = Vector3(TABLE_SIZE.x + 0.3, 0.14, TABLE_SIZE.y + 0.3)
	surface_shape.shape = surface_box
	surface_shape.position = Vector3(0, TABLE_HEIGHT - 0.05, 0)
	surface.add_child(surface_shape)
	add_child(surface)

	# Pieds.
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			_add_box(Vector3(0.12, TABLE_HEIGHT, 0.12),
				Vector3(corner_x * (TABLE_SIZE.x / 2.0), TABLE_HEIGHT / 2.0 - 0.07,
					corner_z * (TABLE_SIZE.y / 2.0)), wood)

	# Bandes (visuel + collision, rebond garanti).
	var rails := [
		[Vector3(TABLE_SIZE.x + 0.3, 0.1, 0.08), Vector3(0, TABLE_HEIGHT + 0.06, TABLE_SIZE.y / 2.0 + 0.11)],
		[Vector3(TABLE_SIZE.x + 0.3, 0.1, 0.08), Vector3(0, TABLE_HEIGHT + 0.06, -TABLE_SIZE.y / 2.0 - 0.11)],
		[Vector3(0.08, 0.1, TABLE_SIZE.y + 0.3), Vector3(TABLE_SIZE.x / 2.0 + 0.11, TABLE_HEIGHT + 0.06, 0)],
		[Vector3(0.08, 0.1, TABLE_SIZE.y + 0.3), Vector3(-TABLE_SIZE.x / 2.0 - 0.11, TABLE_HEIGHT + 0.06, 0)],
	]
	for rail in rails:
		_add_box(rail[0], rail[1], wood)
		var rail_body := StaticBody3D.new()
		rail_body.physics_material_override = bounce
		var rail_shape := CollisionShape3D.new()
		var rail_box := BoxShape3D.new()
		rail_box.size = rail[0]
		rail_shape.shape = rail_box
		rail_shape.position = rail[1]
		rail_body.add_child(rail_shape)
		add_child(rail_body)

	# Poches aux 4 coins : une bille qui y entre disparaît.
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			var pocket := Area3D.new()
			var pocket_shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.1
			pocket_shape.shape = sphere
			pocket.add_child(pocket_shape)
			pocket.position = Vector3(corner_x * (TABLE_SIZE.x / 2.0),
				TABLE_HEIGHT + 0.03, corner_z * (TABLE_SIZE.y / 2.0))
			pocket.body_entered.connect(_on_pocket_entered)
			add_child(pocket)
			var hole := CylinderMesh.new()
			hole.top_radius = 0.08
			hole.bottom_radius = 0.08
			hole.height = 0.015
			var hole_visual := MeshInstance3D.new()
			hole_visual.mesh = hole
			var hole_mat := StandardMaterial3D.new()
			hole_mat.albedo_color = Color(0.03, 0.03, 0.03)
			hole_visual.material_override = hole_mat
			hole_visual.position = pocket.position + Vector3(0, -0.005, 0)
			add_child(hole_visual)

func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	visual.material_override = material
	visual.position = pos
	add_child(visual)

func _spawn_balls() -> void:
	var colors := [Color(0.95, 0.95, 0.9), Color(0.85, 0.2, 0.2), Color(0.9, 0.75, 0.2),
		Color(0.25, 0.3, 0.7), Color(0.2, 0.55, 0.3)]
	for i in colors.size():
		var ball := RigidBody3D.new()
		ball.add_to_group("billiard_ball")
		ball.set_meta("index", i)
		ball.mass = 0.4
		ball.linear_damp = 0.9
		ball.angular_damp = 0.9
		var material := PhysicsMaterial.new()
		material.bounce = 0.6
		material.friction = 0.3
		ball.physics_material_override = material
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = BALL_RADIUS
		shape.shape = sphere
		ball.add_child(shape)
		var visual := MeshInstance3D.new()
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = BALL_RADIUS
		ball_mesh.height = BALL_RADIUS * 2.0
		visual.mesh = ball_mesh
		var visual_mat := StandardMaterial3D.new()
		visual_mat.albedo_color = colors[i]
		visual_mat.roughness = 0.2
		visual.material_override = visual_mat
		ball.add_child(visual)
		add_child(ball)
		_balls.append(ball)
	_reset_balls()

## Replace les billes en position de départ.
func _reset_balls() -> void:
	var spots := [Vector3(-0.6, 0, 0), Vector3(0.4, 0, 0), Vector3(0.55, 0, 0.14),
		Vector3(0.55, 0, -0.14), Vector3(0.7, 0, 0)]
	for i in _balls.size():
		var ball := _balls[i]
		ball.visible = true
		ball.freeze = Net.client_mode()
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		ball.position = spots[i] + Vector3(0, TABLE_HEIGHT + BALL_RADIUS + 0.03, 0)

# ---------------------------------------------------------------- Jeu

## Frappe une bille dans une direction (autorité uniquement).
func strike(ball: RigidBody3D, direction: Vector3, striker) -> void:
	if not ball.visible or not EventBus.match_started:
		return
	_last_striker = striker
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	ball.apply_central_impulse(flat * STRIKE_FORCE)
	Audio.play_at("pop", ball.global_position, -6.0)

func strike_index(index: int, direction: Vector3, striker) -> void:
	if index >= 0 and index < _balls.size():
		strike(_balls[index], direction, striker)

func _on_pocket_entered(body: Node3D) -> void:
	if not body is RigidBody3D or not body.is_in_group("billiard_ball") or not body.visible:
		return
	if Net.client_mode():
		return  # l'hôte décide.
	body.visible = false
	body.freeze = true
	body.position = Vector3(0, -10, 0)  # parquée hors-jeu, prête à resservir.
	if _last_striker != null and is_instance_valid(_last_striker) and _last_striker.is_alive():
		_last_striker.points += 1
		EventBus.points_changed.emit(_last_striker, _last_striker.points)
		EventBus.log_public.emit(Lang.t("🎱 %s empoche une bille ! (+1 point d'audace)")
			% _last_striker.display_name)
	else:
		EventBus.log_public.emit(Lang.t("🎱 Une bille tombe dans la poche…"))
	# Plus qu'une bille en jeu ? On retriangule.
	var remaining := 0
	for ball in _balls:
		if ball.visible:
			remaining += 1
	if remaining <= 1:
		await get_tree().create_timer(2.0).timeout
		_reset_balls()

# ---------------------------------------------------------------- Réseau

func _process(delta: float) -> void:
	if not Net.active or not Net.is_server:
		return
	_sync_accumulator += delta
	if _sync_accumulator < SYNC_INTERVAL:
		return
	_sync_accumulator = 0.0
	var moving := false
	for ball in _balls:
		if ball.visible and ball.linear_velocity.length_squared() > 0.001:
			moving = true
			break
	if moving:
		var states: Array = []
		for i in _balls.size():
			states.append([i, _balls[i].position, _balls[i].visible])
		Net.broadcast_balls(states)

## Côté client : applique les positions reçues de l'hôte.
func apply_sync(states: Array) -> void:
	for state in states:
		var index: int = state[0]
		if index >= 0 and index < _balls.size():
			_balls[index].position = state[1]
			_balls[index].visible = state[2]
