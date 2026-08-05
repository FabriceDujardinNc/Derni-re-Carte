extends Node
## CardDatabase — base de cartes data-driven (autoload).
##
## Les cartes sont décrites dans un fichier JSON (res://data/cards/cards.json),
## jamais dans le code : ajouter une carte = ajouter une entrée JSON.
## C'est la fondation du modding (à terme : chargement de packs de cartes
## depuis user:// ou le Workshop Steam).
##
## La pioche est pondérée : chaque carte a un "weight". La Carte du Destin
## a un poids de 0.1 sur ~100, soit ~0,1 % comme prévu par le game design.

const CARDS_PATH := "res://data/cards/cards.json"

var cards: Array = []
var _total_weight := 0.0

func _ready() -> void:
	_load_cards()

func _load_cards() -> void:
	if not FileAccess.file_exists(CARDS_PATH):
		push_error("CardDatabase : fichier introuvable : " + CARDS_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CARDS_PATH))
	if parsed == null or not parsed is Dictionary or not parsed.has("cards"):
		push_error("CardDatabase : JSON invalide (clé 'cards' attendue).")
		return
	cards = parsed["cards"]
	_total_weight = 0.0
	for card in cards:
		_total_weight += float(card.get("weight", 1.0))
	print("CardDatabase : %d cartes chargées (poids total %.1f)." % [cards.size(), _total_weight])

## Tire une carte au hasard, pondérée par la rareté.
func draw_card() -> Dictionary:
	if cards.is_empty():
		push_error("CardDatabase : aucune carte chargée.")
		return {}
	var roll := randf() * _total_weight
	for card in cards:
		roll -= float(card.get("weight", 1.0))
		if roll <= 0.0:
			return card
	return cards.back()
