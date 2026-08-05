extends Node
## Voice — voice chat de PROXIMITÉ (autoload).
##
## « Le micro fait partie du gameplay » (document de conception) :
##  - Push-to-talk : maintenir V pour parler (pas de micro ouvert qui ronfle) ;
##  - la voix sort de la BOUCHE du personnage (AudioStreamPlayer3D) → portée
##    courte naturelle : on chuchote à l'oreille en s'approchant, on devient
##    inaudible à l'autre bout de la taverne ;
##  - 100 % OPTIONNEL : sans micro (ou micro désactivé dans le menu pause),
##    on joue normalement et on ENTEND toujours les autres.
##
## Transport : PCM 16 bits mono sous-échantillonné à 16 kHz (~32 Ko/s en
## parlant), RPC non fiables via l'hôte. Parfait en LAN ; Steam Voice prendra
## le relais (compression Opus) lors de l'intégration Steamworks.

const NET_SAMPLE_RATE := 16000.0
const FRAME_SECONDS := 0.06  # paquets de ~60 ms.

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _send_buffer := PackedFloat32Array()
var _talking := false
var _speakers := {}  # siège -> {"player": AudioStreamPlayer3D, "playback": ...}

func _ready() -> void:
	# Touche V (physique) : parler. Déclarée ici pour exister dès le menu.
	if not InputMap.has_action("voice_talk"):
		InputMap.add_action("voice_talk")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_V
		InputMap.action_add_event("voice_talk", event)
	_setup_microphone()

## Bus de capture muet : le micro n'est JAMAIS rejoué localement (anti-larsen).
func _setup_microphone() -> void:
	var bus_index := AudioServer.get_bus_count()
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, "MicCapture")
	AudioServer.set_bus_mute(bus_index, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_index, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "MicCapture"
	add_child(_mic_player)
	set_microphone_enabled(GameConfig.voice_enabled)

## Active/désactive la capture micro (menu pause). Sans micro branché,
## la capture produit du silence : aucun risque, aucune erreur.
func set_microphone_enabled(enabled: bool) -> void:
	GameConfig.voice_enabled = enabled
	if enabled and not _mic_player.playing:
		_mic_player.play()
	elif not enabled and _mic_player.playing:
		_mic_player.stop()

func _process(_delta: float) -> void:
	if _capture == null:
		return
	var want_talk: bool = GameConfig.voice_enabled and Net.active \
		and Input.is_action_pressed("voice_talk") and not EventBus.pause_open
	if want_talk and not _talking:
		_talking = true
		_capture.clear_buffer()
		_send_buffer = PackedFloat32Array()
	elif not want_talk and _talking:
		_talking = false
		_ship_packet()  # dernier morceau de phrase.
	if not _talking:
		return
	# Décime le flux micro (44,1 kHz stéréo) vers 16 kHz mono.
	var available := _capture.get_frames_available()
	if available > 0:
		var frames := _capture.get_buffer(available)
		var ratio := maxi(int(round(AudioServer.get_mix_rate() / NET_SAMPLE_RATE)), 1)
		for i in range(0, frames.size(), ratio):
			_send_buffer.append((frames[i].x + frames[i].y) * 0.5)
	if _send_buffer.size() >= int(NET_SAMPLE_RATE * FRAME_SECONDS):
		_ship_packet()

func _ship_packet() -> void:
	if _send_buffer.is_empty() or not Net.active:
		_send_buffer = PackedFloat32Array()
		return
	var bytes := PackedByteArray()
	bytes.resize(_send_buffer.size() * 2)
	for i in _send_buffer.size():
		bytes.encode_s16(i * 2, int(clampf(_send_buffer[i], -1.0, 1.0) * 32000.0))
	_send_buffer = PackedFloat32Array()
	if Net.is_server:
		Net.relay_voice(Net.my_seat, bytes)
	else:
		Net.send_voice(bytes)

## Un paquet de voix arrive : on le joue à la position du personnage parleur.
func receive(seat: int, data: PackedByteArray) -> void:
	if seat == Net.my_seat or GameConfig.voice_volume <= 0.0:
		return
	if seat < 0 or seat >= Net.characters.size():
		return
	var character = Net.characters[seat]
	if character == null or not is_instance_valid(character):
		return
	var speaker := _get_speaker(seat, character)
	if speaker.is_empty():
		return
	var player: AudioStreamPlayer3D = speaker["player"]
	player.volume_db = linear_to_db(maxf(GameConfig.voice_volume, 0.0001))
	var playback: AudioStreamGeneratorPlayback = speaker["playback"]
	for i in range(0, data.size() - 1, 2):
		if playback.get_frames_available() <= 0:
			break
		var sample := data.decode_s16(i) / 32768.0
		playback.push_frame(Vector2(sample, sample))
	if character.has_method("flash_talking"):
		character.flash_talking()

## Haut-parleur 3D par personnage, créé à la demande (dans sa tête).
func _get_speaker(seat: int, character: Node3D) -> Dictionary:
	if _speakers.has(seat):
		var existing: Dictionary = _speakers[seat]
		if is_instance_valid(existing["player"]):
			return existing
	var player := AudioStreamPlayer3D.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = NET_SAMPLE_RATE
	generator.buffer_length = 0.3
	player.stream = generator
	player.max_distance = 12.0
	player.position = Vector3(0, 1.55, 0)
	character.add_child(player)
	player.play()
	var speaker := {"player": player, "playback": player.get_stream_playback()}
	_speakers[seat] = speaker
	return speaker
