class_name HealthComponent
extends Node
## HealthComponent — points de vie, bouclier et paliers de dégradation visuelle.
##
## Composant PUR : il ne connaît ni son propriétaire ni l'EventBus, il émet
## seulement des signaux locaux. C'est le personnage qui relaie vers le bus.
## Paliers visuels (game design) : 100 / 75 / 50 / 25 / 10 %.

signal hp_changed(hp: int, max_hp: int)
signal shield_changed(shield: int)
signal damaged(amount: int, source: String)
signal healed(amount: int)
signal visual_state_changed(state: int)
signal died(cause: String)

## Paliers de dégradation, du moins au plus abîmé (en % de PV).
const VISUAL_THRESHOLDS: Array[int] = [75, 50, 25, 10]

var max_hp := 100
var hp := 100
var shield := 0
var visual_state := 100

func is_alive() -> bool:
	return hp > 0

## Inflige des dégâts. Le bouclier absorbe en priorité.
func take_damage(amount: int, source := "???") -> void:
	if hp <= 0 or amount <= 0:
		return
	var remaining := amount
	if shield > 0:
		var absorbed := mini(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		shield_changed.emit(shield)
	hp = maxi(hp - remaining, 0)
	hp_changed.emit(hp, max_hp)
	damaged.emit(amount, source)
	_refresh_visual_state()
	if hp == 0:
		died.emit(source)

func heal(amount: int) -> void:
	if hp <= 0 or amount <= 0:
		return
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
	healed.emit(amount)
	_refresh_visual_state()

func add_shield(amount: int) -> void:
	if hp <= 0 or amount <= 0:
		return
	shield += amount
	shield_changed.emit(shield)

## Recalcule le palier visuel courant et notifie s'il a changé.
func _refresh_visual_state() -> void:
	var pct := 100.0 * hp / max_hp
	var new_state := 100
	for threshold in VISUAL_THRESHOLDS:
		if pct <= threshold:
			new_state = threshold
	if new_state != visual_state:
		visual_state = new_state
		visual_state_changed.emit(visual_state)
