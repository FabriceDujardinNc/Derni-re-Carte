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
const VERSION := "v0.7-alpha"

var player_name := "Player"
var mode := "ffa"  ## "ffa" (chacun pour soi) ou "chains" (Les Enchaînés, paires secrètes).
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
