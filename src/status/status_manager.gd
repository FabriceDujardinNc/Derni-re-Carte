class_name StatusManager
extends Node
## StatusManager — effets sur la durée portés par un personnage.
##
## Gère les DoT (poison, brûlure...) et la mort différée de la Carte du Destin.
## Chaque statut est un simple Dictionary : facile à sérialiser plus tard
## pour la réplication réseau ou la sauvegarde.

## Mises en scène absurdes de la Carte du Destin (game design : mourir doit être drôle).
const DOOM_SCENES: Array[String] = [
	"…un piano à queue tombe du plafond sur %s ! 🎹",
	"…la foudre frappe %s sous un ciel parfaitement dégagé ! ⚡",
	"…une météorite de taille modeste aplatit %s ! ☄️",
	"…des extraterrestres visiblement pressés embarquent %s ! 🛸",
	"…un trou noir de poche avale %s puis disparaît, gêné. 🕳️",
]

var character  ## Le CharacterBase parent (non typé pour éviter une référence circulaire).

var _statuses: Array[Dictionary] = []

func _ready() -> void:
	character = get_parent()

## Dégâts sur la durée : `dps` PV par seconde pendant `duration` secondes.
func add_dot(id: String, dps: float, duration: float) -> void:
	_statuses.append({"kind": "dot", "id": id, "dps": dps, "time_left": duration, "tick": 0.0})
	EventBus.status_applied.emit(character, id)

## Mort différée : rien pendant un délai aléatoire, puis catastrophe absurde.
func add_doom(min_delay: float, max_delay: float) -> void:
	_statuses.append({"kind": "doom", "time_left": randf_range(min_delay, max_delay)})
	EventBus.status_applied.emit(character, "💀 Destin scellé…")

## Purge tous les statuts (fin de l'échauffement d'avant-partie).
func clear_all() -> void:
	_statuses.clear()

func _process(delta: float) -> void:
	if _statuses.is_empty() or not character.is_alive():
		return
	# Parcours à rebours pour pouvoir retirer les statuts expirés en itérant.
	for i in range(_statuses.size() - 1, -1, -1):
		var s: Dictionary = _statuses[i]
		s.time_left -= delta
		match s.kind:
			"dot":
				s.tick += delta
				while s.tick >= 1.0 and character.is_alive():
					s.tick -= 1.0
					character.health.take_damage(int(round(s.dps)), s.id)
			"doom":
				if s.time_left <= 0.0:
					var scene: String = DOOM_SCENES.pick_random()
					EventBus.log_public.emit("💀 Soudain, " + scene % character.display_name)
					character.health.take_damage(999, "Carte du Destin")
		if s.time_left <= 0.0:
			_statuses.remove_at(i)
