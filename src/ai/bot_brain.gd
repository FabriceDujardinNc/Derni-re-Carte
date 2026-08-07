class_name BotBrain
extends Node
## BotBrain — IA d'un joueur bot, pilotée par une personnalité.
##
## Version prototype : le bot pioche à son tour et RÉAGIT via des émotes,
## honnêtement ou en bluffant selon sa personnalité. C'est la brique de base
## du futur AI Director : les personnalités influenceront ensuite la lecture
## des autres joueurs, les accusations vocales (TTS) et les tells simulés.

enum Personality { MENTEUR, PEUREUX, AGRESSIF, CALCULATEUR, TROLL, PRUDENT }

## Difficulté globale des bots : multiplicateurs de comportement.
## aggro = fréquence d'attaque · think = vitesse de réaction (plus petit = plus vif)
## spy = zèle d'espionnage · reveal = générosité en révélations (info gratuite)
## suspicion = qualité de lecture · heal_at = seuil de soin (PV) · taunt = moqueries chat.
const DIFFICULTY := {
	"facile": {"aggro": 0.5, "think": 1.6, "spy": 0.5, "reveal": 1.6, "suspicion": 0.5, "heal_at": 30, "taunt": 0.0},
	"moyen": {"aggro": 1.0, "think": 1.0, "spy": 1.0, "reveal": 1.0, "suspicion": 1.0, "heal_at": 45, "taunt": 0.0},
	"difficile": {"aggro": 1.4, "think": 0.7, "spy": 1.3, "reveal": 0.6, "suspicion": 1.5, "heal_at": 55, "taunt": 0.06},
	"nightmare": {"aggro": 1.9, "think": 0.45, "spy": 1.6, "reveal": 0.3, "suspicion": 2.0, "heal_at": 65, "taunt": 0.14},
	"celeste": {"aggro": 2.6, "think": 0.3, "spy": 2.0, "reveal": 0.1, "suspicion": 3.0, "heal_at": 75, "taunt": 0.28},
}

const TAUNTS: Array[String] = [
	"Rien de personnel.",
	"Tu l'as bien cherché.",
	"Le barman t'aurait fait pire.",
	"C'était peut-être ton enchaîné ? Oups.",
	"Ma grand-mère bluffe mieux que toi.",
	"Tu trembles déjà ?",
	"On applaudit bien fort.",
	"Je vois TOUT.",
]

## Raccourci : paramètre de la difficulté courante.
func _d(key: String) -> float:
	var tier: Dictionary = DIFFICULTY.get(GameConfig.difficulty, DIFFICULTY["moyen"])
	return float(tier[key])

## Après un mauvais coup réussi : parfois, le bot savoure (dans le chat).
func _maybe_taunt(_victim) -> void:
	if randf() < _d("taunt"):
		character.say(Lang.t(TAUNTS.pick_random()))

## Probabilité d'afficher une émotion INVERSE de ce que le bot ressent.
const BLUFF_CHANCE := {
	Personality.MENTEUR: 0.85,
	Personality.PEUREUX: 0.1,
	Personality.AGRESSIF: 0.4,
	Personality.CALCULATEUR: 0.6,
	Personality.TROLL: 0.5,
	Personality.PRUDENT: 0.3,
}

## Émote favorite quand le bot observe la pioche d'un autre joueur.
const SPECTATE_EMOTE := {
	Personality.MENTEUR: "🤫",
	Personality.PEUREUX: "😱",
	Personality.AGRESSIF: "👎",
	Personality.CALCULATEUR: "😏",
	Personality.TROLL: "😂",
	Personality.PRUDENT: "🤫",
}

const EMOTE_GOOD: Array[String] = ["😀", "😂", "👍"]
const EMOTE_BAD: Array[String] = ["😱", "😭"]

## Probabilité de lancer une carte offensive stockée, à son tour.
const AGGRO_CHANCE := {
	Personality.MENTEUR: 0.3,
	Personality.PEUREUX: 0.15,
	Personality.AGRESSIF: 0.8,
	Personality.CALCULATEUR: 0.45,
	Personality.TROLL: 0.55,
	Personality.PRUDENT: 0.2,
}

## Probabilité de révéler volontairement sa carte piochée (+1 point d'audace).
const REVEAL_CHANCE := {
	Personality.MENTEUR: 0.05,
	Personality.PEUREUX: 0.3,
	Personality.AGRESSIF: 0.25,
	Personality.CALCULATEUR: 0.35,
	Personality.TROLL: 0.4,
	Personality.PRUDENT: 0.2,
}

## Probabilité de se retourner quand quelqu'un rôde dans son dos (protège le sac).
const PROTECT_CHANCE := {
	Personality.MENTEUR: 0.4,
	Personality.PEUREUX: 0.5,
	Personality.AGRESSIF: 0.3,
	Personality.CALCULATEUR: 0.7,
	Personality.TROLL: 0.3,
	Personality.PRUDENT: 0.8,
}

## Probabilité de se lever pour aller espionner (testée toutes les ~15 s).
const SPY_CHANCE := {
	Personality.MENTEUR: 0.5,
	Personality.PEUREUX: 0.1,
	Personality.AGRESSIF: 0.3,
	Personality.CALCULATEUR: 0.6,
	Personality.TROLL: 0.5,
	Personality.PRUDENT: 0.15,
}

var personality := Personality.PRUDENT

@onready var character: CharacterBase = get_parent()

var _my_turn := false

## LE BOT LIT LA TABLE : mémoire de suspicion par joueur. Elle monte quand
## quelqu'un stocke des cartes, l'attaque (vengeance !), ou rôde dans son dos.
## Elle guide le choix des cibles de grenades et de cailloux.
var _suspicion := {}  # instance_id -> score

func _ready() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.card_drawn.connect(_on_card_drawn)
	EventBus.card_resolved.connect(func(who, _card: Dictionary) -> void:
		if who == character:
			_my_turn = false)
	EventBus.stalling_started.connect(_on_stalling_started)
	EventBus.steal_started.connect(_on_steal_attempt)
	# Lecture de la table.
	EventBus.card_stored.connect(func(who, _card: Dictionary) -> void:
		_bump_suspicion(who, 1.0))  # il prépare un mauvais coup.
	EventBus.card_used.connect(func(user, _card: Dictionary, target) -> void:
		if target == character:
			_bump_suspicion(user, 5.0))  # VENGEANCE.
	EventBus.player_damaged.connect(_on_someone_damaged)
	EventBus.card_revealed.connect(func(who, _card: Dictionary) -> void:
		_bump_suspicion(who, -0.5))  # la transparence apaise.
	_spy_loop()
	_defense_loop()

func _bump_suspicion(who, amount: float) -> void:
	if who == null or who == character:
		return
	var key: int = who.get_instance_id()
	_suspicion[key] = maxf(float(_suspicion.get(key, 0.0)) + amount * _d("suspicion"), 0.0)

## Les gifles et cailloux signent leurs auteurs : le bot s'en souvient.
func _on_someone_damaged(victim, _amount: int, source: String) -> void:
	if victim != character:
		return
	for prefix in ["Claque de ", "Caillou de "]:
		if source.begins_with(prefix):
			var attacker_name := source.trim_prefix(prefix)
			for other in get_tree().get_nodes_in_group("characters"):
				if other.display_name == attacker_name:
					_bump_suspicion(other, 5.0)
			return

## Mode Équipes : les bots sont LOYAUX — jamais d'attaque volontaire sur un
## coéquipier (le tir ami reste possible pour les humains maladroits).
func _is_teammate(other) -> bool:
	return GameConfig.mode == "teams" and character.team >= 0 and other.team == character.team

## Choisit une victime : suspicion + faiblesse visible + une part d'imprévu.
func _pick_victim(candidates: Array):
	var best = null
	var best_score := -INF
	for candidate in candidates:
		var score := float(_suspicion.get(candidate.get_instance_id(), 0.0))
		score += (100 - candidate.health.visual_state) * 0.05  # achever les blessés.
		score += randf() * 2.0
		if score > best_score:
			best_score = score
			best = candidate
	return best

## On fouille MON sac ?! Le bot se retourne (flagrant délit) puis gifle.
func _on_steal_attempt(thief, victim) -> void:
	if victim != character or not character.is_alive() or thief == null:
		return
	await get_tree().create_timer(randf_range(0.8, 2.0) * _d("think")).timeout
	if not character.is_alive() or not is_instance_valid(thief):
		return
	character.look_at(Vector3(thief.global_position.x, 0, thief.global_position.z))
	character.play_emote("😤")
	_bump_suspicion(thief, 6.0)
	await get_tree().create_timer(0.4).timeout
	if character.is_alive() and is_instance_valid(thief):
		character.try_slap(thief)

## Quelqu'un fait poireauter la table : on le caillasse jusqu'à ce qu'il pioche.
func _on_stalling_started(lambin) -> void:
	if lambin == character or not character.is_alive():
		return
	await get_tree().create_timer(randf_range(0.8, 2.5)).timeout
	while EventBus.stalling_player == lambin and character.is_alive() \
			and is_instance_valid(lambin) and lambin.is_alive():
		# Un espion debout profite du chaos ? Il devient une cible de choix.
		var target = lambin
		var spies := get_tree().get_nodes_in_group("characters").filter(
			func(c) -> bool: return c != character and c.is_alive() and not c.is_seated)
		if not spies.is_empty() and randf() < 0.4:
			target = spies.pick_random()
		character.throw_rock(target)
		await get_tree().create_timer(randf_range(1.4, 2.8)).timeout

func _on_turn_started(who) -> void:
	if who != character or not character.is_alive():
		return
	_my_turn = true
	# En vadrouille quand son tour arrive ? On rentre s'asseoir d'abord.
	if not character.is_seated:
		character.return_to_seat()
		await character.seated
		if not character.is_alive():
			return
	# Petit temps de "réflexion" — les bots durs réfléchissent VITE.
	await get_tree().create_timer(randf_range(1.0, 2.0) * _d("think")).timeout
	if not character.is_alive():
		return
	_maybe_use_stored_card()
	await get_tree().create_timer(randf_range(0.5, 1.0)).timeout
	if character.is_alive():
		EventBus.draw_requested.emit(character)

## De temps en temps, le bot se lève : fleur s'il va mal, un verre pour le
## plaisir, ou une virée d'espionnage — vers le joueur le plus SUSPECT.
func _spy_loop() -> void:
	while is_instance_valid(character):
		await get_tree().create_timer(randf_range(10.0, 22.0)).timeout
		if not is_instance_valid(character) or not character.is_alive():
			return
		if _my_turn or not character.is_seated or not EventBus.match_started:
			continue
		# Mal en point + fleur disponible ? Le bot va se l'offrir. 💅
		if character.health.hp < 50 and not EventBus.flower_taken and randf() < 0.6:
			_flower_errand()
			continue
		# Petit verre au comptoir, pour le folklore.
		if character.health.hp < 95 and randf() < 0.12:
			_drink_errand()
			continue
		if randf() >= minf(float(SPY_CHANCE[personality]) * _d("spy"), 0.9):
			continue
		var targets := get_tree().get_nodes_in_group("characters").filter(
			func(c) -> bool: return c != character and c.is_alive() and not _is_teammate(c))
		if not targets.is_empty():
			character.spy_walk(_pick_victim(targets))  # on espionne les suspects (ennemis).

func _flower_errand() -> void:
	var pots := get_tree().get_nodes_in_group("flower_pot")
	if pots.is_empty():
		return
	var nearest: Node3D = null
	var best := INF
	for pot in pots:
		var d: float = character.global_position.distance_to(pot.global_position)
		if d < best:
			best = d
			nearest = pot
	var angle: float = atan2(nearest.global_position.x, nearest.global_position.z)
	character.errand(angle, 9.0, func() -> void:
		character.pick_flower()
		if character.has_flower:
			character.offer_flower(character))

func _drink_errand() -> void:
	var bars := get_tree().get_nodes_in_group("bar_drink")
	if bars.is_empty():
		return
	var angle: float = atan2(bars[0].global_position.x, bars[0].global_position.z)
	character.errand(angle, 7.6, func() -> void: character.drink())

## Un joueur debout rôde ? À portée de bras : CLAC. Plus loin : caillou.
## Zèle selon le tempérament, MAIS avec un long temps de recharge : être
## debout doit rester risqué, pas suicidaire (fleur, espionnage, billard…).
## Et un porteur de fleur est sacré : aucun bot ne s'en prend à lui.
func _defense_loop() -> void:
	while is_instance_valid(character):
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(character) or not character.is_alive():
			return
		for other in get_tree().get_nodes_in_group("characters"):
			if other == character or other.is_seated or not other.is_alive() or other.has_flower \
					or _is_teammate(other):
				continue
			var distance: float = character.global_position.distance_to(other.global_position)
			# Quelqu'un rôde dans mon dos ? Je me RETOURNE pour protéger mon sac.
			if character.is_seated and distance < 2.6:
				var to_other: Vector3 = (other.global_position - character.global_position).normalized()
				var behind: bool = (-character.global_basis.z).dot(to_other) < -0.2
				if behind and randf() < float(PROTECT_CHANCE[personality]):
					character.look_at(Vector3(other.global_position.x, 0, other.global_position.z))
					character.play_emote(SPECTATE_EMOTE[personality])
					_bump_suspicion(other, 2.0)
					continue
			var acted := false
			if distance <= 1.7:
				if randf() < minf(float(AGGRO_CHANCE[personality]) * _d("aggro"), 0.95):
					acted = character.try_slap(other)
			elif randf() < float(AGGRO_CHANCE[personality]) * 0.08 * _d("aggro"):
				acted = character.throw_rock(other)
			if acted:
				_maybe_taunt(other)
				# Temps de recharge : un bot ne mitraille jamais (mais Céleste recharge vite).
				await get_tree().create_timer(randf_range(5.0, 9.0) / maxf(_d("aggro"), 0.5)).timeout
				break

## Le bot joue une carte de sa manche : soin s'il est mal en point,
## carte offensive selon son agressivité.
func _maybe_use_stored_card() -> void:
	for i in character.hand.size():
		var card: Dictionary = character.hand[i]
		var heals: bool = card.get("effects", []).any(
			func(e) -> bool: return e.get("type", "") == "heal")
		if heals and character.health.hp <= int(_d("heal_at")):
			character.use_card(i, character)
			return
		# Les grenades se lancent à tout moment — sur la cible la plus MÉRITANTE
		# (suspicion accumulée + blessures apparentes), plus une part de hasard.
		if card.get("targetable", false) and randf() < minf(float(AGGRO_CHANCE[personality]) * _d("aggro"), 0.95):
			var victims := get_tree().get_nodes_in_group("characters").filter(
				func(c) -> bool: return c != character and c.is_alive() and not _is_teammate(c))
			if not victims.is_empty():
				var victim = _pick_victim(victims)
				character.use_card(i, victim)
				_maybe_taunt(victim)
			return

func _on_card_drawn(who, card: Dictionary) -> void:
	if not character.is_alive():
		return
	if who == character:
		await get_tree().create_timer(randf_range(0.6, 1.8)).timeout
		if character.is_alive():
			character.play_emote(_pick_reaction(card))
			# Parfois, le bot joue la transparence — les durs, presque jamais.
			if randf() < float(REVEAL_CHANCE[personality]) * _d("reveal"):
				await get_tree().create_timer(randf_range(0.3, 0.8)).timeout
				if character.is_alive():
					character.reveal_card()
	elif randf() < 0.18:
		# Réaction de spectateur : ambiance de table, faux indices gratuits.
		await get_tree().create_timer(randf_range(0.5, 2.0)).timeout
		if character.is_alive():
			character.play_emote(SPECTATE_EMOTE[personality])

## Choisit l'émote de réaction à SA carte : honnête… ou pas.
func _pick_reaction(card: Dictionary) -> String:
	# Neutre = soulagement (rien ne se passe) ; utilitaire = une arme en main.
	var feels_good: bool = card.get("category", "") in ["positive", "neutral", "utility"]
	var bluffs: bool = randf() < float(BLUFF_CHANCE[personality])
	if personality == Personality.TROLL and randf() < 0.4:
		return "😏"  # Le troll adore semer le doute.
	var shows_good: bool = feels_good != bluffs  # XOR : bluffer = montrer l'inverse.
	return (EMOTE_GOOD if shows_good else EMOTE_BAD).pick_random()
