extends Node3D
## main.gd — point d'entrée du prototype.
##
## Construit tout par code (environnement, arène, personnages, HUD) : aucun
## asset requis, le projet tourne dès l'ouverture. Quand les modèles Blender
## et les vraies scènes arriveront, ce fichier deviendra un simple assembleur
## de scènes — l'architecture (EventBus, modules) ne changera pas.

## Réglé par le menu principal (GameConfig) ; `-- players=N` prime pour les tests.
var player_count := 8

## La table s'adapte au nombre de joueurs : intime à 2, grande tablée à 8.
var seat_radius := 3.0
var table_radius := 2.2

## Nom + personnalité de chaque bot (7 bots + le joueur local = 8 à table).
var bot_roster := [
	{"name": "Gaston", "personality": BotBrain.Personality.MENTEUR},
	{"name": "Ginette", "personality": BotBrain.Personality.PEUREUX},
	{"name": "Kevin", "personality": BotBrain.Personality.AGRESSIF},
	{"name": "Perceval", "personality": BotBrain.Personality.CALCULATEUR},
	{"name": "Momo", "personality": BotBrain.Personality.TROLL},
	{"name": "Jacqueline", "personality": BotBrain.Personality.PRUDENT},
	{"name": "Bob", "personality": BotBrain.Personality.TROLL},
]

var turn_manager: TurnManager
var local_player: CharacterBase
var _deck_material: StandardMaterial3D
var _match_over := false
var _autoplay := false
var _fire_light: OmniLight3D
var _fire_time := 0.0
var _chandelier: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _lamp_light: OmniLight3D
var _blackout_active := false
var _flames: Array[MeshInstance3D] = []
var _flame_phases: Array[float] = []
var _blossoms: Array[MeshInstance3D] = []

func _process(delta: float) -> void:
	_fire_time += delta
	# Feu de cheminée qui vacille : deux sinus désaccordés ≈ flamme vivante.
	if _fire_light != null and not _blackout_active:
		_fire_light.light_energy = 1.4 + sin(_fire_time * 7.0) * 0.2 + sin(_fire_time * 13.7) * 0.12
	# Le lustre oscille imperceptiblement — la pièce respire.
	if _chandelier != null:
		_chandelier.rotation.z = sin(_fire_time * 0.8) * 0.025
		_chandelier.rotation.x = sin(_fire_time * 0.63) * 0.02
	# Bougies et torches : chaque flamme danse avec sa propre phase.
	for i in _flames.size():
		var flicker := 1.0 + sin(_fire_time * 9.0 + _flame_phases[i]) * 0.2 \
			+ sin(_fire_time * 15.3 + _flame_phases[i] * 2.0) * 0.1
		_flames[i].scale = Vector3(flicker, flicker * 1.15, flicker)

func _ready() -> void:
	randomize()
	# Outils de test/équilibrage : `godot --headless . -- autoplay turbo`
	# autoplay : un bot joue à la place du joueur local (simulation de partie).
	# turbo    : temps accéléré x10 pour simuler des parties entières.
	player_count = Net.seats.size() if Net.active else GameConfig.player_count
	var user_args := OS.get_cmdline_user_args()
	_autoplay = "autoplay" in user_args
	if "turbo" in user_args:
		Engine.time_scale = 10.0
	if not Net.active:
		for arg in user_args:
			if arg.begins_with("players="):
				player_count = clampi(arg.get_slice("=", 1).to_int(), 2, 8)
			elif arg.begins_with("mode="):
				GameConfig.mode = arg.get_slice("=", 1)
			elif arg.begins_with("difficulty="):
				GameConfig.difficulty = arg.get_slice("=", 1)
			elif arg.begins_with("sd="):
				GameConfig.sudden_death_seconds = arg.get_slice("=", 1).to_float()
	# Enchaînés et Équipes demandent au moins 4 joueurs pour avoir du sens.
	if GameConfig.mode in ["chains", "teams"] and player_count < 4:
		GameConfig.mode = "ffa"
	seat_radius = 2.0 + (player_count - 2) * (1.0 / 6.0)  # 2.0 m à 2 → 3.0 m à 8.
	table_radius = seat_radius - 0.8
	Audio.stop_music()  # fin de l'ambiance de bar : place à la tension.
	EventBus.flower_taken = false  # une nouvelle partie, une nouvelle fleur.
	EventBus.match_started = false  # verrouillé jusqu'à la fin du tutoriel.
	EventBus.warmup = false
	Net.reset_tutorial()
	EventBus.flower_picked.connect(_on_flower_picked)
	_register_inputs()
	_build_environment()
	_build_arena()
	var characters := _spawn_characters()
	_build_hud()

	EventBus.match_ended.connect(func(_winner) -> void: _match_over = true)
	EventBus.director_event.connect(_on_director_event)
	# Électrocution : l'écran de la victime tremble (bzzzt).
	EventBus.player_damaged.connect(func(victim, _amount: int, source: String) -> void:
		if victim == local_player and source == "Électrocution":
			_event_table_shake())
	# La pioche s'illumine quand c'est au joueur local de jouer.
	EventBus.turn_started.connect(func(who) -> void:
		_deck_material.emission_enabled = who == local_player)
	EventBus.card_drawn.connect(func(_who, _card: Dictionary) -> void:
		_deck_material.emission_enabled = false)

	# En réseau : enregistre les personnages (relais d'événements / marionnettes).
	# En solo : référence directe (audio, écran de fin…). TOUJOURS renseigné.
	if Net.active:
		Net.match_begin(characters)
	else:
		Net.characters = characters

	# Mode Les Enchaînés : appariement secret, uniquement chez l'hôte.
	if GameConfig.mode == "chains" and Net.is_server:
		var chains := preload("res://src/core/chain_mode.gd").new()
		add_child(chains)
		chains.setup(characters)

	# Mode Équipes : répartition alternée (équilibrée d'office), sur CHAQUE
	# machine (déterministe par siège — aucune synchro supplémentaire).
	if GameConfig.mode == "teams":
		for i in characters.size():
			characters[i].set_team(i % 2)
		if Net.is_server:
			var reds: Array[String] = []
			var blues: Array[String] = []
			for i in characters.size():
				(reds if i % 2 == 0 else blues).append(characters[i].display_name)
			EventBus.log_public.emit(Lang.t("⚔️ 🔴 Équipe Rouge : %s") % ", ".join(reds))
			EventBus.log_public.emit(Lang.t("⚔️ 🔵 Équipe Bleue : %s") % ", ".join(blues))
			EventBus.log_public.emit(Lang.t("⚔️ Dernière équipe debout gagne. Le tir ami existe. Bonne chance."))

	# Menu pause (Échap) : options et sorties — la partie continue derrière.
	add_child(preload("res://src/ui/pause_menu.gd").new())

	# Mini-jeu de vol à la tire (crochetage des sacs).
	add_child(preload("res://src/ui/steal_minigame.gd").new())

	# Tutoriel d'avant-partie : flèches sur les éléments clés, lecture libre.
	var tutorial: CanvasLayer = preload("res://src/ui/tutorial.gd").new()
	tutorial.targets = {
		"deck": Vector3(0, 1.35, 0),
		"rocks": local_player.rock_pile_position + Vector3(0, 0.25, 0),
		"flower": _polar(0.0, 9.7, 1.3),
		"billiard": _polar(deg_to_rad(70), 7.2, 1.4),
		"barman": _polar(deg_to_rad(250), 9.3, 2.5),
	}
	add_child(tutorial)

	# La logique de partie ne tourne que chez l'hôte (ou en solo).
	if Net.is_server:
		turn_manager = TurnManager.new()
		add_child(turn_manager)
		# Le Game Director veille : deux parties ne se ressembleront jamais.
		add_child(preload("res://src/core/game_director.gd").new())
		if Net.active:
			await Net.wait_for_clients(8.0)
		# La manche ne démarre que quand TOUS les humains ont fini le tutoriel.
		await Net.wait_tutorial_ready()
		# Échauffement : 10 s de cailloux gratuits (personne ne peut mourir)…
		for n in range(10, 0, -1):
			EventBus.countdown_tick.emit(n)
			Net.bcast_countdown(n)
			await get_tree().create_timer(1.0).timeout
		# …puis chacun reprend sa place, PV à 100 %, et c'est parti.
		EventBus.warmup = false
		EventBus.match_started = true
		for character in characters:
			character.reset_for_match()
		EventBus.countdown_tick.emit(0)
		Net.bcast_countdown(0)
		await get_tree().create_timer(0.8).timeout
		turn_manager.start_match(characters)

func _unhandled_input(event: InputEvent) -> void:
	# Fin de partie : R pour rejouer (mêmes réglages), M pour revenir au menu.
	if _match_over and event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.physical_keycode == KEY_M:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")

# ---------------------------------------------------------------- Entrées

## Les actions sont déclarées par code : lisible en revue, zéro risque de
## désynchronisation entre project.godot et les scripts.
func _register_inputs() -> void:
	_add_key_action("draw_card", KEY_SPACE)
	_add_key_action("emote_1", KEY_1)
	_add_key_action("emote_2", KEY_2)
	_add_key_action("emote_3", KEY_3)
	_add_key_action("emote_4", KEY_4)
	# Touches PHYSIQUES : WASD devient naturellement ZQSD sur un clavier AZERTY.
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("toggle_stand", KEY_E)
	_add_key_action("reveal_card", KEY_R)
	_add_key_action("open_chat", KEY_T)

func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

# ---------------------------------------------------------------- Décor

func _build_environment() -> void:
	# Ambiance "cave de bar" : fond sombre, lampe chaude au-dessus de la table.
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.5)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.5
	add_child(sun)

	# Lustre suspendu = un GROUPE qui oscille doucement (voir _process).
	_chandelier = Node3D.new()
	_chandelier.position = Vector3(0, 4.5, 0)
	add_child(_chandelier)

	var lamp := OmniLight3D.new()
	_lamp_light = lamp
	lamp.position = Vector3(0, -1.3, 0)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 3.0
	lamp.omni_range = 9.0
	# Une seule lumière avec ombres : lisible et pas cher sur GPU. Mais en rendu
	# LOGICIEL (llvmpipe : WSLg, VM sans GPU…), les ombres coûtent très cher → off.
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	lamp.shadow_enabled = not ("llvmpipe" in adapter or "swiftshader" in adapter)
	_chandelier.add_child(lamp)

	# Habillage de la pièce : mur circulaire (vu de l'intérieur) et plafond.
	var wall := MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = 10.5
	wall_mesh.bottom_radius = 10.5
	wall_mesh.height = 4.5
	wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.17, 0.12, 0.1)
	wall_mat.roughness = 1.0
	wall_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # on rend les faces INTÉRIEURES.
	wall.material_override = wall_mat
	wall.position = Vector3(0, 2.25, 0)
	add_child(wall)

	var ceiling := CylinderMesh.new()
	ceiling.top_radius = 10.7
	ceiling.bottom_radius = 10.7
	ceiling.height = 0.1
	_add_mesh(ceiling, Vector3(0, 4.55, 0), Color(0.1, 0.08, 0.07))

	# Visuels du lustre, attachés au groupe oscillant.
	var cord := CylinderMesh.new()
	cord.top_radius = 0.015
	cord.bottom_radius = 0.015
	cord.height = 1.1
	_add_mesh(cord, Vector3(0, -0.55, 0), Color(0.05, 0.05, 0.05), _chandelier)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.06
	shade.bottom_radius = 0.5
	shade.height = 0.35
	_add_mesh(shade, Vector3(0, -1.08, 0), Color(0.16, 0.28, 0.2), _chandelier)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.09
	bulb_mesh.height = 0.18
	var bulb := _add_mesh(bulb_mesh, Vector3(0, -1.28, 0), Color(1.0, 0.9, 0.7), _chandelier)
	var bulb_mat := bulb.material_override as StandardMaterial3D
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_energy_multiplier = 2.0

func _build_arena() -> void:
	# Sol + grand tapis rond sous la table.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(24, 24)
	_add_mesh(floor_mesh, Vector3.ZERO, Color(0.16, 0.12, 0.10))

	# Colliders sol + plateau : les objets physiques (poulets…) s'y posent.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var table_body := StaticBody3D.new()
	var table_shape := CollisionShape3D.new()
	var table_cylinder := CylinderShape3D.new()
	table_cylinder.radius = table_radius
	table_cylinder.height = 1.06
	table_shape.shape = table_cylinder
	table_shape.position = Vector3(0, 0.53, 0)
	table_body.add_child(table_shape)
	add_child(table_body)
	var carpet := CylinderMesh.new()
	carpet.top_radius = table_radius * 2.1
	carpet.bottom_radius = table_radius * 2.1
	carpet.height = 0.02
	_add_mesh(carpet, Vector3(0, 0.012, 0), Color(0.33, 0.12, 0.11))

	# Pied et plateau de la table — dimensionnés selon le nombre de joueurs.
	var leg := CylinderMesh.new()
	leg.top_radius = table_radius * 0.16
	leg.bottom_radius = table_radius * 0.23
	leg.height = 0.95
	_add_mesh(leg, Vector3(0, 0.475, 0), Color(0.25, 0.16, 0.1))

	var top := CylinderMesh.new()
	top.top_radius = table_radius
	top.bottom_radius = table_radius
	top.height = 0.12
	_add_mesh(top, Vector3(0, 1.0, 0), Color(0.45, 0.28, 0.15))

	# Tapis de feutre vert, comme une table de poker.
	var felt := CylinderMesh.new()
	felt.top_radius = table_radius - 0.3
	felt.bottom_radius = table_radius - 0.3
	felt.height = 0.02
	_add_mesh(felt, Vector3(0, 1.07, 0), Color(0.13, 0.35, 0.2))

	# La pioche, au centre de la table — cliquable (raycast depuis la caméra).
	var deck := BoxMesh.new()
	deck.size = Vector3(0.3, 0.08, 0.42)
	var deck_visual := _add_mesh(deck, Vector3(0, 1.12, 0), Color(0.9, 0.88, 0.85))
	_deck_material = deck_visual.material_override as StandardMaterial3D
	_deck_material.emission = Color(0.85, 0.6, 0.2)

	var deck_body := StaticBody3D.new()
	deck_body.add_to_group("deck")
	deck_body.position = Vector3(0, 1.12, 0)
	var deck_shape := CollisionShape3D.new()
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(0.45, 0.25, 0.55)  # un peu plus grand : facile à viser.
	deck_shape.shape = deck_box
	deck_body.add_child(deck_shape)
	add_child(deck_body)

	_build_tavern_props()

## Habillage de taverne : tout en primitives, une seule lumière ajoutée (le feu).
func _build_tavern_props() -> void:
	var wood_dark := Color(0.2, 0.13, 0.09)
	var wood := Color(0.3, 0.19, 0.12)

	# Piliers contre le mur + poutres au plafond.
	for i in 8:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.22
		pillar.bottom_radius = 0.26
		pillar.height = 4.5
		_add_mesh(pillar, _polar(TAU * i / 8.0, 10.1, 2.25), wood_dark)
	for i in 3:
		var beam := BoxMesh.new()
		beam.size = Vector3(20.5, 0.25, 0.3)
		var beam_visual := _add_mesh(beam, Vector3(0, 4.35, 0), wood_dark)
		beam_visual.rotation_degrees = Vector3(0, 60.0 * i, 0)

	# Cheminée (angle 90°) : conduit, âtre sombre, braises émissives, feu vacillant.
	var fire_angle := TAU * 0.25
	var chimney := BoxMesh.new()
	chimney.size = Vector3(2.4, 4.5, 1.0)
	var chimney_visual := _add_mesh(chimney, _polar(fire_angle, 10.0, 2.25), Color(0.28, 0.24, 0.22))
	chimney_visual.rotation.y = fire_angle
	var hearth := BoxMesh.new()
	hearth.size = Vector3(1.4, 1.2, 0.5)
	var hearth_visual := _add_mesh(hearth, _polar(fire_angle, 9.55, 0.6), Color(0.05, 0.04, 0.04))
	hearth_visual.rotation.y = -fire_angle
	var embers := BoxMesh.new()
	embers.size = Vector3(1.0, 0.5, 0.3)
	var embers_visual := _add_mesh(embers, _polar(fire_angle, 9.4, 0.35), Color(1.0, 0.45, 0.1))
	embers_visual.rotation.y = -fire_angle
	var embers_material := embers_visual.material_override as StandardMaterial3D
	embers_material.emission_enabled = true
	embers_material.emission = Color(1.0, 0.4, 0.08)
	embers_material.emission_energy_multiplier = 2.5
	_fire_light = OmniLight3D.new()
	_fire_light.position = _polar(fire_angle, 9.0, 0.9)
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.omni_range = 7.0
	add_child(_fire_light)

	# Tonneaux empilés (angle 160°).
	var barrel_positions := [
		_polar(deg_to_rad(160), 9.2, 0.55), _polar(deg_to_rad(168), 9.3, 0.55),
		_polar(deg_to_rad(164), 9.25, 1.55),
	]
	for barrel_position in barrel_positions:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.42
		barrel.bottom_radius = 0.42
		barrel.height = 1.1
		_add_mesh(barrel, barrel_position, wood)
		var hoop := CylinderMesh.new()
		hoop.top_radius = 0.44
		hoop.bottom_radius = 0.44
		hoop.height = 0.06
		_add_mesh(hoop, barrel_position, Color(0.15, 0.14, 0.13))

	# Tables du fond avec leurs tabourets (angles 20° et 300°).
	for table_angle in [deg_to_rad(20), deg_to_rad(300)]:
		var table_center := _polar(table_angle, 8.2, 0.0)
		var small_leg := CylinderMesh.new()
		small_leg.top_radius = 0.08
		small_leg.bottom_radius = 0.12
		small_leg.height = 0.85
		_add_mesh(small_leg, table_center + Vector3(0, 0.425, 0), wood_dark)
		var small_top := CylinderMesh.new()
		small_top.top_radius = 0.75
		small_top.bottom_radius = 0.75
		small_top.height = 0.08
		_add_mesh(small_top, table_center + Vector3(0, 0.89, 0), wood)
		for stool_offset in [Vector3(0.9, 0, 0.3), Vector3(-0.5, 0, -0.9)]:
			var prop_stool := CylinderMesh.new()
			prop_stool.top_radius = 0.24
			prop_stool.bottom_radius = 0.24
			prop_stool.height = 0.5
			_add_mesh(prop_stool, table_center + stool_offset + Vector3(0, 0.25, 0), wood_dark)
		# Une chope oubliée sur la table.
		var forgotten_mug := CylinderMesh.new()
		forgotten_mug.top_radius = 0.07
		forgotten_mug.bottom_radius = 0.07
		forgotten_mug.height = 0.14
		_add_mesh(forgotten_mug, table_center + Vector3(0.2, 1.0, 0.1), Color(0.7, 0.65, 0.55))

	# LE BAR (angle 250°) : comptoir, verres, et son barman irascible.
	var shelf_angle := deg_to_rad(250)
	var bar_top := BoxMesh.new()
	bar_top.size = Vector3(3.4, 0.12, 0.6)
	var bar_top_visual := _add_mesh(bar_top, _polar(shelf_angle, 8.5, 1.02), wood)
	bar_top_visual.rotation.y = shelf_angle
	var bar_front := BoxMesh.new()
	bar_front.size = Vector3(3.4, 1.0, 0.1)
	var bar_front_visual := _add_mesh(bar_front, _polar(shelf_angle, 8.25, 0.5), wood_dark)
	bar_front_visual.rotation.y = shelf_angle
	# Quelques verres propres alignés sur le comptoir (son œuvre, NE PAS TOUCHER).
	var bar_side := Vector3(cos(shelf_angle), 0, -sin(shelf_angle))
	for i in 3:
		var clean_glass := CylinderMesh.new()
		clean_glass.top_radius = 0.06
		clean_glass.bottom_radius = 0.045
		clean_glass.height = 0.13
		_add_mesh(clean_glass, _polar(shelf_angle, 8.5, 1.15) + bar_side * (i - 1.0) * 0.4,
			Color(0.8, 0.88, 0.92))

	# Zone de service : cliquer sur le comptoir/les verres = boire un coup (+1 PV).
	var drink_zone := StaticBody3D.new()
	drink_zone.add_to_group("bar_drink")
	drink_zone.position = _polar(shelf_angle, 8.5, 1.1)
	var drink_shape := CollisionShape3D.new()
	var drink_box := BoxShape3D.new()
	drink_box.size = Vector3(3.2, 0.5, 0.7)
	drink_shape.shape = drink_box
	drink_shape.rotation.y = shelf_angle
	drink_zone.add_child(drink_shape)
	add_child(drink_zone)

	var barman: Node3D = preload("res://src/decor/barman.gd").new()
	add_child(barman)
	barman.position = _polar(shelf_angle, 9.3, 0.0)
	barman.look_at(Vector3.ZERO, Vector3.UP)
	var shelf := BoxMesh.new()
	shelf.size = Vector3(2.2, 0.08, 0.35)
	var shelf_visual := _add_mesh(shelf, _polar(shelf_angle, 9.9, 2.0), wood_dark)
	shelf_visual.rotation.y = shelf_angle
	var bottle_colors := [Color(0.2, 0.5, 0.3), Color(0.5, 0.25, 0.15), Color(0.25, 0.3, 0.55), Color(0.55, 0.45, 0.2)]
	for i in bottle_colors.size():
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.045
		bottle.bottom_radius = 0.07
		bottle.height = 0.32
		var offset := Vector3(cos(shelf_angle) * (i - 1.5) * 0.45, 0, -sin(shelf_angle) * (i - 1.5) * 0.45)
		_add_mesh(bottle, _polar(shelf_angle, 9.9, 2.22) + offset, bottle_colors[i])

	# Tableaux PLAQUÉS au mur : rotation +angle pour être TANGENT au mur
	# (le signe négatif les mettait en diagonale).
	for painting_angle in [deg_to_rad(60), deg_to_rad(205), deg_to_rad(330)]:
		var frame := BoxMesh.new()
		frame.size = Vector3(1.3, 1.0, 0.06)
		var frame_visual := _add_mesh(frame, _polar(painting_angle, 10.42, 2.3), Color(0.65, 0.5, 0.2))
		frame_visual.rotation.y = painting_angle
		var canvas := BoxMesh.new()
		canvas.size = Vector3(1.1, 0.8, 0.07)
		var canvas_visual := _add_mesh(canvas, _polar(painting_angle, 10.38, 2.3), Color(0.16, 0.14, 0.2))
		canvas_visual.rotation.y = painting_angle

	# Anneau décoratif sur le tapis.
	var ring := CylinderMesh.new()
	ring.top_radius = table_radius * 1.6
	ring.bottom_radius = table_radius * 1.6
	ring.height = 0.022
	_add_mesh(ring, Vector3(0, 0.013, 0), Color(0.24, 0.09, 0.08))

	# Torches murales sur un pilier sur deux (flammes animées, sans lumière : pas cher).
	for i: int in [1, 3, 5, 7]:
		var torch_angle: float = TAU * i / 8.0
		var holder := BoxMesh.new()
		holder.size = Vector3(0.08, 0.25, 0.08)
		_add_mesh(holder, _polar(torch_angle, 9.85, 2.4), wood_dark)
		_add_flame(_polar(torch_angle, 9.85, 2.58))

	# Deux bougies sur la grande table.
	for candle_angle in [deg_to_rad(45), deg_to_rad(225)]:
		var candle := CylinderMesh.new()
		candle.top_radius = 0.03
		candle.bottom_radius = 0.035
		candle.height = 0.12
		_add_mesh(candle, _polar(candle_angle, table_radius * 0.55, 1.13), Color(0.9, 0.85, 0.7))
		_add_flame(_polar(candle_angle, table_radius * 0.55, 1.23))

	# Fausse porte d'entrée (angle 130°) : cadre, battant, poignée.
	var door_angle := deg_to_rad(130)
	var door_side := Vector3(cos(door_angle), 0, -sin(door_angle))
	var door_frame := BoxMesh.new()
	door_frame.size = Vector3(1.4, 2.7, 0.12)
	var door_frame_visual := _add_mesh(door_frame, _polar(door_angle, 10.4, 1.35), Color(0.16, 0.1, 0.07))
	door_frame_visual.rotation.y = door_angle
	var door_panel := BoxMesh.new()
	door_panel.size = Vector3(1.15, 2.45, 0.1)
	var door_panel_visual := _add_mesh(door_panel, _polar(door_angle, 10.34, 1.22), wood)
	door_panel_visual.rotation.y = door_angle
	var handle := SphereMesh.new()
	handle.radius = 0.05
	handle.height = 0.1
	_add_mesh(handle, _polar(door_angle, 10.26, 1.2) + door_side * 0.42, Color(0.75, 0.6, 0.25))

	# Canapés en tissu rouge, tournés vers la salle.
	for sofa_angle in [deg_to_rad(115), deg_to_rad(180)]:
		var sofa_side := Vector3(cos(sofa_angle), 0, -sin(sofa_angle))
		var fabric := Color(0.42, 0.15, 0.14)
		var seat := BoxMesh.new()
		seat.size = Vector3(1.9, 0.42, 0.75)
		var seat_visual := _add_mesh(seat, _polar(sofa_angle, 9.2, 0.28), fabric)
		seat_visual.rotation.y = sofa_angle
		var backrest := BoxMesh.new()
		backrest.size = Vector3(1.9, 0.65, 0.2)
		var backrest_visual := _add_mesh(backrest, _polar(sofa_angle, 9.55, 0.72), fabric.darkened(0.15))
		backrest_visual.rotation.y = sofa_angle
		for arm_side in [-1.0, 1.0]:
			var armrest := BoxMesh.new()
			armrest.size = Vector3(0.22, 0.55, 0.75)
			var armrest_visual := _add_mesh(armrest,
				_polar(sofa_angle, 9.2, 0.4) + sofa_side * 0.95 * arm_side, fabric.darkened(0.1))
			armrest_visual.rotation.y = sofa_angle

	# Pots de fleurs : terre cuite + feuillage + UNE fleur rouge cliquable.
	# La fleur ne peut être cueillie qu'UNE fois par partie, par UN seul joueur.
	for pot_angle in [deg_to_rad(0), deg_to_rad(145), deg_to_rad(225), deg_to_rad(287)]:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.24
		pot.bottom_radius = 0.16
		pot.height = 0.32
		_add_mesh(pot, _polar(pot_angle, 9.7, 0.16), Color(0.55, 0.3, 0.2))
		var foliage := SphereMesh.new()
		foliage.radius = 0.32
		foliage.height = 0.64
		_add_mesh(foliage, _polar(pot_angle, 9.7, 0.58), Color(0.2, 0.42, 0.2))
		var foliage_top := SphereMesh.new()
		foliage_top.radius = 0.2
		foliage_top.height = 0.4
		_add_mesh(foliage_top, _polar(pot_angle, 9.7, 0.84), Color(0.24, 0.48, 0.22))
		var blossom := SphereMesh.new()
		blossom.radius = 0.06
		blossom.height = 0.1
		_blossoms.append(_add_mesh(blossom, _polar(pot_angle, 9.62, 1.0), Color(0.9, 0.2, 0.3)))

		var pot_body := StaticBody3D.new()
		pot_body.add_to_group("flower_pot")
		pot_body.position = _polar(pot_angle, 9.7, 0.5)
		var pot_shape := CollisionShape3D.new()
		var pot_capsule := CapsuleShape3D.new()
		pot_capsule.radius = 0.35
		pot_capsule.height = 1.1
		pot_shape.shape = pot_capsule
		pot_body.add_child(pot_shape)
		add_child(pot_body)

	# Le billard, dans le coin détente (jouable debout : viser une bille, cliquer).
	var billiard: Node3D = preload("res://src/decor/billiard.gd").new()
	add_child(billiard)
	billiard.position = _polar(deg_to_rad(70), 7.2, 0.0)
	billiard.rotation.y = deg_to_rad(70) + PI / 2.0  # dans le sens de la pièce.

	# Fripouille, le chat de la taverne : il erre, s'assoit, miaule parfois.
	var cat: Node3D = preload("res://src/decor/tavern_cat.gd").new()
	add_child(cat)
	cat.position = _polar(randf() * TAU, 7.0, 0.0)

func _polar(angle: float, radius: float, y: float) -> Vector3:
	return Vector3(sin(angle) * radius, y, cos(angle) * radius)

# ---------------------------------------------------------------- Événements du Director

## Chaque machine exécute localement la mise en scène demandée par l'hôte.
func _on_director_event(event_name: String) -> void:
	match event_name:
		"blackout":
			_event_blackout()
		"storm":
			_event_storm()
		"chickens":
			_event_chicken_rain()
		"shake":
			_event_table_shake()

## Noir complet 5 secondes : seules les braises rougeoient encore.
func _event_blackout() -> void:
	_blackout_active = true
	var lamp_energy := _lamp_light.light_energy
	var ambient := _env.ambient_light_energy
	var sun_energy := _sun.light_energy
	_lamp_light.light_energy = 0.0
	_env.ambient_light_energy = 0.04
	_sun.light_energy = 0.0
	_fire_light.light_energy = 0.15
	Audio.play("impact", -8.0)
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_lamp_light, "light_energy", lamp_energy, 1.2)
	tween.tween_property(_env, "ambient_light_energy", ambient, 1.2)
	tween.tween_property(_sun, "light_energy", sun_energy, 1.2)
	tween.chain().tween_callback(func() -> void: _blackout_active = false)
	EventBus.log_public.emit(Lang.t("💡 La lumière revient…"))

## Trois éclairs qui blanchissent la salle, avec le tonnerre.
func _event_storm() -> void:
	var ambient := _env.ambient_light_energy
	for i in 3:
		_env.ambient_light_energy = 2.8
		Audio.play("thunder", -4.0 - i * 2.0)
		await get_tree().create_timer(0.1).timeout
		_env.ambient_light_energy = ambient
		await get_tree().create_timer(randf_range(0.3, 0.9)).timeout
		if not is_inside_tree():
			return

## Une pluie de poulets physiques. Parce que pourquoi pas.
func _event_chicken_rain() -> void:
	for i in 8:
		var chicken := RigidBody3D.new()
		chicken.mass = 0.3
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.14
		shape.shape = sphere
		chicken.add_child(shape)
		var body := MeshInstance3D.new()
		var body_mesh := SphereMesh.new()
		body_mesh.radius = 0.14
		body_mesh.height = 0.26
		body.mesh = body_mesh
		var feathers := StandardMaterial3D.new()
		feathers.albedo_color = Color(0.95, 0.93, 0.88)
		body.material_override = feathers
		chicken.add_child(body)
		var beak := MeshInstance3D.new()
		var beak_mesh := CylinderMesh.new()
		beak_mesh.top_radius = 0.001
		beak_mesh.bottom_radius = 0.04
		beak_mesh.height = 0.09
		beak.mesh = beak_mesh
		var beak_mat := StandardMaterial3D.new()
		beak_mat.albedo_color = Color(0.95, 0.6, 0.15)
		beak.material_override = beak_mat
		beak.position = Vector3(0, 0.02, -0.15)
		beak.rotation_degrees = Vector3(-90, 0, 0)
		chicken.add_child(beak)
		add_child(chicken)
		var drop_angle := randf() * TAU
		var drop_radius := randf_range(0.5, 4.5)
		chicken.global_position = Vector3(sin(drop_angle) * drop_radius, randf_range(3.6, 4.3),
			cos(drop_angle) * drop_radius)
		chicken.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		if i % 3 == 0:
			Audio.play_at("poule", chicken.global_position, -4.0)
		# Chaque poulet repart comme il est venu, six secondes plus tard.
		get_tree().create_timer(6.0 + i * 0.2).timeout.connect(chicken.queue_free)
		await get_tree().create_timer(randf_range(0.1, 0.35)).timeout
		if not is_inside_tree():
			return

## La caméra locale tremble — où qu'elle soit (assis, debout, spectateur).
func _event_table_shake() -> void:
	Audio.play("thunder", -6.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var tween := create_tween()
	for i in 8:
		tween.tween_property(camera, "v_offset", 0.05 if i % 2 == 0 else -0.05, 0.05)
	tween.tween_property(camera, "v_offset", 0.0, 0.08)

## La fleur unique est cueillie : toutes les autres se fanent aussitôt.
func _on_flower_picked(_character) -> void:
	for blossom in _blossoms:
		if is_instance_valid(blossom):
			blossom.visible = false

func _add_mesh(mesh: Mesh, pos: Vector3, color: Color, parent: Node = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	instance.material_override = material
	instance.position = pos
	(parent if parent != null else self).add_child(instance)
	return instance

## Petite flamme émissive (bougie, torche) — animée dans _process.
func _add_flame(pos: Vector3) -> void:
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.035
	flame_mesh.height = 0.09
	var flame := _add_mesh(flame_mesh, pos, Color(1.0, 0.75, 0.3))
	var material := flame.material_override as StandardMaterial3D
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.15)
	material.emission_energy_multiplier = 2.2
	_flames.append(flame)
	_flame_phases.append(randf() * TAU)

# ---------------------------------------------------------------- Joueurs

func _spawn_characters() -> Array:
	var characters: Array = []
	var palette := GameConfig.PLAYER_COLORS
	var my_id := multiplayer.get_unique_id()
	for i in player_count:
		var is_bot: bool
		var is_local: bool
		var display_name: String
		var color: Color
		var hat := -1  # -1 = chapeau automatique (bots).
		if Net.active:
			var seat: Dictionary = Net.seats[i]
			is_bot = int(seat["peer"]) == -1
			is_local = int(seat["peer"]) == my_id
			display_name = seat["name"]
			color = palette[int(seat["color"]) % palette.size()]
			if not is_bot:
				hat = int(seat.get("hat", 0))
		else:
			is_bot = i != 0
			is_local = i == 0
			display_name = bot_roster[i - 1]["name"] if is_bot else GameConfig.player_name
			# Le joueur local reçoit SA couleur ; les bots se partagent le reste.
			color = palette[(GameConfig.color_index + i) % palette.size()]
			if is_local:
				hat = GameConfig.selected_hat
		var character := CharacterBase.new()
		character.setup(display_name, color, is_bot)
		character.hat_id = hat
		add_child(character)

		# Placement en cercle autour de la table, face au centre.
		var angle := TAU * i / player_count
		character.position = Vector3(sin(angle) * seat_radius, 0, cos(angle) * seat_radius)
		character.look_at(Vector3.ZERO, Vector3.UP)
		character.store_seat()  # sa place attitrée, pour y revenir après une virée.
		character.walk_radius_min = table_radius + 0.55  # on contourne LA table, quelle que soit sa taille.

		# Tabouret derrière chaque place (le personnage se tient devant).
		var pile_direction := Vector3(sin(angle), 0, cos(angle))
		var stool_pos := pile_direction * (seat_radius + 0.55)
		var stool_leg := CylinderMesh.new()
		stool_leg.top_radius = 0.07
		stool_leg.bottom_radius = 0.13
		stool_leg.height = 0.5
		_add_mesh(stool_leg, stool_pos + Vector3(0, 0.25, 0), Color(0.24, 0.15, 0.1))
		var stool_seat := CylinderMesh.new()
		stool_seat.top_radius = 0.3
		stool_seat.bottom_radius = 0.3
		stool_seat.height = 0.07
		_add_mesh(stool_seat, stool_pos + Vector3(0, 0.53, 0), Color(0.32, 0.2, 0.13))

		# La chope de chaque joueur, posée près de son bord de table.
		var side := Vector3(pile_direction.z, 0, -pile_direction.x)
		var mug := CylinderMesh.new()
		mug.top_radius = 0.07
		mug.bottom_radius = 0.075
		mug.height = 0.16
		_add_mesh(mug, pile_direction * (table_radius - 0.25) + side * 0.35 + Vector3(0, 1.14, 0),
			Color(0.72, 0.66, 0.55))

		# Petit tas de cailloux devant sa place : munitions anti-lambin.
		var pile_position := pile_direction * (table_radius - 0.2) + Vector3(0, 1.09, 0)
		character.rock_pile_position = pile_position
		for j in 3:
			var pebble := SphereMesh.new()
			pebble.radius = 0.035
			pebble.height = 0.07
			_add_mesh(pebble, pile_position + Vector3(
				randf_range(-0.06, 0.06), 0, randf_range(-0.06, 0.06)),
				Color(0.45, 0.44, 0.42))

		if is_bot:
			# L'IA ne tourne que chez l'hôte : les clients voient des marionnettes.
			if Net.is_server:
				var brain := BotBrain.new()
				brain.personality = bot_roster[(i - 1) % bot_roster.size()]["personality"]
				character.add_child(brain)
		elif is_local:
			local_player = character
			# Nom/émote au-dessus de SA tête : inutile et gênant pour sa caméra.
			character.set_overhead_visible(false)
			# Sa tête ne suit pas la table : c'est la souris qui pilote son regard.
			character.set_gaze_enabled(false)
			# Première personne : caméra À LA PLACE des yeux, tête masquée pour soi.
			var camera := Camera3D.new()
			camera.position = Vector3(0, 1.30, -0.02)
			camera.rotation_degrees = Vector3(-10, 0, 0)
			character.add_child(camera)
			camera.current = true
			character.hide_head_from_camera(camera)
			var controller := PlayerController.new()
			controller.camera = camera
			character.add_child(controller)
			if _autoplay:
				character.add_child(BotBrain.new())

		characters.append(character)
	return characters

func _build_hud() -> void:
	var hud := Hud.new()
	hud.local_player = local_player
	add_child(hud)
