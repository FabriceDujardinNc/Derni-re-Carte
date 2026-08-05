class_name Projectile
extends Node3D
## Projectile visuel (grenade, huile chaude…) : trajectoire en cloche d'un
## joueur vers un autre, puis callback à l'impact (qui applique l'effet).
## Purement cosmétique côté physique : la cible est déjà décidée au lancer —
## simple, prévisible en réseau, et toujours drôle à regarder.

static func throw(parent: Node, from: Vector3, to: Vector3, on_hit: Callable) -> void:
	EventBus.projectile_thrown.emit(from, to)
	var projectile := Projectile.new()
	parent.add_child(projectile)

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28)
	mesh.material_override = mat
	projectile.add_child(mesh)
	projectile.global_position = from

	var tween := projectile.create_tween()
	tween.tween_method(func(t: float) -> void:
		projectile.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 1.4,
		0.0, 1.0, 0.75)
	tween.tween_callback(func() -> void:
		on_hit.call()
		projectile.queue_free())
