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

static func apply(character, card: Dictionary) -> void:
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
			_:
				push_warning("EffectExecutor : type d'effet inconnu : %s" % [effect])
