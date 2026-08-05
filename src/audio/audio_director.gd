extends Node
## AudioDirector — le son comme mécanique de jeu (autoload).
##
## Tous les sons sont SYNTHÉTISÉS au démarrage (ondes + bruit, AudioStreamWAV) :
## zéro asset externe, cohérent avec le prototype. Ils seront remplacés un à un
## par de vrais enregistrements sans toucher au câblage.
##
## Règles de design sonore :
##  - les sons sont SPATIALISÉS : la goupille s'entend depuis le bon joueur ;
##  - le FAUX bruit de goupille (cartes neutres) est LE MÊME que le vrai,
##    joué depuis un point aléatoire de la table — indiscernable, c'est le but ;
##  - le battement de cœur n'existe que pour TOI, quand tu es mal en point.

const SAMPLE_RATE := 22050
## Distance max pour entendre battre le cœur d'un AUTRE joueur (espionnage).
const HEART_EAVESDROP_RANGE := 3.0

var _sounds := {}
var _heart_accumulator := 0.0
var _heart_accumulators := {}  # par personnage (id d'instance) → temps cumulé.

func _ready() -> void:
	_build_sounds()
	EventBus.card_drawn.connect(func(c, _card: Dictionary) -> void: play_at("draw", _pos(c)))
	EventBus.card_stored.connect(func(c, _card: Dictionary) -> void: play_at("store", _pos(c)))
	EventBus.card_revealed.connect(func(c, _card: Dictionary) -> void: play_at("ding", _pos(c), -4.0))
	EventBus.card_used.connect(func(user, card: Dictionary, _t) -> void:
		if card.get("targetable", false):
			play_at("goupille", _pos(user)))
	EventBus.projectile_thrown.connect(func(from: Vector3, _to: Vector3) -> void:
		play_at("whoosh", from))
	EventBus.fake_event.connect(_on_fake_event)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_healed.connect(func(c, _amount: int) -> void: play_at("heal", _pos(c)))
	EventBus.player_died.connect(func(c, _cause: String) -> void: play_at("lose", _pos(c)))
	EventBus.emote_played.connect(func(c, _emote: String) -> void: play_at("pop", _pos(c), -10.0))
	EventBus.player_stood_up.connect(func(c) -> void: play_at("chair", _pos(c)))
	EventBus.player_sat_down.connect(func(c) -> void: play_at("chair", _pos(c), -8.0))
	EventBus.stalling_started.connect(func(_c) -> void: play("alarm"))
	EventBus.match_ended.connect(func(_winner) -> void: play("win"))
	EventBus.turn_started.connect(func(c) -> void:
		if c == _local_character():
			play("ding", -6.0))
	EventBus.status_applied.connect(func(c, status_name: String) -> void:
		if "Destin" in status_name:
			play_at("doom", _pos(c)))
	_ambient_loop()

## La taverne vit : bois qui craque, feu qui crépite — pendant les parties.
func _ambient_loop() -> void:
	while true:
		await get_tree().create_timer(randf_range(7.0, 15.0)).timeout
		if Net.characters.is_empty() or not is_instance_valid(Net.characters[0]):
			continue  # au menu : silence (la musique s'en charge).
		if randf() < 0.55:
			var angle := randf() * TAU
			play_at("creak", Vector3(sin(angle) * randf_range(4.0, 9.0),
				randf_range(0.5, 3.5), cos(angle) * randf_range(4.0, 9.0)), -14.0)
		else:
			play_at("crackle", Vector3(9.4, 0.6, 0.0), -10.0)  # depuis la cheminée.

# ---------------------------------------------------------------- Musique

var _music_player: AudioStreamPlayer

func play_menu_music() -> void:
	if not _sounds.has("menu_music"):
		_sounds["menu_music"] = _make_menu_music()
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.stream = _sounds["menu_music"]
		add_child(_music_player)
	if _music_player.playing:
		return
	_music_player.volume_db = -16.0
	_music_player.play()

func stop_music() -> void:
	if _music_player == null or not _music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -45.0, 1.2)
	tween.tween_callback(_music_player.stop)

func _process(delta: float) -> void:
	var me = _local_character()
	if me == null or not is_instance_valid(me):
		return
	_process_own_heart(me, delta)
	_process_nearby_hearts(me, delta)

## Ton propre cœur : dans tes oreilles, quand ça va mal.
func _process_own_heart(me, delta: float) -> void:
	if not me.is_alive() or me.health.visual_state > 25:
		_heart_accumulator = 0.0
		return
	_heart_accumulator += delta
	var interval := 0.6 if me.health.visual_state == 25 else 0.4  # panique à 10 %.
	if _heart_accumulator >= interval:
		_heart_accumulator = 0.0
		play("heart", -4.0)

## Le cœur des AUTRES : audible seulement en s'approchant tout près — un
## indice d'espionnage discret, jamais une pollution de la bande-son.
func _process_nearby_hearts(me, delta: float) -> void:
	for character in Net.characters:
		if character == me or character == null or not is_instance_valid(character) \
				or not character.is_alive() or character.health.visual_state > 25:
			continue
		var key: int = character.get_instance_id()
		var accumulated: float = _heart_accumulators.get(key, 0.0) + delta
		var interval := 0.6 if character.health.visual_state == 25 else 0.4
		if accumulated >= interval:
			accumulated = 0.0
			if me.global_position.distance_to(character.global_position) <= HEART_EAVESDROP_RANGE:
				play_at("heart", character.global_position + Vector3(0, 1.2, 0), -8.0, 4.0)
		_heart_accumulators[key] = accumulated

# ---------------------------------------------------------------- Lecture

## Son global, non spatialisé (UI, alarmes, ton propre cœur).
func play(sound_name: String, volume_db := 0.0) -> void:
	if not _sounds.has(sound_name):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _sounds[sound_name]
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## Son spatialisé : il vient de quelque part autour de la table.
## `max_distance` court = son intime, audible seulement de près.
func play_at(sound_name: String, position: Vector3, volume_db := 0.0, max_distance := 30.0) -> void:
	if not _sounds.has(sound_name):
		return
	var scene := get_tree().current_scene
	if scene == null:
		play(sound_name, volume_db)
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _sounds[sound_name]
	player.volume_db = volume_db
	player.max_distance = max_distance
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()

func _local_character():
	if Net.characters.is_empty() or Net.my_seat >= Net.characters.size():
		return null
	var c = Net.characters[Net.my_seat]
	return c if is_instance_valid(c) else null

func _pos(character) -> Vector3:
	if character != null and is_instance_valid(character):
		return character.global_position + Vector3(0, 1.3, 0)
	return Vector3(0, 1.3, 0)

func _on_fake_event(_message: String) -> void:
	# Le faux bruit vient d'un point ALÉATOIRE de la table : impossible à situer.
	var angle := randf() * TAU
	play_at("goupille", Vector3(sin(angle) * 2.0, 1.2, cos(angle) * 2.0))

func _on_player_damaged(c, amount: int, source: String) -> void:
	var sound := "slap" if source.begins_with("Claque") else "impact"
	play_at(sound, _pos(c), clampf(-14.0 + amount * 0.5, -14.0, 0.0))

# ---------------------------------------------------------------- Synthèse

func _build_sounds() -> void:
	_sounds["click"] = _wav(_tone(880, 0.05, 30.0))
	_sounds["ding"] = _wav(_tone(1320, 0.12, 12.0) + _tone(1760, 0.15, 10.0))
	_sounds["draw"] = _wav(_swish(0.18))
	_sounds["store"] = _wav(_tone(440, 0.06, 20.0) + _tone(660, 0.07, 18.0))
	_sounds["goupille"] = _wav(_square(2500, 0.025, 40.0) + _noise(0.03, 60.0, 0.4))
	_sounds["whoosh"] = _wav(_swish(0.35))
	_sounds["impact"] = _wav(_mix(_noise(0.16, 22.0, 0.9), _tone(90, 0.14, 14.0)))
	_sounds["slap"] = _wav(_mix(_noise(0.06, 45.0, 1.0), _square(1200, 0.02, 50.0)))
	_sounds["heal"] = _wav(_tone(523, 0.09, 10.0) + _tone(659, 0.09, 10.0) + _tone(784, 0.14, 8.0))
	_sounds["lose"] = _wav(_square(392, 0.18, 5.0) + _square(330, 0.18, 5.0) + _square(262, 0.32, 4.0))
	_sounds["win"] = _wav(_tone(523, 0.12, 6.0) + _tone(659, 0.12, 6.0)
		+ _tone(784, 0.12, 6.0) + _tone(1046, 0.35, 4.0))
	_sounds["alarm"] = _wav(_square(700, 0.14, 3.0) + _square(900, 0.14, 3.0)
		+ _square(700, 0.14, 3.0) + _square(900, 0.2, 4.0))
	_sounds["chair"] = _wav(_rumble(0.3))
	_sounds["pop"] = _wav(_tone(990, 0.05, 30.0))
	_sounds["heart"] = _wav(_tone(55, 0.1, 18.0))
	_sounds["doom"] = _wav(_tone(65, 0.9, 3.0))
	_sounds["miaou"] = _wav(_tone(700, 0.09, 9.0, 0.25) + _tone(520, 0.14, 8.0, 0.22))
	_sounds["creak"] = _wav(_square(95, 0.1, 8.0, 0.12) + _square(70, 0.16, 8.0, 0.1))
	_sounds["crackle"] = _wav(_noise(0.05, 40.0, 0.3) + _noise(0.04, 50.0, 0.25) + _noise(0.08, 30.0, 0.2))
	# La musique (8 s d'échantillons) est générée PARESSEUSEMENT au premier
	# passage au menu : elle ne doit jamais retarder le lancement du jeu.

## Boucle jazzy feutrée (Am7 · Dm7 · G7 · Cmaj7) : ambiance de bar, jamais agressive.
func _make_menu_music() -> AudioStreamWAV:
	var chords := [
		[110.0, 164.81, 196.0, 261.63],
		[146.83, 174.61, 220.0, 261.63],
		[98.0, 174.61, 246.94, 293.66],
		[130.81, 164.81, 196.0, 246.94],
	]
	var chord_duration := 2.0
	var samples := PackedFloat32Array()
	for chord in chords:
		var count := int(chord_duration * SAMPLE_RATE)
		var offset := samples.size()
		samples.resize(offset + count)
		for i in count:
			var t := float(i) / SAMPLE_RATE
			var envelope := sin(PI * t / chord_duration)
			var value := 0.0
			for freq in chord:
				value += sin(TAU * freq * t) * 0.09
			samples[offset + i] = value * envelope
	var stream := _wav(samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream

## Onde sinusoïdale avec décroissance exponentielle.
func _tone(freq: float, duration: float, decay: float, amp := 0.5) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(duration * SAMPLE_RATE)
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		samples[i] = sin(TAU * freq * t) * amp * exp(-decay * t)
	return samples

## Onde carrée (plus agressive, métallique).
func _square(freq: float, duration: float, decay: float, amp := 0.3) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(duration * SAMPLE_RATE)
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		samples[i] = (1.0 if fmod(freq * t, 1.0) < 0.5 else -1.0) * amp * exp(-decay * t)
	return samples

## Bruit blanc avec décroissance (impacts, claques).
func _noise(duration: float, decay: float, amp := 0.5) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(duration * SAMPLE_RATE)
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		samples[i] = randf_range(-1.0, 1.0) * amp * exp(-decay * t)
	return samples

## Souffle en cloche (pioche, projectile qui fend l'air).
func _swish(duration: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(duration * SAMPLE_RATE)
	samples.resize(count)
	var previous := 0.0
	for i in count:
		var envelope := sin(PI * float(i) / count)
		# Bruit légèrement lissé : plus "air" que "friture".
		previous = lerpf(previous, randf_range(-1.0, 1.0), 0.4)
		samples[i] = previous * 0.4 * envelope
	return samples

## Grondement sourd (raclement de chaise).
func _rumble(duration: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(duration * SAMPLE_RATE)
	samples.resize(count)
	var previous := 0.0
	for i in count:
		var envelope := sin(PI * float(i) / count)
		previous = lerpf(previous, randf_range(-1.0, 1.0), 0.08)
		samples[i] = previous * 0.8 * envelope
	return samples

## Superpose deux pistes (la plus longue donne la durée).
func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var result := a if a.size() >= b.size() else b
	var other := b if a.size() >= b.size() else a
	result = result.duplicate()
	for i in other.size():
		result[i] = clampf(result[i] + other[i], -1.0, 1.0)
	return result

## Convertit les échantillons flottants en AudioStreamWAV 16 bits.
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	stream.data = bytes
	return stream
