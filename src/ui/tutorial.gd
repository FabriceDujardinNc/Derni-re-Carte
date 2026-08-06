extends CanvasLayer
## Tutoriel d'avant-partie.
##
## Chaque joueur le lit à son rythme (ENTRÉE pour avancer, P pour tout passer)
## pendant que tout le monde peut déjà se balader dans la taverne — mais les
## easter eggs sont verrouillés (EventBus.match_started). La manche ne démarre
## que quand TOUS les humains ont terminé ; la liste de ceux qui lisent encore
## est affichée chez tout le monde. Des flèches 3D pointent les éléments clés.

var targets := {}  ## nom symbolique -> position monde (fourni par main.gd).

const PAGES := [
	{
		"title": "🎴 Bienvenue à la taverne !",
		"text": "Le but : être le DERNIER SURVIVANT (100 PV chacun).\nÀ ton tour, pioche une carte : ESPACE, ou clique sur la pioche qui brille.\nElle peut être bénéfique 💚, dangereuse 💥, piégée… ou n'être Absolument Rien 👻.",
		"targets": ["deck"],
	},
	{
		"title": "🎭 Le bluff, c'est le jeu",
		"text": "Toi seul vois ta carte : joue la comédie avec les émotes (touches 1 à 4) !\nPendant que tu la lis, la touche R la RÉVÈLE à tous : +1 point d'audace et +3 PV.\nL'audace départage les doubles KO — et fait ta légende.",
		"targets": [],
	},
	{
		"title": "🎒 Ton sac (et celui des autres)",
		"text": "Les cartes gardées (Médikit, Bouclier, Grenade lançable…) vont dans ton sac :\nmolette pour choisir, clic droit pour utiliser — ou LANCER sur un joueur visé.\nMéfiance : la poche arrière est transparente, ton jeu se lit dans ton dos !",
		"targets": [],
	},
	{
		"title": "👀 Debout, tout se paie",
		"text": "E : se lever · ZQSD : marcher. Va lire les cartes et les sacs par-derrière !\nMais debout, tu peux être GIFLÉ à portée de bras et CAILLASSÉ de loin.\nEt si tu tardes trop à piocher… LAPIDATION générale autorisée. 🪨",
		"targets": ["rocks"],
	},
	{
		"title": "🌹 La taverne vit",
		"text": "UNE seule fleur par partie : offre-la à quelqu'un (+30 PV)… ou garde-la pour toi.\nLe billard rapporte des points d'audace. Colle-toi à un blessé : son cœur bat.\nEt surtout : NE DÉRANGEZ. PAS. LE BARMAN.",
		"targets": ["flower", "billiard", "barman"],
	},
]

var _page := 0
var _done := false
var _reviewing := false  ## Relecture volontaire (P) après un passage automatique.
var _panel: PanelContainer
var _title: Label
var _text: Label
var _progress: Label
var _waiting: Label
var _arrows: Array[Node3D] = []
var _arrow_time := 0.0

func _ready() -> void:
	EventBus.tutorial_waiting.connect(_on_waiting)
	_build_ui()
	var args := OS.get_cmdline_user_args()
	if "autoplay" in args or "turbo" in args:
		_finish()  # test automatisé : prêt immédiatement, sans affichage.
	elif GameConfig.tutorial_done:
		# Déjà lu cette session : prêt immédiatement, mais on LE DIT clairement
		# (sinon on croit à un bug quand les autres lisent encore).
		_finish()
		_flash_notice("✅ Tutoriel déjà lu — tu es prêt !   (P : le relire)")
	else:
		_show_page(0)

func _flash_notice(text: String) -> void:
	_waiting.text = text
	_waiting.visible = true
	var tween := create_tween()
	tween.tween_interval(6.0)
	tween.tween_callback(func() -> void:
		# Ne masque que si la liste d'attente n'a pas pris le relais.
		if _waiting.text == text:
			_waiting.visible = false)

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.make_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.offset_top = -252
	_panel.offset_bottom = -48
	_panel.visible = false
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(_title)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)

	_progress = Label.new()
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_progress)

	# Qui fait attendre la table (visible chez tout le monde).
	_waiting = Label.new()
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_waiting.offset_top = 110
	_waiting.offset_bottom = 148
	_waiting.add_theme_font_size_override("font_size", 22)
	_waiting.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	_waiting.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_waiting.add_theme_constant_override("shadow_offset_y", 2)
	_waiting.visible = false
	root.add_child(_waiting)

func _show_page(index: int) -> void:
	_page = index
	_panel.visible = true
	var page: Dictionary = PAGES[index]
	_title.text = page["title"]
	_text.text = page["text"]
	_progress.text = "ENTRÉE : suivant · P : tout passer          %d / %d" % [index + 1, PAGES.size()]
	_spawn_arrows(page["targets"])

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		# Relecture à la demande : P rouvre les pages (sans bloquer personne,
		# on est déjà marqué « prêt »).
		if _reviewing:
			if event.is_action_pressed("ui_accept"):
				if _page + 1 < PAGES.size():
					_show_page(_page + 1)
				else:
					_close_review()
			elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_P:
				_close_review()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_P \
				and not EventBus.chat_open and not EventBus.pause_open:
			_reviewing = true
			_show_page(0)
		return
	if event.is_action_pressed("ui_accept"):
		if _page + 1 < PAGES.size():
			_show_page(_page + 1)
		else:
			_finish()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_P:
		_finish()

func _close_review() -> void:
	_reviewing = false
	_panel.visible = false
	_clear_arrows()

func _finish() -> void:
	if _done:
		return
	_done = true
	GameConfig.tutorial_done = true
	_panel.visible = false
	_clear_arrows()
	Net.tutorial_ready()
	if Net.active and not EventBus.match_started:
		_waiting.text = "⏳ En attente des autres joueurs…"
		_waiting.visible = true

func _on_waiting(names: Array) -> void:
	if names.is_empty():
		_waiting.visible = false
		return
	_waiting.visible = true
	if _done:
		_waiting.text = "⏳ Encore en train de lire le tutoriel : %s" % ", ".join(names)

# ---------------------------------------------------------------- Flèches 3D

## Des cônes dorés qui pointent (et rebondissent) au-dessus des éléments cités.
func _spawn_arrows(names: Array) -> void:
	_clear_arrows()
	for target_name in names:
		if not targets.has(target_name):
			continue
		var arrow := Node3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.14
		cone.bottom_radius = 0.005
		cone.height = 0.35
		var visual := MeshInstance3D.new()
		visual.mesh = cone
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.8, 0.2)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.7, 0.1)
		material.emission_energy_multiplier = 1.6
		visual.material_override = material
		arrow.add_child(visual)
		arrow.position = targets[target_name]
		arrow.set_meta("base_y", targets[target_name].y)
		add_child(arrow)
		_arrows.append(arrow)

func _clear_arrows() -> void:
	for arrow in _arrows:
		arrow.queue_free()
	_arrows.clear()

func _process(delta: float) -> void:
	_arrow_time += delta
	for arrow in _arrows:
		arrow.position.y = arrow.get_meta("base_y") + 0.35 + sin(_arrow_time * 4.0) * 0.15
		arrow.rotation.y += delta * 1.5
