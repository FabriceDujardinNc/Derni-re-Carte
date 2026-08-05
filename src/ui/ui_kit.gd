class_name UiKit
extends RefCounted
## UiKit — petit kit d'interface partagé (menu, lobby, futurs écrans).
## Styles arrondis, boutons animés au survol, cartes flottantes d'ambiance.
## Tout est généré par code : aucune texture requise.

const ACCENT := Color(0.85, 0.65, 0.2)     # or — action principale
const ACCENT_BLUE := Color(0.35, 0.55, 0.9) # bleu — actions secondaires
const CARD_RED := Color(0.45, 0.1, 0.12)

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = GameFonts.ui_font()
	theme.default_font_size = 18
	return theme

## Fond sombre + léger dégradé vertical (vignette de taverne).
static func add_background(root: Control) -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var glow := ColorRect.new()
	glow.color = Color(0.16, 0.1, 0.05, 0.35)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -300
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)

## Panneau central : fond semi-transparent, coins arrondis, fine bordure dorée.
static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.13, 0.92)
	style.set_corner_radius_all(16)
	style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	style.set_border_width_all(1)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 24
	return style

## Habille un bouton : coins arrondis, teinte d'accent, pop au survol.
static func style_button(button: Button, accent: Color, font_size := 20) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.62)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(1)
	normal.border_color = accent.darkened(0.25)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = accent.darkened(0.42)
	var pressed := normal.duplicate()
	pressed.bg_color = accent.darkened(0.72)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(func() -> void: Audio.play("click", -8.0))
	hover_pop(button)

## Le contrôle gonfle légèrement quand la souris le survole.
static func hover_pop(control: Control) -> void:
	control.mouse_entered.connect(func() -> void:
		control.pivot_offset = control.size / 2.0
		var tween := control.create_tween()
		tween.tween_property(control, "scale", Vector2(1.05, 1.05), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	control.mouse_exited.connect(func() -> void:
		var tween := control.create_tween()
		tween.tween_property(control, "scale", Vector2.ONE, 0.12))

## Respiration douce (titre) : léger zoom cyclique.
static func breathe(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "scale", Vector2(1.025, 1.025), 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Entrée en scène : le contrôle surgit (fondu + zoom élastique).
static func pop_in(control: Control, delay := 0.0) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(0.9, 0.9)
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tween.tween_property(control, "modulate:a", 1.0, 0.3).set_delay(delay)

## Dos de cartes qui flottent lentement vers le haut, en arrière-plan.
static func spawn_floating_cards(layer: Control, count: int) -> void:
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in count:
		var card := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(CARD_RED.r, CARD_RED.g, CARD_RED.b, 0.5)
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.border_color = Color(0.85, 0.8, 0.72, 0.25)
		card.add_theme_stylebox_override("panel", style)
		var width := randf_range(46.0, 90.0)
		card.size = Vector2(width, width * 1.4)
		card.pivot_offset = card.size / 2.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(card)
		# Départ étalé sur tout l'écran pour éviter l'effet "vague de départ".
		var viewport := layer.get_viewport_rect().size
		card.position = Vector2(randf_range(0, viewport.x), randf_range(0, viewport.y))
		_float_card(card)

static func _float_card(card: Panel) -> void:
	var viewport := card.get_viewport_rect().size
	var duration := randf_range(10.0, 20.0)
	card.rotation = randf_range(-0.5, 0.5)
	card.modulate.a = randf_range(0.2, 0.55)
	var tween := card.create_tween()
	tween.tween_property(card, "position:y", -160.0, duration * (card.position.y + 160.0) / (viewport.y + 320.0))
	tween.parallel().tween_property(card, "rotation", card.rotation + randf_range(-1.2, 1.2), duration)
	tween.tween_callback(func() -> void:
		card.position = Vector2(randf_range(0, viewport.x), viewport.y + 160.0)
		_float_card(card))
