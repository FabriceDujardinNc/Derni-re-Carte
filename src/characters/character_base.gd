class_name CharacterBase
extends Node3D
## CharacterBase — un joueur autour de la table (humain ou bot).
##
## Avatar procédural "placeholder" en attendant les modèles Blender, mais le
## LANGAGE CORPOREL est déjà une mécanique de gameplay à part entière :
## - la tête suit le regard : chacun se tourne vers celui qui pioche ;
## - une vraie carte 3D est saisie et montée devant le visage — les autres
##   voient le DOS de la carte, seul son porteur voit ce qu'il regarde ;
## - paliers de blessure → teinte sombre, tremblements, halètement ;
## - émotes au-dessus de la tête, mort = chute en arrière avec rebond.
## Remplacer _build_visuals() par un vrai modèle ne change rien au gameplay.

var display_name := "?"
var color := Color.WHITE
var is_bot := true
var current_card: Dictionary = {}

signal seated  ## Émis quand le personnage vient de se rasseoir.

## Cartes gardées "dans la manche" (keepable). Contenu privé, existence publique.
const HAND_SIZE := 3
var hand: Array[Dictionary] = []

## Points d'audace : gagnés en RÉVÉLANT volontairement sa carte piochée.
## Cacher = garder l'info ; montrer = +1 point et un petit soin. Un dilemme.
const REVEAL_HEAL := 3
var points := 0
var _can_reveal := false

## La fleur unique de la partie (cueillie au pot, offerte à un joueur proche).
const FLOWER_HEAL := 30  # recevoir une fleur, ça requinque sérieusement.
const FLOWER_OFFER_RANGE := 2.4
var has_flower := false
var _carried_flower: Node3D
var _worn_flower: Node3D
var _bag_cards: Array[Node3D] = []  ## Mini-cartes visibles dans la poche du sac.

## Chaise = sanctuaire : assis, on ne peut être ni visé ni giflé.
## Debout, on peut espionner les cartes… et tout prendre sur la figure.
var is_seated := true
var seat_position := Vector3.ZERO
var seat_rotation := 0.0
var auto_moving := false  ## Déplacement scripté en cours (trajet d'espionnage/retour).

var walk_radius_min := 2.75    ## On ne traverse pas la table (rayon fixé par main.gd)…
const WALK_RADIUS_MAX := 9.0   ## …et on ne quitte pas l'arène.
const SLAP_DAMAGE := 5
const SLAP_RANGE := 1.8
const ROCK_DAMAGE := 3           # sur le lambin assis qui refuse de piocher
const ROCK_DAMAGE_STANDING := 6  # sur un joueur DEBOUT pendant le caillassage : ça ne pardonne pas

## Tas de cailloux devant sa place (posé sur la table, assigné par main.gd).
var rock_pile_position := Vector3.ZERO

var _slap_cooldown := 0.0
var _rock_cooldown := 0.0
var _drink_cooldown := 0.0
var _move_tween: Tween

var health: HealthComponent
var status: StatusManager
var collision_body: StaticBody3D  ## Pour viser ce joueur (raycast des lancers).

## Teinte "sang séché / suie" mélangée à la couleur de base selon le palier.
const STATE_DAMAGE_TINT := {100: 0.0, 75: 0.18, 50: 0.4, 25: 0.62, 10: 0.8}
## Amplitude des tremblements selon le palier.
const STATE_SHAKE := {100: 0.0, 75: 0.0, 50: 0.004, 25: 0.012, 10: 0.028}

## Pose des bras (rotation X de l'épaule, en degrés, positif = vers la table).
const ARM_REST := 50.0    # posés vers la table
const ARM_RAISED := 112.0 # main devant le visage (lecture de carte)

## Position de la carte tenue : au repos (posée devant soi) et levée (devant le visage).
const CARD_REST_POS := Vector3(0.3, 1.05, -0.45)
const CARD_RAISED_POS := Vector3(0.25, 1.42, -0.5)

var _body: MeshInstance3D
var _head_pivot: Node3D
var _mat: StandardMaterial3D
var _name_label: Label3D
var _emote_label: Label3D
var _card_label: Label3D
var _card_emoji_label: Label3D
var _turn_marker: Label3D      ## « À TOI ! » au-dessus de la tête, visible de tous.
var _talk_icon: Label3D        ## 🎤 pendant que ce joueur parle au micro.
var _chat_bubble: Label3D      ## 💬 bulle de dialogue (chat texte).
var _chat_tween: Tween
var _talk_hide_at := 0
var _overhead_visible := true
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _hand_r: Node3D
var _card_visual: Node3D

var _emote_tween: Tween
var _arm_tween: Tween
var _body_base_pos: Vector3
var _shake := 0.0
var _time := 0.0
var _holding_card := false
var _gaze_enabled := true
var _gaze_point := Vector3(0, 1.1, 0)  # par défaut : la pioche au centre.

func setup(p_name: String, p_color: Color, p_is_bot: bool) -> void:
	display_name = p_name
	color = p_color
	is_bot = p_is_bot

func _ready() -> void:
	add_to_group("characters")
	health = HealthComponent.new()
	add_child(health)
	status = StatusManager.new()
	add_child(status)
	_build_visuals()
	health.damaged.connect(_on_damaged)
	health.healed.connect(func(amount: int) -> void: EventBus.player_healed.emit(self, amount))
	health.visual_state_changed.connect(_on_visual_state_changed)
	health.died.connect(_on_died)
	health.guardian_saved.connect(func() -> void:
		play_emote("👼")
		if not Net.client_mode():
			EventBus.log_public.emit("👼 L'Ange Gardien arrache %s à la mort !" % display_name))
	# Réactions "corporelles" aux événements de table.
	EventBus.turn_started.connect(_on_turn_started_body)
	EventBus.card_drawn.connect(_on_card_drawn_body)
	EventBus.card_resolved.connect(_on_card_resolved_body)
	EventBus.stalling_started.connect(func(lambin) -> void:
		if lambin == self:
			_turn_marker.text = "🪨 PIOCHE !!!"
			_turn_marker.modulate = Color(1.0, 0.35, 0.2))
	EventBus.chain_echo.connect(func(who) -> void:
		if who == self:
			_play_chain_echo())

func is_alive() -> bool:
	return health != null and health.is_alive()

# ---------------------------------------------------------------- Construction

func _build_visuals() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.9

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	_body = MeshInstance3D.new()
	_body.mesh = capsule
	_body.material_override = _mat
	_body.position = Vector3(0, 0.7, 0)
	add_child(_body)
	_body_base_pos = _body.position

	# Tête sur pivot : c'est elle qui "regarde" (mécanique de bluff).
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0, 1.55, 0)
	add_child(_head_pivot)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28
	head_mesh.height = 0.56
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = _mat
	_head_pivot.add_child(head)

	# Yeux côté -Z (face à la table) : la direction du regard se lit de loin.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.08, 0.08, 0.1)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.05
		eye_mesh.height = 0.1
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(0.1 * side, 0.05, -0.24)
		_head_pivot.add_child(eye)

	# Bras posés vers la table ; le droit tient les cartes.
	_shoulder_l = _build_arm(-1.0)
	_shoulder_r = _build_arm(1.0)
	_hand_r = _shoulder_r.get_node("Hand")
	_build_card_visual()
	_build_accessories()

	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.font = GameFonts.ui_font()
	_name_label.font_size = 48
	_name_label.pixel_size = 0.004
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.3, 0)  # au-dessus des chapeaux.
	_name_label.modulate = color.lightened(0.4)
	add_child(_name_label)

	_emote_label = Label3D.new()
	_emote_label.font = GameFonts.emoji_font()
	_emote_label.font_size = 110
	_emote_label.pixel_size = 0.004
	_emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_label.position = Vector3(0, 2.7, 0)
	add_child(_emote_label)

	# Le rappel de tour flotte au-dessus du joueur qui doit piocher : toute la
	# table voit qui fait attendre tout le monde. La honte est une mécanique.
	_turn_marker = Label3D.new()
	_turn_marker.text = "🎯 À TOI !"
	_turn_marker.font = GameFonts.ui_font()
	_turn_marker.font_size = 64
	_turn_marker.pixel_size = 0.005
	_turn_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_turn_marker.position = Vector3(0, 3.05, 0)
	_turn_marker.modulate = Color(1.0, 0.85, 0.3)
	_turn_marker.visible = false
	add_child(_turn_marker)

	# La fleur : portée en main gauche, ou arborée sur la tête une fois offerte.
	_carried_flower = _build_flower(_shoulder_l.get_node("Hand"), Vector3(0, -0.1, 0))
	_worn_flower = _build_flower(_head_pivot, Vector3(0.16, 0.14, -0.14))

	# Le sac à dos et sa poche transparente : les cartes gardées y sont
	# RANGÉES EN VRAC, visibles de quiconque regarde ton dos. L'espionnage
	# est physique : se placer derrière quelqu'un = voir son jeu.
	_build_bag()

	# 💬 Bulle de dialogue du chat texte.
	_chat_bubble = Label3D.new()
	_chat_bubble.font = GameFonts.ui_font()
	_chat_bubble.font_size = 36
	_chat_bubble.pixel_size = 0.0045
	_chat_bubble.width = 260.0
	_chat_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chat_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chat_bubble.outline_size = 14
	_chat_bubble.position = Vector3(0, 3.0, 0)
	add_child(_chat_bubble)

	# 🎤 au-dessus de la tête pendant qu'il parle (lire QUI parle = gameplay).
	_talk_icon = Label3D.new()
	_talk_icon.text = "🎤"
	_talk_icon.font = GameFonts.emoji_font()
	_talk_icon.font_size = 64
	_talk_icon.pixel_size = 0.004
	_talk_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_talk_icon.position = Vector3(0.45, 2.3, 0)
	_talk_icon.visible = false
	add_child(_talk_icon)

	# Corps de collision : permet de VISER ce joueur (lancer de grenade…).
	collision_body = StaticBody3D.new()
	collision_body.add_to_group("character_body")
	collision_body.set_meta("character", self)
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.9
	shape.shape = capsule_shape
	shape.position = Vector3(0, 0.95, 0)
	collision_body.add_child(shape)
	add_child(collision_body)

## Accessoires distinctifs : chapeau (4 modèles, déterminé par le nom),
## sourcils et pieds. Attachés au pivot de tête → ils suivent le regard.
## Chaque silhouette devient identifiable de loin, même sans vrai modèle 3D.
func _build_accessories() -> void:
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = color.darkened(0.45)
	hat_mat.roughness = 0.85
	match absi(display_name.hash()) % 4:
		0:  # Haut-de-forme.
			var brim := CylinderMesh.new()
			brim.top_radius = 0.32
			brim.bottom_radius = 0.32
			brim.height = 0.03
			_add_head_mesh(brim, Vector3(0, 0.22, 0), hat_mat)
			var crown := CylinderMesh.new()
			crown.top_radius = 0.19
			crown.bottom_radius = 0.19
			crown.height = 0.3
			_add_head_mesh(crown, Vector3(0, 0.38, 0), hat_mat)
		1:  # Casquette.
			var cap := SphereMesh.new()
			cap.radius = 0.29
			cap.height = 0.3
			_add_head_mesh(cap, Vector3(0, 0.15, 0), hat_mat)
			var visor := BoxMesh.new()
			visor.size = Vector3(0.24, 0.02, 0.18)
			_add_head_mesh(visor, Vector3(0, 0.16, -0.3), hat_mat)
		2:  # Chapeau pointu.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.01
			cone.bottom_radius = 0.24
			cone.height = 0.45
			_add_head_mesh(cone, Vector3(0, 0.4, 0), hat_mat)
		3:  # Béret, légèrement de travers.
			var beret := SphereMesh.new()
			beret.radius = 0.3
			beret.height = 0.18
			var mesh := _add_head_mesh(beret, Vector3(0.06, 0.23, 0), hat_mat)
			mesh.rotation_degrees = Vector3(0, 0, -12)

	# Sourcils : deux petites barres sombres au-dessus des yeux.
	var brow_mat := StandardMaterial3D.new()
	brow_mat.albedo_color = Color(0.08, 0.08, 0.1)
	for side in [-1.0, 1.0]:
		var brow := BoxMesh.new()
		brow.size = Vector3(0.1, 0.025, 0.02)
		var mesh := _add_head_mesh(brow, Vector3(0.1 * side, 0.13, -0.25), brow_mat)
		mesh.rotation_degrees = Vector3(0, 0, 8.0 * side)

	# Pieds : deux demi-sphères sombres, le personnage ne flotte plus.
	var feet_mat := StandardMaterial3D.new()
	feet_mat.albedo_color = color.darkened(0.6)
	for side in [-1.0, 1.0]:
		var foot := SphereMesh.new()
		foot.radius = 0.13
		foot.height = 0.16
		var mesh := MeshInstance3D.new()
		mesh.mesh = foot
		mesh.material_override = feet_mat
		mesh.position = Vector3(0.14 * side, 0.05, -0.08)
		add_child(mesh)

func _add_head_mesh(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	_head_pivot.add_child(instance)
	return instance

## Bras = pivot à l'épaule + segment qui pend, main au bout.
func _build_arm(side: float) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0.38 * side, 1.3, 0)
	shoulder.rotation_degrees = Vector3(ARM_REST, 0, 8.0 * side)
	add_child(shoulder)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.09
	arm_mesh.height = 0.6
	var arm := MeshInstance3D.new()
	arm.mesh = arm_mesh
	arm.material_override = _mat
	arm.position = Vector3(0, -0.3, 0)
	shoulder.add_child(arm)

	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0, -0.62, 0)
	shoulder.add_child(hand)

	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.11
	hand_mesh.height = 0.22
	var hand_visual := MeshInstance3D.new()
	hand_visual.mesh = hand_mesh
	hand_visual.material_override = _mat
	hand.add_child(hand_visual)
	return shoulder

## Carte 3D tenue devant soi : face blanche côté porteur, DOS ROUGE côté table.
## Ancrée au personnage (pas à la main) : orientation garantie, la main levée
## vient naturellement se placer dessous pour donner l'illusion de la tenir.
func _build_card_visual() -> void:
	_card_visual = Node3D.new()
	_card_visual.position = CARD_REST_POS
	_card_visual.rotation_degrees = Vector3(-12, 0, 0)
	_card_visual.visible = false
	add_child(_card_visual)

	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.93, 0.91, 0.86)
	face_mat.roughness = 0.6
	var card_mesh := BoxMesh.new()
	card_mesh.size = Vector3(0.26, 0.36, 0.012)
	var card := MeshInstance3D.new()
	card.mesh = card_mesh
	card.material_override = face_mat
	_card_visual.add_child(card)

	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.55, 0.12, 0.14)
	back_mat.roughness = 0.6
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(0.22, 0.32)
	var back := MeshInstance3D.new()
	back.mesh = back_mesh
	back.material_override = back_mat
	back.position = Vector3(0, 0, -0.008)
	back.rotation_degrees = Vector3(0, 180, 0)  # le dos regarde la table.
	_card_visual.add_child(back)

	# Le contenu est ÉCRIT sur la face : quiconque voit physiquement la face
	# (son porteur… ou un espion derrière lui) peut la lire.
	# Deux étiquettes calibrées pour tenir DANS la carte (0.26 × 0.36 m) :
	# l'emoji en grand au-dessus, le nom en petit en dessous.
	_card_emoji_label = Label3D.new()
	_card_emoji_label.font = GameFonts.emoji_font()
	_card_emoji_label.font_size = 52
	_card_emoji_label.pixel_size = 0.002
	_card_emoji_label.position = Vector3(0, 0.08, 0.012)
	_card_visual.add_child(_card_emoji_label)

	_card_label = Label3D.new()
	_card_label.font = GameFonts.ui_font()
	_card_label.font_size = 15
	_card_label.pixel_size = 0.0025
	_card_label.width = 96.0  # 96 px × 0.0025 = 0.24 m : la largeur utile de la carte.
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_label.modulate = Color(0.15, 0.15, 0.2)
	_card_label.outline_size = 0
	_card_label.position = Vector3(0, -0.05, 0.012)
	_card_visual.add_child(_card_label)

# ---------------------------------------------------------------- Échauffement

## Fin du compte à rebours : chacun reprend sa place, PV à 100 %, ardoise
## effacée — les cailloux de l'échauffement sont pardonnés.
func reset_for_match() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	auto_moving = false
	is_seated = true
	position = seat_position
	rotation = Vector3(0, seat_rotation, 0)
	status.clear_all()
	health.reset()
	_shake = 0.0
	_mat.albedo_color = _tinted_color()

# ---------------------------------------------------------------- Le comptoir

## Boire un verre au comptoir : +1 PV. Pas grand-chose, mais la taverne est
## une taverne. Le barman ressert toutes les 8 secondes, pas plus vite.
func drink() -> void:
	if not is_alive() or not EventBus.match_started:
		return
	if _drink_cooldown > 0.0:
		EventBus.log_private.emit(self, "🍺 Le barman essuie encore ton verre… (patiente un peu)")
		return
	_drink_cooldown = 8.0
	health.heal(1)
	EventBus.log_public.emit("🍺 %s s'accorde un verre au comptoir. (+1 PV)" % display_name)

# ---------------------------------------------------------------- Le sac à dos

## Sac en cuir + poche arrière TRANSPARENTE avec 3 emplacements de cartes
## posées de travers, comme fourrées à la va-vite.
func _build_bag() -> void:
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.35, 0.22, 0.13)
	leather.roughness = 1.0

	var bag := BoxMesh.new()
	bag.size = Vector3(0.46, 0.56, 0.16)
	var bag_visual := MeshInstance3D.new()
	bag_visual.mesh = bag
	bag_visual.material_override = leather
	bag_visual.position = Vector3(0, 1.05, 0.44)
	add_child(bag_visual)

	# Sangles sur les épaules.
	for side in [-1.0, 1.0]:
		var strap := BoxMesh.new()
		strap.size = Vector3(0.06, 0.4, 0.34)
		var strap_visual := MeshInstance3D.new()
		strap_visual.mesh = strap
		strap_visual.material_override = leather
		strap_visual.position = Vector3(0.18 * side, 1.32, 0.2)
		strap_visual.rotation_degrees = Vector3(38, 0, 0)
		add_child(strap_visual)

	# Poche transparente à l'arrière.
	var pocket := BoxMesh.new()
	pocket.size = Vector3(0.42, 0.5, 0.015)
	var pocket_visual := MeshInstance3D.new()
	pocket_visual.mesh = pocket
	var pocket_mat := StandardMaterial3D.new()
	pocket_mat.albedo_color = Color(0.75, 0.85, 0.95, 0.22)
	pocket_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pocket_visual.material_override = pocket_mat
	pocket_visual.position = Vector3(0, 1.05, 0.55)
	add_child(pocket_visual)

	# Trois emplacements de mini-cartes, volontairement de travers.
	var slots := [
		[Vector3(-0.11, 1.13, 0.53), -14.0],
		[Vector3(0.03, 1.0, 0.535), 9.0],
		[Vector3(0.12, 1.15, 0.53), -5.0],
	]
	for slot in slots:
		var mini := Node3D.new()
		mini.position = slot[0]
		mini.rotation_degrees = Vector3(0, 0, slot[1])
		mini.visible = false
		add_child(mini)
		var face := BoxMesh.new()
		face.size = Vector3(0.17, 0.23, 0.008)
		var face_visual := MeshInstance3D.new()
		face_visual.mesh = face
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_color = Color(0.93, 0.91, 0.86)
		face_visual.material_override = face_mat
		mini.add_child(face_visual)
		var emoji := Label3D.new()
		emoji.name = "Emoji"
		emoji.font = GameFonts.emoji_font()
		emoji.font_size = 30
		emoji.pixel_size = 0.0022
		emoji.position = Vector3(0, 0.04, 0.006)
		mini.add_child(emoji)
		var title := Label3D.new()
		title.name = "Titre"
		title.font = GameFonts.ui_font()
		title.font_size = 11
		title.pixel_size = 0.0018
		title.width = 90.0
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.modulate = Color(0.15, 0.15, 0.2)
		title.outline_size = 0
		title.position = Vector3(0, -0.055, 0.006)
		mini.add_child(title)
		_bag_cards.append(mini)

## Reflète la main dans la poche du sac (appelé quand la main change).
func _refresh_bag() -> void:
	for i in _bag_cards.size():
		var mini := _bag_cards[i]
		if i < hand.size():
			mini.visible = true
			(mini.get_node("Emoji") as Label3D).text = hand[i].get("emoji", "")
			(mini.get_node("Titre") as Label3D).text = hand[i].get("name", "")
		else:
			mini.visible = false

# ---------------------------------------------------------------- La fleur

## Cueille l'UNIQUE fleur de la partie (autorité seulement).
func pick_flower() -> void:
	if not is_alive() or not EventBus.match_started:
		return
	if EventBus.flower_taken:
		EventBus.log_private.emit(self, "🥀 Il n'y a plus de fleur à offrir cette partie…")
		return
	if has_flower:
		return
	EventBus.flower_taken = true
	has_flower = true
	show_carried_flower(true)
	EventBus.flower_picked.emit(self)
	EventBus.log_public.emit("🌹 %s cueille l'unique fleur de la taverne… Pour qui ?" % display_name)

## Offre la fleur à un joueur proche (+30 PV, +1 audace chacun)…
## ou à SOI-MÊME, avec un aplomb total.
func offer_flower(target) -> void:
	if not has_flower or target == null or not target.is_alive():
		return
	if target == self:
		has_flower = false
		show_carried_flower(false)
		wear_flower()
		health.heal(FLOWER_HEAL)
		points += 1
		EventBus.points_changed.emit(self, points)
		play_emote("💅")
		EventBus.flower_offered.emit(self, self)
		EventBus.log_public.emit("🌹💅 %s s'offre la fleur à LUI-MÊME ! +30 PV, et aucune honte."
			% display_name)
		return
	if global_position.distance_to(target.global_position) > FLOWER_OFFER_RANGE:
		EventBus.log_private.emit(self, "🌹 Approche-toi de lui pour offrir ta fleur !")
		return
	has_flower = false
	show_carried_flower(false)
	target.wear_flower()
	target.health.heal(FLOWER_HEAL)
	points += 1
	target.points += 1
	EventBus.points_changed.emit(self, points)
	EventBus.points_changed.emit(target, target.points)
	target.play_emote("❤️")
	EventBus.flower_offered.emit(self, target)
	EventBus.log_public.emit("🌹 %s offre sa fleur à %s ! Toute la table fond. (+30 PV, +1 audace chacun)"
		% [display_name, target.display_name])

func show_carried_flower(carried: bool) -> void:
	_carried_flower.visible = carried

func wear_flower() -> void:
	_worn_flower.visible = true

## Petite fleur : tige + corolle. `attach` = main (portée) ou tête (offerte).
func _build_flower(attach: Node3D, pos: Vector3) -> Node3D:
	var flower := Node3D.new()
	flower.position = pos
	flower.visible = false
	attach.add_child(flower)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.008
	stem.height = 0.16
	var stem_visual := MeshInstance3D.new()
	stem_visual.mesh = stem
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.2, 0.45, 0.2)
	stem_visual.material_override = stem_mat
	flower.add_child(stem_visual)
	var petals := SphereMesh.new()
	petals.radius = 0.045
	petals.height = 0.07
	var petals_visual := MeshInstance3D.new()
	petals_visual.mesh = petals
	var petals_mat := StandardMaterial3D.new()
	petals_mat.albedo_color = Color(0.9, 0.2, 0.3)
	petals_visual.material_override = petals_mat
	petals_visual.position = Vector3(0, 0.1, 0)
	flower.add_child(petals_visual)
	return flower

# ---------------------------------------------------------------- Regard

## Coupe le suivi de tête automatique (joueur local : c'est la souris qui pilote).
func set_gaze_enabled(enabled: bool) -> void:
	_gaze_enabled = enabled
	if not enabled:
		_head_pivot.rotation = Vector3.ZERO

## Dit un message écrit : bulle au-dessus de la tête + signal (journal, réseau).
func say(text: String) -> void:
	var clean := text.strip_edges().left(90)
	if clean.is_empty():
		return
	_chat_bubble.text = "💬 " + clean
	if _chat_tween and _chat_tween.is_valid():
		_chat_tween.kill()
	_chat_tween = create_tween()
	_chat_tween.tween_interval(3.0 + clean.length() * 0.05)
	_chat_tween.tween_callback(func() -> void: _chat_bubble.text = "")
	EventBus.chat_message.emit(self, clean)

## Le voice chat vient de jouer un paquet : montrer brièvement le micro.
func flash_talking() -> void:
	if _overhead_visible and is_alive():
		_talk_icon.visible = true
	_talk_hide_at = Time.get_ticks_msec() + 300

## Masque nom + émote + marqueur (joueur local : inutile devant sa caméra).
func set_overhead_visible(visible_overhead: bool) -> void:
	_overhead_visible = visible_overhead
	_name_label.visible = visible_overhead
	_emote_label.visible = visible_overhead
	if not visible_overhead:
		_turn_marker.visible = false
		_talk_icon.visible = false

## Première personne : la tête passe sur la couche de rendu 2, que la caméra
## du joueur local ignore. Les AUTRES joueurs continuent de voir sa tête.
func hide_head_from_camera(camera: Camera3D) -> void:
	for child in _head_pivot.get_children():
		if child is VisualInstance3D:
			child.layers = 2
	camera.cull_mask = 1

func look_at_point(world_point: Vector3) -> void:
	_gaze_point = world_point

func look_at_character(other: Node3D) -> void:
	_gaze_point = other.global_position + Vector3(0, 1.55, 0)

# ---------------------------------------------------------------- Se lever / s'asseoir

## Mémorise la place attribuée (appelé par main.gd après le placement).
func store_seat() -> void:
	seat_position = position
	seat_rotation = rotation.y

## Quitter sa chaise : action PUBLIQUE — tout le monde sait qu'un espion rôde.
func stand_up() -> void:
	if not is_seated or not is_alive():
		return
	is_seated = false
	position += global_basis.z * 0.4  # petit pas en arrière.
	EventBus.player_stood_up.emit(self)
	# En réseau client, le log arrive via l'hôte (sinon il apparaîtrait en double).
	if not Net.client_mode():
		EventBus.log_public.emit("👀 %s se lève de sa chaise…" % display_name)

func sit_down() -> void:
	if is_seated:
		return
	position = seat_position
	rotation = Vector3(0, seat_rotation, 0)
	is_seated = true
	auto_moving = false
	EventBus.player_sat_down.emit(self)
	if not Net.client_mode():
		EventBus.log_public.emit("🪑 %s se rassoit." % display_name)
	seated.emit()

## Retour automatique à sa place en contournant la table.
func return_to_seat() -> void:
	if is_seated or not is_alive():
		return
	auto_moving = true
	var a_from := atan2(position.x, position.z)
	var r_from := Vector2(position.x, position.z).length()
	var a_to := atan2(seat_position.x, seat_position.z)
	var r_to := Vector2(seat_position.x, seat_position.z).length()
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	var duration := absf(angle_difference(a_from, a_to)) * 1.1 + 0.5
	_move_tween.tween_method(_walk_arc.bind(a_from, a_to, r_from, r_to, null), 0.0, 1.0, duration)
	_move_tween.tween_callback(sit_down)

## Trajet complet d'espionnage : se lever, marcher jusque derrière la cible,
## observer quelques secondes, puis revenir s'asseoir. (Utilisé par les bots.)
func spy_walk(target) -> void:
	if not is_seated or not is_alive():
		return
	stand_up()
	auto_moving = true
	var a_from := atan2(position.x, position.z)
	var r_from := Vector2(position.x, position.z).length()
	var a_to: float = atan2(target.position.x, target.position.z)
	# Point d'observation : dans le dos de la cible, adapté à la taille de la table.
	var r_spy: float = Vector2(target.seat_position.x, target.seat_position.z).length() + 1.1
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	var duration := absf(angle_difference(a_from, a_to)) * 1.1 + 0.5
	_move_tween.tween_method(_walk_arc.bind(a_from, a_to, r_from, r_spy, target), 0.0, 1.0, duration)
	_move_tween.tween_interval(randf_range(2.0, 3.5))
	_move_tween.tween_method(_walk_arc.bind(a_to, a_from, r_spy, r_from, null), 0.0, 1.0, duration)
	_move_tween.tween_callback(sit_down)

## Course générique : se lever, marcher jusqu'à un point (en arc), exécuter
## une action sur place, puis revenir s'asseoir. (Fleur, comptoir, etc.)
func errand(a_to: float, r_to: float, on_arrive: Callable) -> void:
	if not is_seated or not is_alive():
		return
	stand_up()
	auto_moving = true
	var a_from := atan2(position.x, position.z)
	var r_from := Vector2(position.x, position.z).length()
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	var duration := absf(angle_difference(a_from, a_to)) * 1.1 + 0.5
	_move_tween.tween_method(_walk_arc.bind(a_from, a_to, r_from, r_to, null), 0.0, 1.0, duration)
	_move_tween.tween_callback(on_arrive)
	_move_tween.tween_interval(0.8)
	_move_tween.tween_method(_walk_arc.bind(a_to, a_from, r_to, r_from, null), 0.0, 1.0, duration)
	_move_tween.tween_callback(sit_down)

## Interpole une marche en arc autour de la table (jamais à travers !).
func _walk_arc(t: float, a_from: float, a_to: float, r_from: float, r_to: float, face_target) -> void:
	var angle := lerp_angle(a_from, a_to, t)
	var radius := lerpf(r_from, r_to, t)
	position = Vector3(sin(angle) * radius, 0, cos(angle) * radius)
	var focus: Vector3 = face_target.global_position if face_target != null else Vector3.ZERO
	look_at(Vector3(focus.x, 0, focus.z))

## Maintient le personnage entre la table et les murs (pas de physique : un cercle).
func clamp_to_arena() -> void:
	var flat := Vector2(position.x, position.z)
	var radius := flat.length()
	var clamped := clampf(radius, walk_radius_min, WALK_RADIUS_MAX)
	if clamped != radius and radius > 0.01:
		flat = flat / radius * clamped
		position = Vector3(flat.x, 0, flat.y)

# ---------------------------------------------------------------- Claques

## Gifle un joueur DEBOUT à portée. Les assis sont intouchables (sanctuaire).
func try_slap(target) -> bool:
	if not EventBus.match_started and not EventBus.warmup:
		return false
	if not is_alive() or target == self or target == null or not target.is_alive():
		return false
	if _slap_cooldown > 0.0 or target.is_seated:
		return false
	if global_position.distance_to(target.global_position) > SLAP_RANGE:
		return false
	_slap_cooldown = 2.0
	# Grand geste du bras, bien visible.
	var swing := create_tween()
	swing.tween_property(_shoulder_r, "rotation_degrees:z", 70.0, 0.12)
	swing.tween_property(_shoulder_r, "rotation_degrees:z", 8.0, 0.25)
	EventBus.log_public.emit("👋 CLAC ! %s gifle %s !" % [display_name, target.display_name])
	target.receive_slap(self)
	return true

## Caillasse un joueur. Cibles valides :
## - TOUT joueur DEBOUT, à tout moment (dégâts doublés : être debout, ça expose) ;
## - le lambin assis qui refuse de piocher, pendant la lapidation uniquement.
func throw_rock(target) -> bool:
	if not EventBus.match_started and not EventBus.warmup:
		return false
	if not is_alive() or target == self or target == null or not target.is_alive():
		return false
	if _rock_cooldown > 0.0:
		return false
	# Pendant l'échauffement, TOUT LE MONDE est une cible : défoulez-vous.
	if EventBus.match_started:
		if target.is_seated and target != EventBus.stalling_player:
			return false  # assis (et pas lambin) = intouchable aux cailloux.
		if target.has_flower and target != EventBus.stalling_player:
			return false  # on ne caillasse pas un porteur de fleur… sauf s'il bloque la partie.
	_rock_cooldown = 1.2
	var swing := create_tween()
	swing.tween_property(_shoulder_r, "rotation_degrees:x", ARM_RAISED, 0.15)
	swing.tween_property(_shoulder_r, "rotation_degrees:x", ARM_REST, 0.3)
	var damage := ROCK_DAMAGE if target.is_seated else ROCK_DAMAGE_STANDING
	var thrower_name := display_name
	Projectile.throw(get_tree().current_scene, rock_pile_position,
		target.global_position + Vector3(0, 1.3, 0),
		func() -> void:
			if is_instance_valid(target):
				target.health.take_damage(damage, "Caillou de %s" % thrower_name))
	return true

func receive_slap(from) -> void:
	health.take_damage(SLAP_DAMAGE, "Claque de %s" % from.display_name)
	play_emote("😱")
	# Projection comique, en restant dans l'arène.
	var away: Vector3 = (global_position - from.global_position).normalized()
	var end: Vector3 = position + away * 1.2
	var tween := create_tween()
	tween.tween_property(self, "position", end, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(clamp_to_arena)

# ---------------------------------------------------------------- Main de cartes

func can_store_card() -> bool:
	return hand.size() < HAND_SIZE

## Range la carte dans le sac : les autres savent qu'on garde quelque chose…
## et peuvent même la VOIR, s'ils s'approchent de la poche arrière du sac.
func store_card(card: Dictionary) -> void:
	hand.append(card)
	_refresh_bag()
	EventBus.card_stored.emit(self, card)
	EventBus.log_public.emit("🎒 %s range une carte dans son sac…" % display_name)

## Utilise une carte de la main. `target` = soi-même, ou un autre joueur si lançable.
func use_card(index: int, target) -> void:
	if not is_alive() or index < 0 or index >= hand.size():
		return
	var card: Dictionary = hand[index]
	var targetable: bool = card.get("targetable", false)
	if targetable and (target == null or target == self):
		return
	hand.remove_at(index)
	_refresh_bag()
	EventBus.card_used.emit(self, card, target)
	if targetable:
		# Petit geste du bras + projectile en cloche, effet à l'impact.
		_raise_card()
		get_tree().create_timer(0.25).timeout.connect(_lower_card)
		Projectile.throw(get_tree().current_scene,
			global_position + Vector3(0, 1.5, 0),
			target.global_position + Vector3(0, 1.2, 0),
			func() -> void:
				if is_instance_valid(target):
					EffectExecutor.apply(target, card, self))
	else:
		EffectExecutor.apply(self, card, self)

# ---------------------------------------------------------------- Réactions

func _on_turn_started_body(who) -> void:
	# Marqueur « À TOI ! » au-dessus du joueur courant, visible par les autres.
	_turn_marker.text = "🎯 À TOI !"
	_turn_marker.modulate = Color(1.0, 0.85, 0.3)
	_turn_marker.visible = who == self and _overhead_visible and is_alive()
	if not is_alive() or not _gaze_enabled:
		return
	if who == self:
		look_at_point(Vector3(0, 1.1, 0))  # fixe la pioche.
	else:
		look_at_character(who)             # tout le monde scrute le piocheur.

func _on_card_drawn_body(who, _card: Dictionary) -> void:
	if who == self:
		_turn_marker.visible = false
	if who == self and is_alive():
		_can_reveal = true  # fenêtre de réaction = fenêtre de révélation.
		_raise_card()

func _on_card_resolved_body(who, _card: Dictionary) -> void:
	if who == self:
		_can_reveal = false
		_lower_card()

## Révèle volontairement sa carte à toute la table : +1 point d'audace, +3 PV.
## Ne s'exécute que là où la logique fait autorité (hôte / solo).
func reveal_card() -> void:
	if not _can_reveal or not is_alive():
		return
	_can_reveal = false
	points += 1
	health.heal(REVEAL_HEAL)
	EventBus.points_changed.emit(self, points)
	EventBus.card_revealed.emit(self, current_card)
	EventBus.log_public.emit("📣 %s révèle sa carte : %s %s ! (+1 point d'audace)"
		% [display_name, current_card.get("emoji", ""), current_card.get("name", "?")])

## Monte la carte devant le visage : les autres voient qu'on lit… sauf si un
## espion debout regarde par-dessus l'épaule (le texte est écrit sur la face).
func _raise_card() -> void:
	_holding_card = true
	_card_emoji_label.text = current_card.get("emoji", "")
	_card_label.text = current_card.get("name", "")
	_card_visual.visible = true
	_card_visual.position = CARD_REST_POS
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	_arm_tween = create_tween().set_parallel(true)
	_arm_tween.tween_property(_shoulder_r, "rotation_degrees:x", ARM_RAISED, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_property(_card_visual, "position", CARD_RAISED_POS, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _lower_card() -> void:
	_holding_card = false
	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	_arm_tween = create_tween().set_parallel(true)
	_arm_tween.tween_property(_shoulder_r, "rotation_degrees:x", ARM_REST, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.tween_property(_card_visual, "position", CARD_REST_POS, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_arm_tween.chain().tween_callback(func() -> void: _card_visual.visible = false)

## Mode Enchaînés : tressaillement quand le partenaire encaisse. VISIBLE de
## tous — les bons observateurs relient les frissons aux coups reçus…
func _play_chain_echo() -> void:
	if not is_alive():
		return
	var tween := create_tween()
	tween.tween_property(_body, "rotation_degrees:z", 5.0, 0.06)
	tween.tween_property(_body, "rotation_degrees:z", -5.0, 0.08)
	tween.tween_property(_body, "rotation_degrees:z", 3.0, 0.06)
	tween.tween_property(_body, "rotation_degrees:z", 0.0, 0.1)

## Joue une émote au-dessus de la tête (petit "pop" élastique, puis disparition).
func play_emote(emote: String) -> void:
	if not is_alive():
		return
	if _emote_tween and _emote_tween.is_valid():
		_emote_tween.kill()
	_emote_label.text = emote
	_emote_label.scale = Vector3.ONE * 0.4
	_emote_tween = create_tween()
	_emote_tween.tween_property(_emote_label, "scale", Vector3.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_interval(2.2)
	_emote_tween.tween_callback(func() -> void: _emote_label.text = "")
	EventBus.emote_played.emit(self, emote)

# ---------------------------------------------------------------- Animation

func _process(delta: float) -> void:
	if not is_alive():
		return
	_time += delta
	_slap_cooldown = maxf(_slap_cooldown - delta, 0.0)
	_rock_cooldown = maxf(_rock_cooldown - delta, 0.0)
	_drink_cooldown = maxf(_drink_cooldown - delta, 0.0)
	if _talk_icon.visible and Time.get_ticks_msec() > _talk_hide_at:
		_talk_icon.visible = false
	# Respiration : plus le personnage est abîmé, plus il halète.
	var breath_freq := 2.0 + (100 - health.visual_state) * 0.04
	_body.scale.y = 1.0 + sin(_time * breath_freq) * 0.015
	# Tremblements aux paliers bas — lisibles par les autres joueurs.
	if _shake > 0.0:
		_body.position = _body_base_pos + Vector3(
			randf_range(-_shake, _shake), 0.0, randf_range(-_shake, _shake))
	# Suivi de tête. Bot : regarde le point d'intérêt (piocheur, pioche…).
	# HUMAIN : sa tête suit son corps — donc sa souris — pour que les autres
	# voient où il regarde VRAIMENT. Exception : lire sa carte fait plonger la
	# tête dessus (tell authentique, visible de tous).
	if _gaze_enabled:
		if _holding_card or is_bot:
			var target := _card_visual.global_position if _holding_card else _gaze_point
			var dir_world := target - _head_pivot.global_position
			if dir_world.length_squared() > 0.001:
				var dir := (global_basis.inverse() * dir_world).normalized()
				var yaw := clampf(atan2(-dir.x, -dir.z), -1.3, 1.3)
				var pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), -0.7, 0.5)
				_head_pivot.rotation.y = lerp_angle(_head_pivot.rotation.y, yaw, delta * 6.0)
				_head_pivot.rotation.x = lerp_angle(_head_pivot.rotation.x, pitch, delta * 6.0)
		else:
			_head_pivot.rotation.y = lerp_angle(_head_pivot.rotation.y, 0.0, delta * 6.0)
			_head_pivot.rotation.x = lerp_angle(_head_pivot.rotation.x, 0.0, delta * 6.0)

# ---------------------------------------------------------------- Dégâts / mort

func _on_damaged(amount: int, source: String) -> void:
	EventBus.player_damaged.emit(self, amount, source)
	# Flash rouge bref : les dégâts se VOIENT, même sans barre de vie publique.
	_mat.albedo_color = Color(1.0, 0.25, 0.2)
	var tween := create_tween()
	tween.tween_property(_mat, "albedo_color", _tinted_color(), 0.35)

func _on_visual_state_changed(state: int) -> void:
	_mat.albedo_color = _tinted_color()
	_shake = STATE_SHAKE[state]
	EventBus.visual_state_changed.emit(self, state)

func _tinted_color() -> Color:
	return color.lerp(Color(0.22, 0.14, 0.12), STATE_DAMAGE_TINT[health.visual_state])

func _on_died(cause: String) -> void:
	_mat.albedo_color = _tinted_color().darkened(0.5)
	_body.position = _body_base_pos
	_card_visual.visible = false
	_holding_card = false
	_turn_marker.visible = false
	# Mort en plein espionnage : le corps reste où il est tombé.
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	auto_moving = false
	# Chute en arrière avec rebond : la défaite doit faire rire, pas frustrer.
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:x", -90.0, 0.9) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	EventBus.player_died.emit(self, cause)
