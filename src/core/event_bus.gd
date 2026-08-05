extends Node
## EventBus — bus d'événements global (autoload).
##
## Colonne vertébrale de l'architecture modulaire : les modules (Cards, Characters,
## AI, UI, Audio, Networking...) communiquent UNIQUEMENT via ces signaux et ne se
## référencent jamais directement. Ajouter un module = se connecter au bus.
## C'est aussi le point d'accroche naturel pour la future couche réseau :
## il suffira de répliquer ces signaux via ENet/Steam.

# --- Déroulement de la partie ---
signal turn_started(character)                    ## Le tour d'un joueur commence.
signal draw_requested(character)                  ## Un joueur (humain ou bot) demande à piocher.
signal card_drawn(character, card: Dictionary)    ## Carte piochée (info PRIVÉE au piocheur).
signal card_resolved(character, card: Dictionary) ## L'effet de la carte a été appliqué.
signal card_stored(character, card: Dictionary)   ## Carte gardée en main (le contenu reste privé).
signal card_used(user, card: Dictionary, target)  ## Carte de la main utilisée (action VISIBLE).
signal card_revealed(character, card: Dictionary) ## Révélation VOLONTAIRE (récompensée en points).
signal points_changed(character, points: int)     ## Points d'audace (révélations, billard…).
signal flower_picked(character)                   ## L'UNIQUE fleur de la partie est cueillie.
signal flower_offered(giver, receiver)            ## …et offerte. Toute la table fond.

## La fleur n'existe qu'UNE fois par partie (remis à zéro par main.gd).
var flower_taken := false

# --- Tutoriel et échauffement d'avant-partie ---
signal tutorial_waiting(names: Array)  ## Qui lit encore le tutoriel (liste de noms).
signal countdown_tick(n: int)          ## Compte à rebours d'échauffement (10…1, puis 0 = GO).

## Faux tant que le tutoriel n'est pas terminé par TOUS : on peut se balader,
## mais les easter eggs (barman, fleur, billard, baston) sont verrouillés.
var match_started := false

## Vrai pendant le compte à rebours : cailloux et gifles GRATUITS (personne ne
## peut mourir), puis tout le monde reprend sa place avec 100 % de PV.
var warmup := false
signal hand_selected(character, index: int)       ## Sélection dans la main (UI locale).
signal match_ended(winner)                        ## Fin de partie (winner peut être null).

# --- État des joueurs ---
signal player_damaged(character, amount: int, source: String)
signal player_healed(character, amount: int)
signal player_died(character, cause: String)
signal status_applied(character, status_name: String)
signal visual_state_changed(character, state: int) ## Palier de dégradation : 100/75/50/25/10.

# --- Social / mise en scène ---
signal emote_played(character, emote: String)
signal fake_event(message: String)                ## Faux indice audible par tous (cartes neutres).
signal player_stood_up(character)                 ## Quitte sa chaise : espion potentiel, cible valide.
signal player_sat_down(character)                 ## De retour au sanctuaire : intouchable.
signal stalling_started(character)                ## Trop lent à piocher : caillassage autorisé !
signal stalling_ended(character)                  ## Il a pioché (ou est mort) : on repose les cailloux.
signal projectile_thrown(from: Vector3, to: Vector3) ## Visuel de lancer (répliqué en réseau).

## Joueur actuellement caillassable (géré par le TurnManager, null sinon).
## État partagé volontairement ici : tous les modules en ont besoin (IA, entrées, UI).
var stalling_player = null

# --- Journal (préfigure le futur module UI/notifications) ---
signal log_public(message: String)                ## Visible par tout le monde.
signal log_private(character, message: String)    ## Visible uniquement par le joueur concerné.

func _ready() -> void:
	# Écho console des événements publics : debug facile (headless ou exe _console).
	log_public.connect(func(message: String) -> void: print(message))
	card_drawn.connect(func(character, _card: Dictionary) -> void:
		print("🃏 %s pioche une carte…" % character.display_name))
	card_used.connect(func(user, card: Dictionary, target) -> void:
		print("💥 %s utilise %s%s" % [user.display_name, card.get("name", "?"),
			" → " + target.display_name if target != null and target != user else ""]))
