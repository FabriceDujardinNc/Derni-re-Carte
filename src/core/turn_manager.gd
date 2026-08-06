class_name TurnManager
extends Node
## TurnManager — boucle de jeu au tour par tour.
##
## Séquence d'un tour :
##   1. turn_started → le joueur courant doit piocher (bot : automatique).
##   2. draw_requested validé → card_drawn (info privée au piocheur).
##   3. Fenêtre de réaction : quelques secondes où tout le monde observe,
##      émotes, bluff… puis l'effet se résout.
##   4. Courte transition, tour suivant. Les morts sont sautés.
## La partie s'arrête quand il reste au plus un survivant.

## Durée pendant laquelle le piocheur peut jouer la comédie avant résolution.
const REACTION_TIME := 3.5
const TURN_TRANSITION := 1.2
## Au-delà de ce délai sans piocher, la table a le droit de te caillasser.
const STALL_TIME := 15.0

var players: Array = []
var current_index := -1
var match_running := false

var _awaiting_draw := false
var _turn_id := 0  ## Identifie chaque tour : évite qu'un vieux minuteur agisse sur un tour suivant.

## Mort subite : au-delà du temps limite, la vie de TOUS s'écoule (1 PV/s).
var _match_elapsed := 0.0
var _sudden_death := false
var _drip_accumulator := 0.0

func _process(delta: float) -> void:
	if not match_running or not EventBus.match_started:
		return
	_match_elapsed += delta
	if not _sudden_death:
		if _match_elapsed >= GameConfig.sudden_death_seconds:
			_sudden_death = true
			EventBus.log_public.emit("💀 MORT SUBITE ! La taverne réclame un vainqueur — la vie de chacun s'écoule…")
		return
	_drip_accumulator += delta
	while _drip_accumulator >= 1.0:
		_drip_accumulator -= 1.0
		for player in players:
			if player.is_alive():
				player.health.take_damage(1, "Mort subite")

func start_match(p_players: Array) -> void:
	players = p_players
	match_running = true
	EventBus.draw_requested.connect(_on_draw_requested)
	EventBus.player_died.connect(_on_player_died)
	EventBus.log_public.emit("🎴 La partie commence ! Que le meilleur menteur gagne.")
	_next_turn()

func current_player():
	return players[current_index] if current_index >= 0 else null

func _alive_players() -> Array:
	return players.filter(func(p) -> bool: return p.is_alive())

func _next_turn() -> void:
	if not match_running:
		return
	var alive := _alive_players()
	if alive.size() <= 1 or _same_chain(alive):
		_end_match(alive[0] if alive.size() >= 1 else null)
		return
	# Avance jusqu'au prochain joueur vivant.
	for i in players.size():
		current_index = (current_index + 1) % players.size()
		if players[current_index].is_alive():
			break
	_clear_stalling()
	_awaiting_draw = true
	_turn_id += 1
	EventBus.turn_started.emit(players[current_index])
	_watch_stalling(players[current_index], _turn_id)

## Après STALL_TIME sans pioche, ouvre la saison du caillassage sur le lambin.
func _watch_stalling(character, turn_id: int) -> void:
	await get_tree().create_timer(STALL_TIME).timeout
	if not match_running or not _awaiting_draw or turn_id != _turn_id \
			or not character.is_alive():
		return
	EventBus.stalling_player = character
	EventBus.stalling_started.emit(character)
	EventBus.log_public.emit(
		"🪨 %s fait traîner la partie… Caillassage autorisé jusqu'à ce qu'il pioche !"
		% character.display_name)

func _clear_stalling() -> void:
	if EventBus.stalling_player != null:
		var lambin = EventBus.stalling_player
		EventBus.stalling_player = null
		EventBus.stalling_ended.emit(lambin)

func _on_draw_requested(character) -> void:
	if not match_running:
		return
	if character != current_player():
		if not character.is_bot:
			EventBus.log_private.emit(character, "⛔ Ce n'est pas ton tour !")
		return
	if not _awaiting_draw:
		return
	# On pioche depuis sa chaise, pas en vadrouille autour de la table.
	if not character.is_seated:
		if not character.is_bot:
			EventBus.log_private.emit(character, "🪑 Reviens t'asseoir pour piocher ! (touche E)")
		return
	_awaiting_draw = false
	if EventBus.stalling_player == character:
		_clear_stalling()
		EventBus.log_public.emit("😮‍💨 %s pioche enfin. On repose les cailloux."
			% character.display_name)

	var card: Dictionary = CardDatabase.draw_card()
	character.current_card = card
	EventBus.card_drawn.emit(character, card)

	# Fenêtre de réaction : c'est ICI que le bluff se joue.
	await get_tree().create_timer(REACTION_TIME).timeout
	if not match_running:
		return
	if character.is_alive():
		# Carte conservable → elle rejoint la manche au lieu de se résoudre
		# (main pleine : elle s'applique immédiatement, tant pis pour lui).
		if card.get("keepable", false) and character.can_store_card():
			character.store_card(card)
		else:
			EffectExecutor.apply(character, card)
		EventBus.card_resolved.emit(character, card)

	await get_tree().create_timer(TURN_TRANSITION).timeout
	if match_running:
		_next_turn()

func _on_player_died(character, cause: String) -> void:
	if not match_running:
		return
	EventBus.log_public.emit("💀 %s est hors-jeu ! (%s)" % [character.display_name, cause])
	var alive := _alive_players()
	if alive.size() <= 1 or _same_chain(alive):
		_end_match(alive[0] if alive.size() >= 1 else null)
		return
	# Si le joueur courant meurt en attendant sa pioche (poison, Destin…), on avance.
	if _awaiting_draw and character == current_player():
		_awaiting_draw = false
		_next_turn()

## Mode Enchaînés : si tous les survivants partagent la même chaîne,
## la partie s'arrête sur une victoire partagée.
func _same_chain(alive: Array) -> bool:
	if GameConfig.mode != "chains" or alive.size() < 2:
		return false
	var chain_nodes := get_tree().get_nodes_in_group("chain_mode")
	if chain_nodes.is_empty():
		return false
	var group: Array = chain_nodes[0].group_of(alive[0])
	for character in alive:
		if not character in group:
			return false
	var names: Array[String] = []
	for character in alive:
		names.append(character.display_name)
	EventBus.log_public.emit("⛓️ Enchaînés jusqu'au bout : %s remportent la partie ENSEMBLE !"
		% " et ".join(names))
	return true

func _end_match(winner) -> void:
	match_running = false
	# Fin des hostilités : plus de gifles/cailloux/cartes après le verdict
	# (les bots, eux, ne s'arrêteraient jamais d'eux-mêmes…).
	EventBus.match_started = false
	# Double KO ? L'AUDACE départage : le plus flamboyant l'emporte, même mort.
	if winner == null and not players.is_empty():
		var boldest = null
		for player in players:
			if boldest == null or player.points > boldest.points:
				boldest = player
		if boldest != null and boldest.points > 0:
			winner = boldest
			EventBus.log_public.emit("⚖️ Double KO ! L'audace départage : %s l'emporte avec %d point%s !"
				% [winner.display_name, winner.points, "s" if winner.points > 1 else ""])
	if winner != null:
		EventBus.log_public.emit("🏆 %s remporte la Dernière Carte !" % winner.display_name)
	else:
		EventBus.log_public.emit("💀 Personne n'a survécu… La table gagne.")
	EventBus.match_ended.emit(winner)
