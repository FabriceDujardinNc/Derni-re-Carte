class_name TavernCat
extends Node3D
## Fripouille, le chat de la taverne. Purement décoratif : il erre entre les
## tables, s'arrête, repart, miaule parfois. C'est lui, la vie du décor.

const WALK_SPEED := 1.1

func _ready() -> void:
	_build_visuals()
	_wander()

func _build_visuals() -> void:
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.18, 0.17, 0.19)
	fur.roughness = 1.0

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.09
	body_mesh.height = 0.38
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = fur
	body.rotation_degrees = Vector3(90, 0, 0)  # allongé, à l'horizontale.
	body.position = Vector3(0, 0.14, 0)
	add_child(body)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.085
	head_mesh.height = 0.17
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = fur
	head.position = Vector3(0, 0.24, -0.22)
	add_child(head)

	for side in [-1.0, 1.0]:
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius = 0.005
		ear_mesh.bottom_radius = 0.03
		ear_mesh.height = 0.07
		var ear := MeshInstance3D.new()
		ear.mesh = ear_mesh
		ear.material_override = fur
		ear.position = Vector3(0.045 * side, 0.32, -0.22)
		add_child(ear)

	var tail_mesh := CapsuleMesh.new()
	tail_mesh.radius = 0.022
	tail_mesh.height = 0.3
	var tail := MeshInstance3D.new()
	tail.mesh = tail_mesh
	tail.material_override = fur
	tail.position = Vector3(0, 0.24, 0.22)
	tail.rotation_degrees = Vector3(-40, 0, 0)
	add_child(tail)

## Errance sans fin : marche en arc (jamais à travers la table), pause, repart.
func _wander() -> void:
	while is_inside_tree():
		var a_from := atan2(position.x, position.z)
		var r_from := Vector2(position.x, position.z).length()
		var a_to := randf() * TAU
		var r_to := randf_range(5.0, 8.8)
		var duration := absf(angle_difference(a_from, a_to)) * maxf(r_from, r_to) / WALK_SPEED + 0.4
		var tween := create_tween()
		tween.tween_method(_walk_step.bind(a_from, a_to, r_from, r_to), 0.0, 1.0, duration)
		await tween.finished
		if not is_inside_tree():
			return
		await get_tree().create_timer(randf_range(2.0, 7.0)).timeout
		if not is_inside_tree():
			return
		if randf() < 0.25:
			Audio.play_at("miaou", global_position + Vector3(0, 0.3, 0), -8.0, 12.0)

func _walk_step(t: float, a_from: float, a_to: float, r_from: float, r_to: float) -> void:
	var angle := lerp_angle(a_from, a_to, t)
	var radius := lerpf(r_from, r_to, t)
	var next := Vector3(sin(angle) * radius, 0, cos(angle) * radius)
	if next.distance_to(position) > 0.02:
		look_at(next, Vector3.UP)
		position = next
