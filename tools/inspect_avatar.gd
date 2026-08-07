# Outil de debug : liste les nœuds du modèle importé.
# Usage : godot --headless --path . --script res://tools/inspect_avatar.gd
extends SceneTree

func _init() -> void:
	var scene: Node = load("res://assets/models/avatar_test.glb").instantiate()
	print("RACINE : ", scene.name, " (", scene.get_class(), ")")
	for child in scene.get_children():
		print("  - ", child.name, " (", child.get_class(), ") pos=", child.position,
			" scale=", child.scale)
	quit()
