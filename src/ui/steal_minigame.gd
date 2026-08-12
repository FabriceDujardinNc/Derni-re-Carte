extends CanvasLayer
## Mini-jeu de VOL À LA TIRE (crochetage du sac).
##
## Trois verrous : un curseur oscille, appuie sur ESPACE dans la zone verte.
## De plus en plus rapide et étroit. Réussite = choisir UNE carte du sac.
## Pendant ce temps, la victime voit un GROS WARNING et peut réagir :
##  - elle s'éloigne → le sac sort de portée, tentative annulée ;
##  - le voleur prend un coup → interrompu ;
##  - elle SE RETOURNE et fait face au voleur → FLAGRANT DÉLIT : le vol
##    s'arrête net et le voleur prend des dégâts. Voler est un métier.

const PIN_COUNT := 3
const PIN_SPEEDS := [2.4, 3.1, 3.9]
const ZONE_WIDTHS := [0.24, 0.18, 0.13]  # fraction de la barre.
const FAIL_COOLDOWN := 10.0
const CAUGHT_DAMAGE := 8
const RANGE_LIMIT := 2.8

var _thief = null
var _victim = null
var _active := false
var _phase := "picking"  # picking | choosing
var _pin := 0
var _cursor_time := 0.0
var _zone_start := 0.4
var _cooldown_until := 0

var _root: Control
var _panel: PanelContainer
var _title: Label
var _progress: Label
var _track: ColorRect
var _zone: ColorRect
var _cursor: ColorRect
var _cards_row: HBoxContainer

func _ready() -> void:
	layer = 12
	add_to_group("steal_minigame")
	_build_ui()

# ---------------------------------------------------------------- Cycle

## Lance une tentative (déjà validée par l'appelant : proximité, cartes…).
func begin(thief, victim) -> void:
	if _active:
		return
	if Time.get_ticks_msec() < _cooldown_until:
		EventBus.log_private.emit(thief, Lang.t("🫳 Le sac s'est refermé il y a peu… patiente un peu."))
		return
	_thief = thief
	_victim = victim
	_active = true
	_phase = "picking"
	_pin = 0
	_cursor_time = 0.0
	EventBus.steal_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = Lang.t("🫳 Fouille du sac de %s…") % victim.display_name
	_cards_row.visible = false
	_track.visible = true
	_randomize_zone()
	_update_progress()
	_root.visible = true
	# Prévenir la victime (via l'hôte en réseau).
	if Net.client_mode():
		Net.send_steal_start(Net.seat_of(victim))
	else:
		EventBus.steal_started.emit(thief, victim)
	# Interruption si le voleur encaisse.
	if not _thief.health.damaged.is_connected(_on_thief_damaged):
		_thief.health.damaged.connect(_on_thief_damaged)

func _end(reason: String) -> void:
	if not _active:
		return
	_active = false
	_root.visible = false
	EventBus.steal_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _thief != null and _thief.health.damaged.is_connected(_on_thief_damaged):
		_thief.health.damaged.disconnect(_on_thief_damaged)
	if Net.client_mode():
		Net.send_steal_end(Net.seat_of(_victim))
	else:
		EventBus.steal_ended.emit(_victim)
	if not reason.is_empty():
		EventBus.log_private.emit(_thief, reason)

func _on_thief_damaged(_amount: int, _source: String) -> void:
	_cooldown_until = Time.get_ticks_msec() + int(FAIL_COOLDOWN * 1000)
	_end(Lang.t("🫳 Interrompu en plein travail ! Le sac s'est refermé."))

# ---------------------------------------------------------------- Surveillance

func _process(delta: float) -> void:
	if not _active:
		return
	# La cible s'éloigne ?
	if not is_instance_valid(_victim) or not _victim.is_alive() \
			or _thief.global_position.distance_to(_victim.global_position) > RANGE_LIMIT:
		_end(Lang.t("🫳 La cible s'est éloignée. Tentative annulée."))
		return
	# FLAGRANT DÉLIT : la victime s'est retournée et te fait face.
	var to_thief: Vector3 = (_thief.global_position - _victim.global_position).normalized()
	if (-_victim.global_basis.z).dot(to_thief) > 0.35:
		_cooldown_until = Time.get_ticks_msec() + int(FAIL_COOLDOWN * 1000)
		if Net.client_mode():
			Net.send_steal_caught()
		else:
			_thief.health.take_damage(CAUGHT_DAMAGE, Lang.t("Pris la main dans le sac"))
			EventBus.log_public.emit(Lang.t("😤 %s a surpris %s la main dans son sac !")
				% [_victim.display_name, _thief.display_name])
		_end(Lang.t("😤 FLAGRANT DÉLIT ! Tu t'es fait surprendre."))
		return
	# Curseur du crochetage.
	if _phase == "picking":
		_cursor_time += delta * float(PIN_SPEEDS[_pin])
		var t := sin(_cursor_time) * 0.5 + 0.5
		_cursor.position.x = t * (_track.size.x - _cursor.size.x)

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		_end(Lang.t("🫳 Tu renonces discrètement."))
		get_viewport().set_input_as_handled()
		return
	if _phase == "picking" and event.is_action_pressed("draw_card"):
		get_viewport().set_input_as_handled()
		var t := _cursor.position.x / (_track.size.x - _cursor.size.x)
		var width := float(ZONE_WIDTHS[_pin])
		if t >= _zone_start and t <= _zone_start + width:
			_pin += 1
			Audio.play("goupille", -4.0)
			if _pin >= PIN_COUNT:
				_show_card_choice()
			else:
				_randomize_zone()
				_update_progress()
		else:
			_cooldown_until = Time.get_ticks_msec() + int(FAIL_COOLDOWN * 1000)
			Audio.play("impact", -8.0)
			_end(Lang.t("🫳 Raté ! Le sac s'est refermé d'un coup sec."))

# ---------------------------------------------------------------- Phases

func _randomize_zone() -> void:
	var width := float(ZONE_WIDTHS[_pin])
	_zone_start = randf_range(0.08, 0.92 - width)
	_zone.position.x = _zone_start * _track.size.x
	_zone.size.x = width * _track.size.x

func _update_progress() -> void:
	_progress.text = Lang.t("Verrou %d / %d — ESPACE dans la zone verte · Échap : renoncer") % [_pin + 1, PIN_COUNT]

## Les trois verrous ont cédé : choisir UNE carte du butin.
func _show_card_choice() -> void:
	_phase = "choosing"
	_track.visible = false
	_title.text = Lang.t("🫳 Le sac de %s est ouvert. Choisis TA carte :") % _victim.display_name
	_progress.text = Lang.t("Vite, avant qu'il ne se retourne…")
	for child in _cards_row.get_children():
		child.queue_free()
	for i in _victim.hand.size():
		var card: Dictionary = _victim.hand[i]
		var button := Button.new()
		button.text = "%s %s" % [card.get("emoji", ""), card.get("name", "?")]
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(button, UiKit.ACCENT, 16)
		button.pressed.connect(_on_card_chosen.bind(i))
		_cards_row.add_child(button)
	_cards_row.visible = true

func _on_card_chosen(index: int) -> void:
	if Net.client_mode():
		Net.send_steal_finish(Net.seat_of(_victim), index)
	else:
		_thief.steal_card_from(_victim, index)
	_end("")

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.make_theme()
	_root.visible = false
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	# Demi-largeur bornée : 300 px sur un écran normal, resserrée sur un
	# téléphone plutôt que de sortir de l'écran.
	var half: float = clampf(_root.get_viewport_rect().size.x * 0.5 - 16.0, 150.0, 300.0)
	_panel.offset_left = -half
	_panel.offset_right = half
	_panel.offset_top = -250
	_panel.offset_bottom = -80
	_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(_title)

	# La barre de crochetage : piste sombre, zone verte, curseur clair.
	_track = ColorRect.new()
	_track.color = Color(0.08, 0.07, 0.1)
	# La piste suit la largeur du panneau (toute la logique est relative à
	# _track.size.x, donc une piste plus courte reste jouable).
	_track.custom_minimum_size = Vector2(maxf(half * 2.0 - 60.0, 180.0), 26)
	box.add_child(_track)
	_zone = ColorRect.new()
	_zone.color = Color(0.3, 0.8, 0.4, 0.85)
	_zone.size = Vector2(100, 26)
	_track.add_child(_zone)
	_cursor = ColorRect.new()
	_cursor.color = Color(1.0, 0.95, 0.8)
	_cursor.size = Vector2(7, 26)
	_track.add_child(_cursor)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 8)
	_cards_row.visible = false
	box.add_child(_cards_row)

	_progress = Label.new()
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_progress)
