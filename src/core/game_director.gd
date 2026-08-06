extends Node
## Game Director — le metteur en scène invisible (hôte uniquement).
##
## Il surveille le rythme de la partie et intervient pour que deux parties ne
## se ressemblent JAMAIS :
##  - la table s'endort (pas de dégâts depuis un moment) → il secoue :
##    coupure de courant, pluie de poulets, table qui tremble ;
##  - la tension est déjà là → il en rajoute une pincée, parfois pour RIEN :
##    orage, faux bruits inquiétants (la paranoïa est gratuite).
## Les effets visuels/sonores sont exécutés par main.gd sur CHAQUE machine
## (relais réseau via EventBus.director_event).

const BOREDOM_MS := 15000  ## Sans dégâts depuis 15 s = la table s'ennuie.

var _last_damage_ms := 0

func _ready() -> void:
	_last_damage_ms = Time.get_ticks_msec()
	EventBus.player_damaged.connect(func(_c, _a: int, _s: String) -> void:
		_last_damage_ms = Time.get_ticks_msec())
	_direction_loop()

func _direction_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(22.0, 40.0)).timeout
		if not is_inside_tree() or not EventBus.match_started:
			continue
		var bored: bool = Time.get_ticks_msec() - _last_damage_ms > BOREDOM_MS
		if bored:
			# On réveille la taverne, avec de la mise en scène.
			_trigger(["chickens", "blackout", "shake", "storm"].pick_random())
		elif randf() < 0.45:
			# La tension est là : une pincée d'inquiétude suffit (ou du vent).
			_trigger(["storm", "fake", "fake"].pick_random())

func _trigger(event_name: String) -> void:
	match event_name:
		"blackout":
			EventBus.log_public.emit("⚡ Les lumières de la taverne s'éteignent d'un coup !")
		"storm":
			EventBus.log_public.emit("🌩️ Un orage éclate au-dessus de la taverne !")
		"chickens":
			EventBus.log_public.emit("🐔 Attendez… IL PLEUT DES POULETS ?!")
		"shake":
			EventBus.log_public.emit("💥 Toute la taverne se met à trembler !")
		"fake":
			# Aucun log : juste un bruit inquiétant venu de nulle part.
			EventBus.fake_event.emit("🔊 Un grondement sourd parcourt la taverne…")
			return
	EventBus.director_event.emit(event_name)
