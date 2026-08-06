extends Node
## Net — module réseau multijoueur (autoload).
##
## Modèle : l'HÔTE FAIT AUTORITÉ. Toute la logique (tours, pioches, effets,
## bots, dégâts) tourne uniquement chez l'hôte. Les clients :
##   - envoient leurs ACTIONS (piocher, émote, se lever, carte, gifle/caillou) ;
##   - reçoivent les ÉVÉNEMENTS (relais des signaux EventBus) et les positions.
## Les personnages côté client sont des marionnettes : leurs visuels réagissent
## aux événements re-émis localement — exactement le même code qu'en solo.
##
## Protection par mot de passe à la connexion (suffisant entre amis ; le
## matchmaking Steam remplacera l'IP plus tard sans toucher à ce modèle).

const DEFAULT_PORT := 4242
const TRANSFORM_RATE := 1.0 / 15.0  # 15 envois de positions par seconde.

signal lobby_updated
signal joined_lobby
signal join_failed(reason: String)

var active := false      ## Partie réseau en cours (hôte OU client).
var is_server := true    ## Vrai aussi en solo : la logique tourne localement.
var password := ""
var peers := {}          ## peer_id -> {"name": String, "color": int}
var seats: Array = []    ## Figé au lancement : [{"peer": int (-1 = bot), "name", "color"}]
var my_seat := 0
var characters: Array = []  ## CharacterBase par siège (rempli par main.gd).

var _transform_accumulator := 0.0
var _clients_ready := 0

func client_mode() -> bool:
	return active and not is_server

func seat_of(character) -> int:
	return characters.find(character)

func _char(seat: int):
	return characters[seat] if seat >= 0 and seat < characters.size() else null

# ---------------------------------------------------------------- Hébergement

func host_game(port: int, pwd: String, player_name: String, color: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 8)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	is_server = true
	password = pwd
	peers = {1: {"name": player_name, "color": color}}
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	lobby_updated.emit()
	return OK

func join_game(ip: String, port: int, pwd: String, player_name: String, color: int) -> Error:
	print("Net : connexion à %s:%d…" % [ip, port])
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		print("Net : échec de création du client (%d)" % error)
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	is_server = false
	password = pwd
	_pending_join = {"name": player_name, "color": color}
	# is_connected : une tentative précédente a pu laisser ses connexions.
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK

var _pending_join := {}

func _on_connected_to_server() -> void:
	print("Net : connecté à l'hôte, envoi de la demande d'entrée…")
	request_join.rpc_id(1, password, _pending_join["name"], _pending_join["color"], GameConfig.VERSION)

func _on_connection_failed() -> void:
	print("Net : connexion impossible (IP/port injoignables).")
	leave()
	join_failed.emit("Connexion impossible : vérifie l'IP et que l'hôte a bien cliqué Héberger.")

func _on_server_disconnected() -> void:
	print("Net : déconnecté par l'hôte.")
	leave()
	join_failed.emit("Déconnecté par l'hôte.")

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server:
		return
	if peers.has(peer_id):
		peers.erase(peer_id)
		sync_lobby.rpc(peers)
		lobby_updated.emit()
	# En pleine partie : le personnage du déserteur passe en pilote automatique.
	for i in seats.size():
		if int(seats[i]["peer"]) == peer_id:
			seats[i]["peer"] = -1
			var character = _char(i)
			if character != null and is_instance_valid(character) and character.is_alive():
				character.add_child(BotBrain.new())
				EventBus.log_public.emit("🤖 %s a quitté la partie — un bot prend le relais."
					% character.display_name)

func leave() -> void:
	active = false
	is_server = true
	peers = {}
	seats = []
	characters = []
	my_seat = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

# ---------------------------------------------------------------- Lobby

@rpc("any_peer", "call_remote", "reliable")
func request_join(pwd: String, player_name: String, color: int, version: String = "?") -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if version != GameConfig.VERSION:
		print("Net : joueur %d refusé (version %s ≠ %s)." % [sender, version, GameConfig.VERSION])
		reject_join.rpc_id(sender, "Versions différentes (hôte %s, toi %s) : téléchargez la même release !"
			% [GameConfig.VERSION, version])
		await get_tree().create_timer(0.5).timeout
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	if pwd != password:
		print("Net : joueur %d refusé (mauvais mot de passe)." % sender)
		reject_join.rpc_id(sender, "Mot de passe incorrect.")
		await get_tree().create_timer(0.5).timeout
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	print("Net : %s a rejoint le salon." % player_name)
	peers[sender] = {"name": player_name, "color": color}
	sync_lobby.rpc(peers)
	lobby_updated.emit()

@rpc("authority", "call_remote", "reliable")
func reject_join(reason: String) -> void:
	leave()
	join_failed.emit(reason)

@rpc("authority", "call_remote", "reliable")
func sync_lobby(new_peers: Dictionary) -> void:
	print("Net : salon reçu (%d joueurs)." % new_peers.size())
	peers = new_peers
	lobby_updated.emit()
	joined_lobby.emit()

## Meilleure IP à partager (les box familiales donnent du 192.168.x.x).
static func best_local_ip() -> String:
	var candidates: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			if ip.begins_with("192.168."):
				return ip
			candidates.append(ip)
	return candidates[0] if not candidates.is_empty() else "(introuvable)"

## L'hôte fige les sièges (humains d'abord, bots pour compléter) et lance tout le monde.
func start_match_as_host(table_size: int) -> void:
	if not is_server:
		return
	var new_seats: Array = []
	var peer_ids := peers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		new_seats.append({"peer": peer_id, "name": peers[peer_id]["name"], "color": peers[peer_id]["color"]})
	var bot_names := ["Gaston", "Ginette", "Kevin", "Perceval", "Momo", "Jacqueline", "Bob"]
	var bot_index := 0
	while new_seats.size() < maxi(table_size, new_seats.size()) and bot_index < bot_names.size():
		new_seats.append({"peer": -1, "name": bot_names[bot_index], "color": (new_seats.size()) % 8})
		bot_index += 1
	rpc_start_match.rpc(new_seats, GameConfig.mode, GameConfig.difficulty)

@rpc("authority", "call_local", "reliable")
func rpc_start_match(new_seats: Array, mode: String, difficulty: String) -> void:
	GameConfig.mode = mode  # le mode et la difficulté de l'hôte s'appliquent à tous.
	GameConfig.difficulty = difficulty
	seats = new_seats
	var my_id := multiplayer.get_unique_id()
	my_seat = 0
	for i in seats.size():
		if int(seats[i]["peer"]) == my_id:
			my_seat = i
	_clients_ready = 0
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ---------------------------------------------------------------- Démarrage de la manche

## Appelé par main.gd une fois la scène construite et les personnages enregistrés.
func match_begin(scene_characters: Array) -> void:
	characters = scene_characters
	if is_server:
		_install_server_relay()
	else:
		_install_client_hooks()
		client_scene_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func client_scene_ready() -> void:
	if is_server:
		_clients_ready += 1

## L'hôte attend que tous les clients aient chargé la scène (délai de grâce max).
func wait_for_clients(timeout: float) -> void:
	var expected := 0
	for seat in seats:
		if int(seat["peer"]) > 1:
			expected += 1
	var waited := 0.0
	while _clients_ready < expected and waited < timeout:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2

# ---------------------------------------------------------------- Relais serveur → clients

## L'hôte écoute l'EventBus et rediffuse chaque événement aux clients.
func _install_server_relay() -> void:
	EventBus.turn_started.connect(func(c) -> void: _bcast("turn", {"s": seat_of(c)}))
	EventBus.card_drawn.connect(func(c, card: Dictionary) -> void:
		_bcast("drawn", {"s": seat_of(c), "card": card}))
	EventBus.card_resolved.connect(func(c, card: Dictionary) -> void:
		_bcast("resolved", {"s": seat_of(c), "card": card}))
	EventBus.card_stored.connect(func(c, card: Dictionary) -> void:
		_bcast("stored", {"s": seat_of(c), "card": card}))
	EventBus.card_used.connect(func(user, card: Dictionary, target) -> void:
		_bcast("used", {"s": seat_of(user), "card": card, "t": seat_of(target)}))
	EventBus.card_revealed.connect(func(c, card: Dictionary) -> void:
		_bcast("revealed", {"s": seat_of(c), "card": card, "p": c.points}))
	EventBus.points_changed.connect(func(c, points: int) -> void:
		_bcast("points", {"s": seat_of(c), "p": points}))
	EventBus.flower_picked.connect(func(c) -> void:
		_bcast("fpick", {"s": seat_of(c)}))
	EventBus.flower_offered.connect(func(giver, receiver) -> void:
		_bcast("fgive", {"s": seat_of(giver), "t": seat_of(receiver)}))
	EventBus.emote_played.connect(func(c, emote: String) -> void:
		_bcast("emote", {"s": seat_of(c), "e": emote}))
	EventBus.fake_event.connect(func(message: String) -> void: _bcast("fake", {"m": message}))
	EventBus.log_public.connect(func(message: String) -> void: _bcast("logp", {"m": message}))
	EventBus.log_private.connect(_relay_private_log)
	EventBus.match_ended.connect(func(winner) -> void:
		_bcast("end", {"s": seat_of(winner) if winner != null else -1}))
	EventBus.stalling_started.connect(func(c) -> void: _bcast("stall_on", {"s": seat_of(c)}))
	EventBus.stalling_ended.connect(func(c) -> void: _bcast("stall_off", {"s": seat_of(c)}))
	EventBus.player_stood_up.connect(func(c) -> void: _bcast("stood", {"s": seat_of(c)}))
	EventBus.player_sat_down.connect(func(c) -> void: _bcast("sat", {"s": seat_of(c)}))
	EventBus.status_applied.connect(func(c, status_name: String) -> void:
		_bcast("status", {"s": seat_of(c), "n": status_name}))
	EventBus.projectile_thrown.connect(func(from: Vector3, to: Vector3) -> void:
		_bcast("proj", {"f": from, "t": to}))
	EventBus.chain_echo.connect(func(c) -> void:
		_bcast("cecho", {"s": seat_of(c)}))
	EventBus.director_event.connect(func(event_name: String) -> void:
		_bcast("dir", {"n": event_name}))
	EventBus.chat_message.connect(func(c, text: String) -> void:
		_bcast("chat", {"s": seat_of(c), "m": text}))
	EventBus.steal_started.connect(func(thief, victim) -> void:
		_bcast("sst", {"s": seat_of(thief), "v": seat_of(victim)}))
	EventBus.steal_ended.connect(func(victim) -> void:
		_bcast("sse", {"v": seat_of(victim)}))
	EventBus.card_stolen.connect(func(thief, victim, card: Dictionary) -> void:
		_bcast("stolen", {"s": seat_of(thief), "v": seat_of(victim), "card": card}))
	# État de santé : synchronisation par personnage.
	for i in characters.size():
		var seat := i
		var c = characters[i]
		c.health.hp_changed.connect(func(_hp: int, _max: int) -> void: _bcast_health(seat))
		c.health.shield_changed.connect(func(_s: int) -> void: _bcast_health(seat))
		c.health.visual_state_changed.connect(func(_v: int) -> void: _bcast_health(seat))
		c.health.damaged.connect(func(amount: int, source: String) -> void:
			_bcast("dmg", {"s": seat, "a": amount, "src": source}))
		c.health.died.connect(func(cause: String) -> void:
			_bcast("died", {"s": seat, "c": cause}))

func _relay_private_log(c, message: String) -> void:
	var seat := seat_of(c)
	if seat < 0:
		return
	var peer := int(seats[seat]["peer"])
	if peer > 1:
		net_event.rpc_id(peer, "logpr", {"s": seat, "m": message})

func _bcast(type: String, data: Dictionary) -> void:
	if active:
		net_event.rpc(type, data)

func _bcast_health(seat: int) -> void:
	var c = _char(seat)
	if c != null and active:
		net_event.rpc("hp", {"s": seat, "hp": c.health.hp, "sh": c.health.shield, "v": c.health.visual_state})

@rpc("authority", "call_remote", "reliable")
func net_event(type: String, data: Dictionary) -> void:
	var c = _char(int(data.get("s", -1)))
	match type:
		"turn":
			EventBus.turn_started.emit(c)
		"drawn":
			c.current_card = data["card"]
			EventBus.card_drawn.emit(c, data["card"])
		"resolved":
			EventBus.card_resolved.emit(c, data["card"])
		"stored":
			c.hand.append(data["card"])
			c._refresh_bag()
			EventBus.card_stored.emit(c, data["card"])
		"used":
			_remove_from_hand(c, data["card"])
			c._refresh_bag()
			EventBus.card_used.emit(c, data["card"], _char(int(data.get("t", -1))))
		"revealed":
			c.points = int(data["p"])
			c.current_card = data["card"]
			EventBus.card_revealed.emit(c, data["card"])
		"points":
			c.points = int(data["p"])
			EventBus.points_changed.emit(c, c.points)
		"fpick":
			EventBus.flower_taken = true
			c.has_flower = true
			c.show_carried_flower(true)
			EventBus.flower_picked.emit(c)
		"fgive":
			var receiver = _char(int(data.get("t", -1)))
			c.has_flower = false
			c.show_carried_flower(false)
			if receiver != null:
				receiver.wear_flower()
			EventBus.flower_offered.emit(c, receiver)
		"cecho":
			EventBus.chain_echo.emit(c)
		"dir":
			EventBus.director_event.emit(data["n"])
		"chat":
			if int(data["s"]) != my_seat:  # son propre message est déjà affiché.
				c.say(data["m"])
		"sst":
			EventBus.steal_started.emit(c, _char(int(data.get("v", -1))))
		"sse":
			EventBus.steal_ended.emit(_char(int(data.get("v", -1))))
		"stolen":
			var robbed = _char(int(data.get("v", -1)))
			if robbed != null:
				_remove_from_hand(robbed, data["card"])
				robbed._refresh_bag()
			c.hand.append(data["card"])
			c._refresh_bag()
			EventBus.card_stolen.emit(c, robbed, data["card"])
		"tuto_wait":
			EventBus.tutorial_waiting.emit(data["names"])
		"tuto_go":
			EventBus.warmup = true
			EventBus.tutorial_waiting.emit([])
		"count":
			var n := int(data["n"])
			EventBus.countdown_tick.emit(n)
			if n == 0:
				EventBus.warmup = false
				EventBus.match_started = true
				for player in characters:
					if is_instance_valid(player):
						player.reset_for_match()
		"emote":
			if int(data["s"]) != my_seat:  # sa propre émote a déjà été jouée localement.
				c.play_emote(data["e"])
		"fake":
			EventBus.fake_event.emit(data["m"])
		"logp":
			EventBus.log_public.emit(data["m"])
		"logpr":
			EventBus.log_private.emit(c, data["m"])
		"end":
			EventBus.match_ended.emit(c)
		"stall_on":
			EventBus.stalling_player = c
			EventBus.stalling_started.emit(c)
		"stall_off":
			EventBus.stalling_player = null
			EventBus.stalling_ended.emit(c)
		"stood":
			if int(data["s"]) != my_seat:
				c.is_seated = false
		"sat":
			if int(data["s"]) != my_seat:
				c.is_seated = true
		"status":
			EventBus.status_applied.emit(c, data["n"])
		"proj":
			Projectile.throw(get_tree().current_scene, data["f"], data["t"], func() -> void: pass)
		"hp":
			var h = c.health
			h.hp = int(data["hp"])
			h.shield = int(data["sh"])
			h.hp_changed.emit(h.hp, h.max_hp)
			h.shield_changed.emit(h.shield)
			if h.visual_state != int(data["v"]):
				h.visual_state = int(data["v"])
				h.visual_state_changed.emit(h.visual_state)
		"dmg":
			c.health.damaged.emit(int(data["a"]), data["src"])
		"died":
			c.health.hp = 0
			c.health.died.emit(data["c"])

func _remove_from_hand(c, card: Dictionary) -> void:
	for i in c.hand.size():
		if c.hand[i].get("id", "") == card.get("id", "!"):
			c.hand.remove_at(i)
			return

# ---------------------------------------------------------------- Actions client → serveur

## Le client écoute ses propres signaux locaux et les transmet à l'hôte.
func _install_client_hooks() -> void:
	EventBus.draw_requested.connect(func(c) -> void:
		if seat_of(c) == my_seat:
			input_draw.rpc_id(1))
	EventBus.emote_played.connect(func(c, emote: String) -> void:
		if seat_of(c) == my_seat:
			input_emote.rpc_id(1, emote))
	EventBus.player_stood_up.connect(func(c) -> void:
		if seat_of(c) == my_seat:
			input_stand.rpc_id(1, true))
	EventBus.player_sat_down.connect(func(c) -> void:
		if seat_of(c) == my_seat:
			input_stand.rpc_id(1, false))

func send_use_card(index: int, target_seat: int) -> void:
	input_use_card.rpc_id(1, index, target_seat)

func send_melee(target_seat: int) -> void:
	input_melee.rpc_id(1, target_seat)

func send_reveal() -> void:
	input_reveal.rpc_id(1)

func send_barman() -> void:
	input_barman.rpc_id(1)

func send_billiard(ball_index: int, direction: Vector3) -> void:
	input_billiard.rpc_id(1, ball_index, direction)

func send_flower_pick() -> void:
	input_flower_pick.rpc_id(1)

func send_drink() -> void:
	input_drink.rpc_id(1)

func send_chat(text: String) -> void:
	input_chat.rpc_id(1, text)

# --- Vol à la tire ---

func send_steal_start(victim_seat: int) -> void:
	input_steal_start.rpc_id(1, victim_seat)

func send_steal_end(victim_seat: int) -> void:
	input_steal_end.rpc_id(1, victim_seat)

func send_steal_finish(victim_seat: int, card_index: int) -> void:
	input_steal_finish.rpc_id(1, victim_seat, card_index)

func send_steal_caught() -> void:
	input_steal_caught.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func input_steal_start(victim_seat: int) -> void:
	var thief = _char(_seat_of_sender())
	var victim = _char(victim_seat)
	if is_server and thief != null and victim != null:
		EventBus.steal_started.emit(thief, victim)

@rpc("any_peer", "call_remote", "reliable")
func input_steal_end(victim_seat: int) -> void:
	var victim = _char(victim_seat)
	if is_server and victim != null:
		EventBus.steal_ended.emit(victim)

@rpc("any_peer", "call_remote", "reliable")
func input_steal_finish(victim_seat: int, card_index: int) -> void:
	var thief = _char(_seat_of_sender())
	var victim = _char(victim_seat)
	if is_server and thief != null and victim != null:
		thief.steal_card_from(victim, card_index)

@rpc("any_peer", "call_remote", "reliable")
func input_steal_caught() -> void:
	var thief = _char(_seat_of_sender())
	if is_server and thief != null:
		thief.health.take_damage(8, "Pris la main dans le sac")

@rpc("any_peer", "call_remote", "reliable")
func input_chat(text: String) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		c.say(text.strip_edges().left(90))

@rpc("any_peer", "call_remote", "reliable")
func input_drink() -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		c.drink()

func send_flower_offer(target_seat: int) -> void:
	input_flower_offer.rpc_id(1, target_seat)

@rpc("any_peer", "call_remote", "reliable")
func input_flower_pick() -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		c.pick_flower()

@rpc("any_peer", "call_remote", "reliable")
func input_flower_offer(target_seat: int) -> void:
	var c = _char(_seat_of_sender())
	var target = _char(target_seat)
	if is_server and c != null and target != null:
		c.offer_flower(target)

func broadcast_balls(states: Array) -> void:
	if active and is_server:
		net_balls.rpc(states)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_balls(states: Array) -> void:
	var billiards := get_tree().get_nodes_in_group("billiard")
	if not billiards.is_empty():
		billiards[0].apply_sync(states)

@rpc("any_peer", "call_remote", "reliable")
func input_billiard(ball_index: int, direction: Vector3) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		var billiards := get_tree().get_nodes_in_group("billiard")
		if not billiards.is_empty():
			billiards[0].strike_index(ball_index, direction, c)

@rpc("any_peer", "call_remote", "reliable")
func input_barman() -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		var barmen := get_tree().get_nodes_in_group("barman")
		if not barmen.is_empty():
			barmen[0].poke(c)

@rpc("any_peer", "call_remote", "reliable")
func input_reveal() -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		c.reveal_card()

func _seat_of_sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	for i in seats.size():
		if int(seats[i]["peer"]) == sender:
			return i
	return -1

@rpc("any_peer", "call_remote", "reliable")
func input_draw() -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		EventBus.draw_requested.emit(c)

@rpc("any_peer", "call_remote", "reliable")
func input_emote(emote: String) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		c.play_emote(emote)

@rpc("any_peer", "call_remote", "reliable")
func input_stand(up: bool) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		if up:
			c.stand_up()
		else:
			c.return_to_seat()

@rpc("any_peer", "call_remote", "reliable")
func input_use_card(index: int, target_seat: int) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null:
		var target = _char(target_seat) if target_seat >= 0 else c
		c.use_card(index, target)

@rpc("any_peer", "call_remote", "reliable")
func input_melee(target_seat: int) -> void:
	var attacker = _char(_seat_of_sender())
	var target = _char(target_seat)
	if is_server and attacker != null and target != null:
		if not attacker.try_slap(target):
			attacker.throw_rock(target)

# ---------------------------------------------------------------- Tutoriel

var _tuto_ready := {}  ## siège -> a fini (ou passé) le tutoriel.

## Appelé par le tutoriel local quand le joueur a fini de lire.
func tutorial_ready() -> void:
	if client_mode():
		input_tutorial_ready.rpc_id(1)
	else:
		_mark_tutorial_ready(my_seat)

@rpc("any_peer", "call_remote", "reliable")
func input_tutorial_ready() -> void:
	if is_server:
		_mark_tutorial_ready(_seat_of_sender())

func _mark_tutorial_ready(seat: int) -> void:
	if seat >= 0:
		_tuto_ready[seat] = true
	_broadcast_tutorial_status()

## Informe tout le monde de qui lit encore.
func _broadcast_tutorial_status() -> void:
	var waiting: Array = []
	for i in seats.size():
		if int(seats[i]["peer"]) != -1 and not _tuto_ready.has(i):
			waiting.append(seats[i]["name"])
	EventBus.tutorial_waiting.emit(waiting)
	if active:
		net_event.rpc("tuto_wait", {"names": waiting})

## Remise à zéro avant chaque manche (appelé par main.gd AVANT le tutoriel —
## surtout pas dans wait_tutorial_ready, qui peut démarrer APRÈS les premiers "prêt").
func reset_tutorial() -> void:
	_tuto_ready = {}

## Bloque le début de manche tant que tous les HUMAINS n'ont pas fini le tuto.
func wait_tutorial_ready() -> void:
	while true:
		var all_ready := true
		if seats.is_empty():
			all_ready = _tuto_ready.has(0)  # solo : un seul humain, siège 0.
		else:
			for i in seats.size():
				if int(seats[i]["peer"]) != -1 and not _tuto_ready.has(i):
					all_ready = false
		if all_ready:
			break
		await get_tree().create_timer(0.2).timeout
	EventBus.warmup = true  # place à l'échauffement (le match démarre après le compte à rebours).
	EventBus.tutorial_waiting.emit([])
	if active:
		net_event.rpc("tuto_go", {})

func bcast_countdown(n: int) -> void:
	if active:
		net_event.rpc("count", {"n": n})

# ---------------------------------------------------------------- Positions (15 Hz)

func _process(delta: float) -> void:
	if not active or characters.is_empty():
		return
	_transform_accumulator += delta
	if _transform_accumulator < TRANSFORM_RATE:
		return
	_transform_accumulator = 0.0
	if is_server:
		var batch := {}
		for i in characters.size():
			var c = characters[i]
			batch[i] = [c.position, c.rotation.y]
		net_transforms.rpc(batch)
	else:
		var mine = _char(my_seat)
		if mine != null:
			input_transform.rpc_id(1, mine.position, mine.rotation.y)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_transforms(batch: Dictionary) -> void:
	for seat in batch:
		if int(seat) == my_seat:
			continue  # ma position est locale (réactivité).
		var c = _char(int(seat))
		if c != null and c.is_alive():
			c.position = c.position.lerp(batch[seat][0], 0.35)
			c.rotation.y = lerp_angle(c.rotation.y, batch[seat][1], 0.35)

# ---------------------------------------------------------------- Voix

func send_voice(data: PackedByteArray) -> void:
	input_voice.rpc_id(1, data)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func input_voice(data: PackedByteArray) -> void:
	if is_server:
		var seat := _seat_of_sender()
		if seat >= 0:
			relay_voice(seat, data)

## L'hôte rediffuse la voix à tous (et l'écoute lui-même).
func relay_voice(seat: int, data: PackedByteArray) -> void:
	net_voice.rpc(seat, data)
	if seat != my_seat:
		Voice.receive(seat, data)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_voice(seat: int, data: PackedByteArray) -> void:
	Voice.receive(seat, data)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func input_transform(pos: Vector3, yaw: float) -> void:
	var c = _char(_seat_of_sender())
	if is_server and c != null and c.is_alive():
		c.position = Vector3(pos.x, 0, pos.z)
		c.rotation.y = yaw
		c.clamp_to_arena()
