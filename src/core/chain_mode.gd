extends Node
## Mode « Les Enchaînés » — paires SECRÈTES liées par le destin.
##
## Chacun est enchaîné à un partenaire inconnu : s'il meurt, tu meurs.
## Trois moyens de découvrir sa chaîne :
##  1. L'écho de douleur : ton partenaire encaisse → tu TRESSAILLES (visible
##     de tous !) et tu reçois un message privé ;
##  2. Le frémissement : à moins de 2 m de ton partenaire, la chaîne frémit
##     (message privé aux deux) ;
##  3. Chaque mort révèle sa chaîne publiquement — on recoupe par élimination.
## Si les derniers survivants sont enchaînés ensemble : victoire partagée.
##
## Ce nœud ne vit que chez l'HÔTE : les chaînes restent secrètes par
## construction (les clients ne reçoivent que les échos et les logs).

const ECHO_MIN_DAMAGE := 8       # en-dessous, pas d'écho (les ticks de poison restent discrets).
const ECHO_COOLDOWN_MS := 3000
const SHIVER_RANGE := 2.0
const SHIVER_PERIOD := 4.0

var groups: Array = []  ## Array de groupes (paires, ou trio si nombre impair).

var _echo_cooldowns := {}
var _shiver_accumulator := 0.0

func setup(characters: Array) -> void:
	add_to_group("chain_mode")
	var pool := characters.duplicate()
	pool.shuffle()
	groups = []
	while pool.size() >= 2:
		if pool.size() == 3:
			groups.append([pool[0], pool[1], pool[2]])  # trio de l'impair.
			break
		groups.append([pool.pop_back(), pool.pop_back()])
	for character in characters:
		EventBus.log_private.emit(character,
			"⛓️ Tu es enchaîné à quelqu'un dans cette salle… S'il meurt, tu meurs. Découvre qui, et protège-le.")
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_damaged.connect(_on_player_damaged)

func group_of(character) -> Array:
	for group in groups:
		if character in group:
			return group
	return []

## La chaîne emporte les partenaires du mort (révélation publique).
func _on_player_died(dead, _cause: String) -> void:
	for partner in group_of(dead):
		if partner != dead and partner.is_alive():
			EventBus.log_public.emit("⛓️ %s s'effondre soudain… il était enchaîné à %s !"
				% [partner.display_name, dead.display_name])
			partner.health.take_damage(999, "Chaîne du destin")

## Écho de douleur : le partenaire tressaille, visiblement.
func _on_player_damaged(victim, amount: int, _source: String) -> void:
	if amount < ECHO_MIN_DAMAGE:
		return
	var now := Time.get_ticks_msec()
	for partner in group_of(victim):
		if partner == victim or not partner.is_alive():
			continue
		var key: int = partner.get_instance_id()
		if now - int(_echo_cooldowns.get(key, 0)) < ECHO_COOLDOWN_MS:
			continue
		_echo_cooldowns[key] = now
		EventBus.chain_echo.emit(partner)
		EventBus.log_private.emit(partner,
			"🩸 Une douleur sourde te traverse… ton enchaîné vient d'encaisser.")

## Frémissement de proximité : tous les 4 s, si les partenaires sont proches.
func _process(delta: float) -> void:
	_shiver_accumulator += delta
	if _shiver_accumulator < SHIVER_PERIOD:
		return
	_shiver_accumulator = 0.0
	for group in groups:
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a = group[i]
				var b = group[j]
				if a.is_alive() and b.is_alive() \
						and a.global_position.distance_to(b.global_position) < SHIVER_RANGE:
					EventBus.log_private.emit(a, "⛓️ Ta chaîne frémit doucement…")
					EventBus.log_private.emit(b, "⛓️ Ta chaîne frémit doucement…")
