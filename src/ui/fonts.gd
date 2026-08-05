class_name GameFonts
extends RefCounted
## GameFonts — polices EMBARQUÉES (res://assets/fonts/, licence OFL).
##
## Parité entre OS garantie : chaque joueur voit exactement les mêmes glyphes
## et les mêmes émojis (mécanique de jeu !), que le système ait ou non des
## polices installées. Repli sur les polices système uniquement si les
## fichiers embarqués manquent (sécurité).

const UI_FONT_PATH := "res://assets/fonts/NotoSans.ttf"
const EMOJI_FONT_PATH := "res://assets/fonts/NotoColorEmoji.ttf"

static var _ui_font: Font
static var _emoji_font: Font

static func emoji_font() -> Font:
	if _emoji_font == null:
		if ResourceLoader.exists(EMOJI_FONT_PATH):
			_emoji_font = load(EMOJI_FONT_PATH)
		else:
			var system := SystemFont.new()
			system.font_names = PackedStringArray([
				"Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji",
			])
			_emoji_font = system
	return _emoji_font

static func ui_font() -> Font:
	if _ui_font == null:
		var base: Font
		if ResourceLoader.exists(UI_FONT_PATH):
			base = load(UI_FONT_PATH)
		else:
			var system := SystemFont.new()
			system.font_names = PackedStringArray([
				"Segoe UI", "Open Sans", "Cantarell", "Arial",
			])
			base = system
		var fallbacks: Array[Font] = [emoji_font()]
		base.fallbacks = fallbacks
		_ui_font = base
	return _ui_font
