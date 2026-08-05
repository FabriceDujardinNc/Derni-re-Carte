extends Node3D
## Le Barman. Il lave ses verres derrière son bar, et le bordel autour de la
## table l'exaspère (regard noir permanent). SURTOUT, NE PAS LE DÉRANGER.
##
## Easter egg à escalade : chaque clic d'un joueur fait monter SA jauge de
## provocation. Quatre avertissements… au cinquième clic, le barman explose
## et emporte le provocateur plus deux innocents. On ne dérange pas le barman.

var _pokes := {}  ## par joueur (id d'instance) → nombre de provocations.
var _time := 0.0
var _scrub_arm: Node3D
var _body: MeshInstance3D

func _ready() -> void:
	add_to_group("barman")
	_build_visuals()

func _build_visuals() -> void:
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color(0.85, 0.83, 0.78)
	shirt.roughness = 1.0
	var apron_mat := StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.25, 0.2, 0.16)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.42
	body_mesh.height = 1.6
	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	_body.material_override = shirt
	_body.position = Vector3(0, 0.8, 0)
	add_child(_body)

	# Tablier de travail.
	var apron := BoxMesh.new()
	apron.size = Vector3(0.55, 0.7, 0.1)
	var apron_visual := MeshInstance3D.new()
	apron_visual.mesh = apron
	apron_visual.material_override = apron_mat
	apron_visual.position = Vector3(0, 0.85, -0.38)
	add_child(apron_visual)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.6
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = shirt
	head.position = Vector3(0, 1.78, 0)
	add_child(head)

	# Yeux + sourcils FURIEUX (très inclinés vers le nez) + moustache.
	for side in [-1.0, 1.0]:
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.05
		eye_mesh.height = 0.1
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = dark
		eye.position = Vector3(0.11 * side, 1.82, -0.26)
		add_child(eye)
		var brow := BoxMesh.new()
		brow.size = Vector3(0.14, 0.03, 0.02)
		var brow_visual := MeshInstance3D.new()
		brow_visual.mesh = brow
		brow_visual.material_override = dark
		brow_visual.position = Vector3(0.11 * side, 1.9, -0.27)
		brow_visual.rotation_degrees = Vector3(0, 0, -28.0 * side)  # colère.
		add_child(brow_visual)
	var mustache := BoxMesh.new()
	mustache.size = Vector3(0.22, 0.05, 0.03)
	var mustache_visual := MeshInstance3D.new()
	mustache_visual.mesh = mustache
	mustache_visual.material_override = dark
	mustache_visual.position = Vector3(0, 1.7, -0.28)
	add_child(mustache_visual)

	# Bras qui frotte un verre, inlassablement.
	_scrub_arm = Node3D.new()
	_scrub_arm.position = Vector3(0.4, 1.35, -0.15)
	add_child(_scrub_arm)
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.09
	arm_mesh.height = 0.5
	var arm := MeshInstance3D.new()
	arm.mesh = arm_mesh
	arm.material_override = shirt
	arm.position = Vector3(0, -0.25, 0)
	_scrub_arm.add_child(arm)
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = 0.07
	glass_mesh.bottom_radius = 0.05
	glass_mesh.height = 0.14
	var glass := MeshInstance3D.new()
	glass.mesh = glass_mesh
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.8, 0.9, 0.95, 0.6)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = glass_mat
	glass.position = Vector3(0, -0.55, 0)
	_scrub_arm.add_child(glass)

	# Corps de collision : c'est LUI qu'on clique (à ses risques et périls).
	var collision := StaticBody3D.new()
	collision.add_to_group("barman_body")
	collision.set_meta("barman", self)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.2
	shape.shape = capsule
	shape.position = Vector3(0, 1.1, 0)
	collision.add_child(shape)
	add_child(collision)

func _process(delta: float) -> void:
	_time += delta
	# Frottage de verre énergique (il évacue sa rage comme il peut).
	_scrub_arm.rotation.x = 0.8 + sin(_time * 8.0) * 0.3
	_scrub_arm.rotation.z = sin(_time * 4.0) * 0.1

## Un joueur ose le déranger. Escalade personnelle, dénouement collectif.
## Ne s'exécute que côté autorité (hôte / solo).
func poke(clicker) -> void:
	if clicker == null or not clicker.is_alive():
		return
	if not EventBus.match_started:
		EventBus.log_private.emit(clicker, "🍺 Le barman t'ignore pendant le tutoriel.")
		return
	var key: int = clicker.get_instance_id()
	var count: int = _pokes.get(key, 0) + 1
	_pokes[key] = count
	_shake()
	match count:
		1:
			EventBus.log_private.emit(clicker, "🍺 Le barman lève les yeux : « Ne m'énerve pas. »")
		2:
			EventBus.log_private.emit(clicker, "🍺 « J'ai dit : ne. m'énerve. PAS. »")
		3:
			EventBus.log_private.emit(clicker, "🍺 « ATTENTION. Le prochain coup, je m'énerve. »")
		4:
			EventBus.log_private.emit(clicker,
				"🍺 « DERNIER AVERTISSEMENT. Encore un clic et je t'emporte, toi et deux autres. »")
		_:
			_rage(clicker)
			_pokes[key] = 0

## La coupe est pleine : le provocateur et deux innocents y passent.
func _rage(clicker) -> void:
	EventBus.log_public.emit("💥 LE BARMAN EXPLOSE DE RAGE ! Il jette ses verres à travers la salle !")
	var victims: Array = [clicker]
	var others := get_tree().get_nodes_in_group("characters").filter(
		func(c) -> bool: return c != clicker and c.is_alive())
	others.shuffle()
	for i in mini(2, others.size()):
		victims.append(others[i])
	for victim in victims:
		Projectile.throw(get_tree().current_scene,
			global_position + Vector3(0, 1.6, 0),
			victim.global_position + Vector3(0, 1.3, 0),
			func() -> void:
				if is_instance_valid(victim):
					victim.health.take_damage(999, "Colère du barman"))

func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(_body, "position:x", 0.05, 0.05)
	tween.tween_property(_body, "position:x", -0.05, 0.05)
	tween.tween_property(_body, "position:x", 0.0, 0.05)
