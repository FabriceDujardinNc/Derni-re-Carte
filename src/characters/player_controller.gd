class_name PlayerController
extends Node
## PlayerController — entrées du joueur local (souris + clavier).
##
## Prototype "assis à table" : regard libre à la souris, ESPACE pour piocher,
## touches 1-4 pour les émotes. Le déplacement libre viendra dans une phase
## ultérieure (lobby / arène) — ici tout le gameplay se joue autour de la table.

const MOUSE_SENSITIVITY := 0.003
const EMOTES: Array[String] = ["😀", "😂", "😱", "🤫"]
const WALK_SPEED := 3.0
const KEY_TURN_SPEED := 2.4  ## rad/s — rotation au clavier (Q/D assis).
const SPY_RANGE := 2.5  ## Distance pour lire la manche d'un joueur dont on voit le dos.

var camera: Camera3D  ## Assignée par main.gd avant l'ajout à l'arbre.

@onready var character: CharacterBase = get_parent()

var _pitch := 0.0
var _selected_card := 0  ## Emplacement sélectionné dans la main (molette).
var _last_spied: Node3D = null  ## Dernière victime d'espionnage (anti-spam du journal).
var _spectating := false
var _orbit_yaw := 0.0
var _orbit_pitch := -0.6
var _orbit_radius := 7.0

var _match_over := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch = camera.rotation.x
	character.health.died.connect(_enter_spectator)
	EventBus.match_ended.connect(func(_winner) -> void: _match_over = true)

## Mort ? On regarde la fin du match en spectateur : caméra orbitale au-dessus
## de la table (souris pour tourner, molette pour zoomer).
func _enter_spectator(_cause: String) -> void:
	if _spectating:
		return
	_spectating = true
	# On laisse la chute comique se jouer, puis la caméra prend son envol.
	await get_tree().create_timer(1.4).timeout
	if not is_inside_tree():
		return
	camera.reparent(get_tree().current_scene)
	_orbit_yaw = character.rotation.y + PI
	EventBus.log_private.emit(character, "👻 Mode spectateur — souris : orbiter · molette : zoomer.")
	_update_orbit()

func _update_orbit() -> void:
	var target := Vector3(0, 1.0, 0)
	# La caméra reste DANS la pièce : jamais dans le plafond (4.5 m) ni les murs (10.5 m).
	var height := clampf(-sin(_orbit_pitch) * _orbit_radius, 0.6, 3.4)
	var flat := minf(cos(_orbit_pitch) * _orbit_radius, 9.0)
	camera.global_position = target + Vector3(sin(_orbit_yaw) * flat, height, cos(_orbit_yaw) * flat)
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	# Menu pause ouvert : aucune entrée gameplay (le menu gère Échap lui-même).
	if EventBus.pause_open:
		return

	# Si la souris s'est échappée de la fenêtre, un clic la verrouille à nouveau.
	# (Sauf en fin de partie : la souris doit rester libre pour les boutons.)
	if event is InputEventMouseButton and event.pressed and not _match_over \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Regard libre (le langage corporel passe aussi par "où on regarde").
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENSITIVITY * GameConfig.mouse_sensitivity
		if _spectating:
			_orbit_yaw -= event.relative.x * sensitivity
			_orbit_pitch = clampf(_orbit_pitch - event.relative.y * sensitivity, -1.4, -0.15)
			_update_orbit()
			return
		character.rotate_y(-event.relative.x * sensitivity)
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.1, 0.6)
		camera.rotation.x = _pitch
		return

	# (Échap est géré par le menu pause.)

	# Spectateur : seule la molette (zoom) reste active.
	if _spectating:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_orbit_radius = maxf(4.0, _orbit_radius - 0.7)
				_update_orbit()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_orbit_radius = minf(13.0, _orbit_radius + 0.7)
				_update_orbit()
		return

	if not character.is_alive():
		return

	# Piocher (le TurnManager vérifie que c'est bien notre tour).
	if event.is_action_pressed("draw_card"):
		EventBus.draw_requested.emit(character)
		return

	# R : révéler volontairement sa carte (pendant la fenêtre de réaction).
	if event.is_action_pressed("reveal_card"):
		if Net.client_mode():
			Net.send_reveal()
		else:
			character.reveal_card()
		return

	# E : se lever pour espionner / retourner s'asseoir.
	if event.is_action_pressed("toggle_stand"):
		if character.is_seated:
			character.stand_up()
		elif not character.auto_moving:
			character.return_to_seat()
		return

	# Souris : clic gauche = piocher (pioche visée) ou GIFLER un joueur debout,
	# clic droit = utiliser la carte sélectionnée, molette = choisir la carte.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _is_aiming_at_deck():
					EventBus.draw_requested.emit(character)
				else:
					var ball = _aimed_ball()
					var barman = _aimed_barman()
					var victim = _aimed_character()
					if ball != null:
						# Billard : frappe dans la direction du regard.
						var direction := -camera.global_basis.z
						if Net.client_mode():
							Net.send_billiard(ball.get_meta("index"), direction)
						else:
							ball.get_parent().strike(ball, direction, character)
					elif _is_aiming_at_pot():
						# Cueillir l'unique fleur de la partie.
						if Net.client_mode():
							Net.send_flower_pick()
						else:
							character.pick_flower()
					elif _is_aiming_at_bar():
						# Un petit verre au comptoir (+1 PV).
						if Net.client_mode():
							Net.send_drink()
						else:
							character.drink()
					elif victim != null and character.has_flower:
						# Offrir sa fleur passe avant la baston.
						if Net.client_mode():
							Net.send_flower_offer(Net.seat_of(victim))
						else:
							character.offer_flower(victim)
					elif barman != null:
						# Déranger le barman. Mauvaise idée. Vraiment.
						if Net.client_mode():
							Net.send_barman()
						else:
							barman.poke(character)
					elif victim != null:
						# À portée de bras → gifle ; sinon → caillou (debout ou lambin).
						# En réseau client, c'est l'hôte qui tranche.
						if Net.client_mode():
							Net.send_melee(Net.seat_of(victim))
						elif not character.try_slap(victim):
							character.throw_rock(victim)
			MOUSE_BUTTON_RIGHT:
				_use_selected_card()
			MOUSE_BUTTON_WHEEL_UP:
				_select_card(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_select_card(1)
		return

	# Émotes 1-4 — utilisables à tout moment : c'est un outil de bluff.
	for i in EMOTES.size():
		if event.is_action_pressed("emote_%d" % (i + 1)):
			character.play_emote(EMOTES[i])
			return

func _process(delta: float) -> void:
	if not character.is_alive() or EventBus.pause_open:
		return
	# L'espionnage est GÉOMÉTRIQUE : assis ou debout, on lit la manche de
	# quiconque nous montre son dos d'assez près.
	_peek_at_nearby_hand()
	# Assis : Q/D pivotent le regard, comme la souris (parfois capricieuse).
	if character.is_seated:
		var turn := Input.get_axis("move_right", "move_left")
		if turn != 0.0:
			character.rotate_y(turn * KEY_TURN_SPEED * delta)
		return
	if character.auto_moving:
		return
	# Marche libre (ZQSD/WASD — touches physiques, indépendantes du clavier).
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input != Vector2.ZERO:
		var direction := (character.global_basis * Vector3(input.x, 0, input.y)).normalized()
		character.position += direction * WALK_SPEED * delta
		character.position.y = 0.0
		character.clamp_to_arena()

## DANS LE DOS d'un joueur, sa manche se révèle dans le journal — que l'on soit
## debout derrière lui… ou assis à côté quand il se tourne de l'autre côté !
## Se tourner protège d'un espion mais expose sa manche au voisin opposé.
func _peek_at_nearby_hand() -> void:
	var closest: Node3D = null
	var best_distance := SPY_RANGE
	for other in get_tree().get_nodes_in_group("characters"):
		if other == character or not other.is_alive():
			continue
		var distance: float = character.global_position.distance_to(other.global_position)
		if distance >= best_distance:
			continue
		# Suis-je derrière lui ? (angle entre son regard et ma position)
		var to_spy: Vector3 = (character.global_position - other.global_position).normalized()
		var target_forward: Vector3 = -other.global_basis.z
		if target_forward.dot(to_spy) > -0.2:
			continue  # il me fait face (ou presque) : manche illisible.
		best_distance = distance
		closest = other
	if closest == null or closest == _last_spied:
		if closest == null:
			_last_spied = null
		return
	_last_spied = closest
	var contents: Array[String] = []
	for card in closest.hand:
		contents.append("%s %s" % [card.get("emoji", ""), card.get("name", "?")])
	var summary := ", ".join(contents) if not contents.is_empty() else "rien du tout"
	EventBus.log_private.emit(character, "🔍 Tu jettes un œil au sac de %s : il contient %s."
		% [closest.display_name, summary])

func _select_card(direction: int) -> void:
	if character.hand.is_empty():
		return
	_selected_card = wrapi(_selected_card + direction, 0, character.hand.size())
	EventBus.hand_selected.emit(character, _selected_card)

## Utilise la carte sélectionnée : sur soi, ou sur le joueur visé si elle se lance.
func _use_selected_card() -> void:
	# Fleur en main + personne dans le viseur = on se l'offre à soi-même. 💅
	if character.has_flower and _aimed_character() == null:
		if Net.client_mode():
			Net.send_flower_offer(Net.my_seat)
		else:
			character.offer_flower(character)
		return
	if character.hand.is_empty():
		EventBus.log_private.emit(character, "🎴 Aucune carte en réserve.")
		return
	_selected_card = clampi(_selected_card, 0, character.hand.size() - 1)
	var card: Dictionary = character.hand[_selected_card]
	if card.get("targetable", false):
		var target = _aimed_character()
		if target == null or target == character:
			EventBus.log_private.emit(character,
				"🎯 Vise un joueur pour utiliser %s !" % card.get("name", "cette carte"))
			return
		if Net.client_mode():
			Net.send_use_card(_selected_card, Net.seat_of(target))
		else:
			character.use_card(_selected_card, target)
	elif Net.client_mode():
		Net.send_use_card(_selected_card, -1)
	else:
		character.use_card(_selected_card, character)
	_selected_card = 0
	EventBus.hand_selected.emit(character, _selected_card)

## Rayon depuis le centre de l'écran, en ignorant son propre corps.
func _raycast_from_camera(distance: float) -> Dictionary:
	var space := character.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [character.collision_body.get_rid()]
	return space.intersect_ray(query)

func _is_aiming_at_deck() -> bool:
	var hit := _raycast_from_camera(6.0)
	return not hit.is_empty() and hit.collider.is_in_group("deck")

## Renvoie le CharacterBase visé (vivant), ou null.
func _aimed_character():
	var hit := _raycast_from_camera(10.0)
	if hit.is_empty() or not hit.collider.is_in_group("character_body"):
		return null
	var target = hit.collider.get_meta("character")
	return target if target != null and target.is_alive() else null

## Renvoie la bille de billard visée (il faut être tout près pour jouer).
func _aimed_ball():
	var hit := _raycast_from_camera(3.5)
	if hit.is_empty():
		return null
	if hit.collider is RigidBody3D and hit.collider.is_in_group("billiard_ball"):
		return hit.collider
	return null

## Vise-t-on un pot de fleurs, d'assez près pour cueillir ?
func _is_aiming_at_pot() -> bool:
	var hit := _raycast_from_camera(3.0)
	return not hit.is_empty() and hit.collider.is_in_group("flower_pot")

## Vise-t-on le comptoir du bar, d'assez près pour boire ?
func _is_aiming_at_bar() -> bool:
	var hit := _raycast_from_camera(3.0)
	return not hit.is_empty() and hit.collider.is_in_group("bar_drink")

## Renvoie le barman si on le vise (il est loin derrière son comptoir).
func _aimed_barman():
	var hit := _raycast_from_camera(15.0)
	if hit.is_empty() or not hit.collider.is_in_group("barman_body"):
		return null
	return hit.collider.get_meta("barman")
