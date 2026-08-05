extends Node
## GameConfig — réglages choisis au menu principal, lus par la scène de jeu.
## Autoload : survit aux changements de scène (menu → partie → rejouer).

## Palette officielle des personnages (le menu propose ces couleurs).
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.35, 0.3), Color(0.3, 0.6, 0.9), Color(0.35, 0.8, 0.4),
	Color(0.95, 0.8, 0.3), Color(0.7, 0.45, 0.85), Color(0.95, 0.55, 0.25),
	Color(0.4, 0.8, 0.8), Color(0.9, 0.5, 0.7),
]

var player_name := "Player"
var player_count := 8   ## 2 à 8 (design : 4-8, mais 2-3 utiles pour tester).
var color_index := 0    ## Couleur du joueur local dans PLAYER_COLORS.
var tutorial_done := false  ## Tutoriel déjà lu cette session : on ne le remontre pas.
