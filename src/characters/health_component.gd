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
signal guardian_saved()  ## L'Ange Gardien vient d'annuler une mort.

## Paliers de dégradation, du moins au plus abîmé (en % de PV).
const VISUAL_THRESHOLDS: Array[int] = [75, 50, 25, 10]

var max_hp := 100
var hp := 100
var shield := 0
var visual_state := 100
var guardian := false        ## Ange Gardien : annule la PROCHAINE mort (hp = 1).
var _heal_block_until := 0   ## Malédiction : soins inopérants jusqu'à cet instant (ms).

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
	# Échauffement d'avant-partie : on encaisse, mais personne ne meurt.
	if EventBus.warmup and remaining >= hp:
		remaining = maxi(hp - 1, 0)
	hp = maxi(hp - remaining, 0)
	# L'Ange Gardien intercepte la mort — une seule fois.
	if hp == 0 and guardian:
		guardian = false
		hp = 1
		guardian_saved.emit()
	hp_changed.emit(hp, max_hp)
	damaged.emit(amount, source)
	_refresh_visual_state()
	if hp == 0:
		died.emit(source)

## Bloque tout soin pendant `seconds` (Malédiction).
func block_healing(seconds: float) -> void:
	_heal_block_until = Time.get_ticks_msec() + int(seconds * 1000.0)

func heal(amount: int) -> void:
	if hp <= 0 or amount <= 0:
		return
	if Time.get_ticks_msec() < _heal_block_until:
		return  # maudit : les soins ne prennent pas.
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
	healed.emit(amount)
	_refresh_visual_state()

## Fixe directement les PV (Échange Vital). Jamais en-dessous de 1.
func set_hp(value: int) -> void:
	hp = clampi(value, 1, max_hp)
	hp_changed.emit(hp, max_hp)
	_refresh_visual_state()

## Remise à neuf complète (fin de l'échauffement).
func reset() -> void:
	hp = max_hp
	shield = 0
	guardian = false
	_heal_block_until = 0
	hp_changed.emit(hp, max_hp)
	shield_changed.emit(shield)
	if visual_state != 100:
		visual_state = 100
		visual_state_changed.emit(visual_state)

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
