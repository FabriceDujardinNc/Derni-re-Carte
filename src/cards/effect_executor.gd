class_name EffectExecutor
extends RefCounted
## EffectExecutor — interprète les effets data-driven des cartes.
##
## Chaque carte JSON porte une liste d'effets ({"type": ..., paramètres...}).
## Ajouter un type d'effet = ajouter une branche ici, sans toucher au reste.
## Types supportés par le prototype :
##   damage  {amount}              — dégâts immédiats
##   heal    {amount}              — soin immédiat
##   shield  {amount}              — bouclier absorbant les prochains dégâts
##   dot     {dps, duration}       — dégâts sur la durée (poison, brûlure...)
##   fake    {message}             — faux indice public, aucun effet réel
##   doom    {min_delay, max_delay}— mort différée humoristique (Carte du Destin)

## `user` = le lanceur pour les cartes ciblées (drain, échange…) ; sinon null.
static func apply(character, card: Dictionary, user = null) -> void:
	var card_name: String = card.get("name", "???")
	for effect in card.get("effects", []):
		match effect.get("type", ""):
			"damage":
				character.health.take_damage(int(effect.get("amount", 0)), card_name)
			"heal":
				character.health.heal(int(effect.get("amount", 0)))
			"shield":
				character.health.add_shield(int(effect.get("amount", 0)))
			"dot":
				character.status.add_dot(card_name, float(effect.get("dps", 1.0)), float(effect.get("duration", 5.0)))
			"fake":
				EventBus.fake_event.emit(effect.get("message", "Un bruit étrange retentit…"))
			"doom":
				character.status.add_doom(float(effect.get("min_delay", 30.0)), float(effect.get("max_delay", 60.0)))
			"curse":
				# Malédiction : les soins ne prennent plus (info PRIVÉE — délicieux).
				var curse_duration := float(effect.get("duration", 20.0))
				character.health.block_healing(curse_duration)
				EventBus.log_private.emit(character,
					"👻 Maudit : les soins ne prennent plus sur toi pendant %d s…" % int(curse_duration))
			"guardian":
				character.health.guardian = true
				EventBus.log_private.emit(character,
					"👼 Un ange veille sur toi : la prochaine mort ne sera pas la tienne.")
			"electric":
				character.health.take_damage(int(effect.get("amount", 12)), "Électrocution")
			"gas":
				# Le gaz touche le piocheur ET ses deux voisins de table.
				var dps := float(effect.get("dps", 2.0))
				var duration := float(effect.get("duration", 5.0))
				character.status.add_dot(card_name, dps, duration)
				var seats: Array = Net.characters
				var index := seats.find(character)
				if index >= 0 and seats.size() > 2:
					for offset in [-1, 1]:
						var neighbor = seats[(index + offset + seats.size()) % seats.size()]
						if neighbor != character and is_instance_valid(neighbor) and neighbor.is_alive():
							neighbor.status.add_dot(card_name + " (voisin)", dps, duration)
					EventBus.log_public.emit("☣️ Le gaz se répand sur les voisins de %s !"
						% character.display_name)
			"lucky":
				match randi() % 4:
					0:
						character.health.heal(30)
						EventBus.log_private.emit(character, "☘️ Chanceux : +30 PV !")
					1:
						character.health.add_shield(25)
						EventBus.log_private.emit(character, "☘️ Chanceux : bouclier de 25 !")
					2:
						character.points += 2
						EventBus.points_changed.emit(character, character.points)
						EventBus.log_private.emit(character, "☘️ Chanceux : +2 points d'audace !")
					_:
						EventBus.log_private.emit(character, "☘️ …rien. La chance est capricieuse.")
			"drain":
				# Vampirisme : les PV volés reviennent au lanceur.
				var drained := int(effect.get("amount", 12))
				character.health.take_damage(drained, card_name)
				if user != null and user != character and user.is_alive():
					user.health.heal(drained)
			"swap_hp":
				# Échange Vital : les deux vitalités permutent. Brutal et hilarant.
				if user != null and user != character and user.is_alive() and character.is_alive():
					var user_hp: int = user.health.hp
					user.health.set_hp(character.health.hp)
					character.health.set_hp(user_hp)
					EventBus.log_public.emit("🔄 %s ÉCHANGE sa vitalité avec %s !"
						% [user.display_name, character.display_name])
			_:
				push_warning("EffectExecutor : type d'effet inconnu : %s" % [effect])
