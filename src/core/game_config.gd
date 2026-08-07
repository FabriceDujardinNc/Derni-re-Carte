extends Node
## GameConfig — réglages choisis au menu principal, lus par la scène de jeu.
## Autoload : survit aux changements de scène (menu → partie → rejouer).

## Palette officielle des personnages (le menu propose ces couleurs).
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.35, 0.3), Color(0.3, 0.6, 0.9), Color(0.35, 0.8, 0.4),
	Color(0.95, 0.8, 0.3), Color(0.7, 0.45, 0.85), Color(0.95, 0.55, 0.25),
	Color(0.4, 0.8, 0.8), Color(0.9, 0.5, 0.7),
]

## Version affichée au menu ET vérifiée à la connexion réseau : deux versions
## différentes ne peuvent pas jouer ensemble (protocole incompatible).
const VERSION := "v0.11-alpha"

## Catalogue des chapeaux. Les 4 premiers sont gratuits ; les autres
## s'achètent avec l'audace GAGNÉE EN JOUANT (jamais d'argent réel).
const HATS := [
	{"name": "Haut-de-forme", "price": 0},
	{"name": "Casquette", "price": 0},
	{"name": "Chapeau pointu", "price": 0},
	{"name": "Béret", "price": 0},
	{"name": "Toque de chef", "price": 60},
	{"name": "Sombrero", "price": 60},
	{"name": "Casque viking", "price": 80},
	{"name": "Couronne", "price": 100},
	{"name": "Auréole", "price": 150},
]

const SAVE_PATH := "user://progression.cfg"
## Clé de chiffrement de la sauvegarde : décourage l'édition au Bloc-notes.
## (Un fichier local n'est JAMAIS inviolable — la vraie protection sera le
## Steam Cloud. La progression étant purement cosmétique, l'enjeu est faible.)
const SAVE_KEY := "derniere-carte:le-barman-veille-sur-les-sauvegardes"

var player_name := "Player"
var mode := "ffa"  ## "ffa" · "chains" (Enchaînés, paires secrètes) · "teams" (Rouge vs Bleu).
var difficulty := "moyen"  ## facile · moyen · difficile · nightmare · celeste.

## Mort subite : au-delà de cette durée de manche, la vie de tous s'écoule
## (1 PV/s) jusqu'au dénouement. Ajustable pour les tests (arg `sd=`).
var sudden_death_seconds := 600.0
var player_count := 8   ## 2 à 8 (design : 4-8, mais 2-3 utiles pour tester).
var color_index := 0    ## Couleur du joueur local dans PLAYER_COLORS.
var tutorial_done := false  ## Tutoriel déjà lu cette session : on ne le remontre pas.

# --- Options (menu pause) ---
var volume := 1.0             ## Volume principal (0 à 1).
var mouse_sensitivity := 1.0  ## Multiplicateur de sensibilité souris (0.4 à 2).
var fullscreen := false
var voice_enabled := true     ## Micro actif (parler avec V). Jouer sans micro = OK.
var voice_volume := 1.0       ## Volume des voix des AUTRES (0 = sourdine).

# --- Progression persistante (sauvegardée sur disque) ---
var audace_bank := 0                    ## Réserve d'audace gagnée en jouant.
var unlocked_hats: Array = [0, 1, 2, 3] ## Chapeaux possédés.
var selected_hat := 0                   ## Chapeau porté par le joueur local.
var language := "fr"                    ## "fr" ou "en" (drapeau du menu).

func _ready() -> void:
	load_progress()

func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load_encrypted_pass(SAVE_PATH, SAVE_KEY) != OK:
		return  # pas de sauvegarde (ou fichier trafiqué) : on repart de zéro.
	audace_bank = config.get_value("progression", "audace_bank", 0)
	unlocked_hats = config.get_value("progression", "unlocked_hats", [0, 1, 2, 3])
	selected_hat = config.get_value("progression", "selected_hat", 0)
	language = config.get_value("progression", "language", "fr")
	if not language in ["fr", "en"]:
		language = "fr"
	# Garde-fous contre les valeurs aberrantes.
	audace_bank = clampi(audace_bank, 0, 999999)
	if not selected_hat in unlocked_hats:
		selected_hat = 0

func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progression", "audace_bank", audace_bank)
	config.set_value("progression", "unlocked_hats", unlocked_hats)
	config.set_value("progression", "selected_hat", selected_hat)
	config.set_value("progression", "language", language)
	config.save_encrypted_pass(SAVE_PATH, SAVE_KEY)

## Encaisse les points d'audace d'une partie dans la réserve.
func bank_points(points: int) -> void:
	if points <= 0:
		return
	audace_bank += points
	save_progress()

## Achète un chapeau (dépense la réserve). Renvoie vrai si l'achat passe.
func buy_hat(hat_id: int) -> bool:
	if hat_id in unlocked_hats:
		return true
	var price: int = HATS[hat_id]["price"]
	if audace_bank < price:
		return false
	audace_bank -= price
	unlocked_hats.append(hat_id)
	save_progress()
	return true
