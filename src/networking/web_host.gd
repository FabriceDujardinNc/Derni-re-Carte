extends Node
class_name WebHost
## WebHost — petit serveur HTTP intégré au jeu (côté HÔTE uniquement).
##
## But : qu'un invité n'ait RIEN à télécharger. L'hôte sert la version
## navigateur du jeu ; l'invité ouvre http://<ip-de-l-hote>:8080 dans Chrome,
## la page se connecte en WebSocket au jeu de l'hôte, et il joue.
##
## Volontairement minimal : GET de fichiers statiques, un dossier, pas de
## cache, pas de TLS (réseau local entre amis). Les gros fichiers (.wasm de
## plusieurs dizaines de Mo) partent par TRANCHES pour ne jamais figer la
## partie de l'hôte pendant qu'un invité charge la page.

const HTTP_PORT := 8080
const CHUNK_SIZE := 262144  ## 256 Ko envoyés par connexion et par frame.
const MAX_REQUEST_BYTES := 8192

## En-têtes OBLIGATOIRES pour un export web Godot avec threads : sans
## isolation d'origine, le navigateur refuse SharedArrayBuffer et le jeu
## reste sur un écran noir.
const ISOLATION_HEADERS := "Cross-Origin-Opener-Policy: same-origin\r\n" \
	+ "Cross-Origin-Embedder-Policy: require-corp\r\n"

const MIME_TYPES := {
	"html": "text/html; charset=utf-8",
	"js": "text/javascript; charset=utf-8",
	"json": "application/json; charset=utf-8",
	"wasm": "application/wasm",
	"pck": "application/octet-stream",
	"png": "image/png",
	"svg": "image/svg+xml",
	"ico": "image/x-icon",
	"webmanifest": "application/manifest+json",
}

var served_directory := ""  ## Dossier contenant index.html (vide = introuvable).
var _server: TCPServer
var _clients: Array[Dictionary] = []

## Dossier de la version navigateur : livré à côté de l'exécutable (dossier
## « web/ » de l'archive). `-- webdir=/chemin` permet de le pointer ailleurs
## pendant les tests. Il n'est JAMAIS dans res:// : il pèserait aussi lourd
## que le jeu et se retrouverait embarqué dans chaque export natif.
static func find_web_build() -> String:
	var candidates: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("webdir="):
			candidates.append(arg.get_slice("=", 1))
	candidates.append(OS.get_executable_path().get_base_dir().path_join("web"))
	for directory in candidates:
		if FileAccess.file_exists(directory.path_join("index.html")):
			return directory
	return ""

## Adresse à communiquer aux invités. Les préfixes sont testés DANS L'ORDRE :
## 192.168 (box domestique / bureau) avant 10. puis 172. — sinon on annonce
## parfois une interface virtuelle (WSL, Docker, VPN) injoignable des invités.
static func local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for prefix in ["192.168.", "10.", "172."]:
		for address in addresses:
			if address.begins_with(prefix):
				return address
	return "127.0.0.1"

## Démarre le partage. Renvoie faux si la version navigateur est absente : le
## multijoueur classique continue de fonctionner, seul le lien n'est pas offert.
func start() -> bool:
	served_directory = find_web_build()
	if served_directory.is_empty():
		print("WebHost : pas de version navigateur à servir (dossier web/ absent).")
		return false
	_server = TCPServer.new()
	var error := _server.listen(HTTP_PORT)
	if error != OK:
		print("WebHost : port %d indisponible (%d)." % [HTTP_PORT, error])
		_server = null
		return false
	print("WebHost : partage sur http://%s:%d (dossier %s)"
		% [local_ip(), HTTP_PORT, served_directory])
	return true

func is_sharing() -> bool:
	return _server != null

## Lien à communiquer aux invités (mot de passe inclus : ils n'ont rien à taper).
func share_url(pwd: String) -> String:
	var url := "http://%s:%d" % [local_ip(), HTTP_PORT]
	if not pwd.is_empty():
		url += "/?mdp=" + pwd.uri_encode()
	return url

func stop() -> void:
	for client in _clients:
		(client["socket"] as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
		_server = null

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"socket": _server.take_connection(), "request": PackedByteArray(),
			"file": null, "sent": 0})
	# Parcours à l'envers : on retire les connexions terminées au passage.
	for i in range(_clients.size() - 1, -1, -1):
		if not _serve(_clients[i]):
			(_clients[i]["socket"] as StreamPeerTCP).disconnect_from_host()
			_clients.remove_at(i)

## Fait avancer une connexion d'un cran. Renvoie faux quand elle est finie.
func _serve(client: Dictionary) -> bool:
	var socket: StreamPeerTCP = client["socket"]
	socket.poll()
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false

	# Phase 2 : un fichier est en cours d'envoi, on pousse la tranche suivante.
	var file: FileAccess = client["file"]
	if file != null:
		var remaining: int = file.get_length() - int(client["sent"])
		if remaining <= 0:
			return false
		var chunk := file.get_buffer(mini(CHUNK_SIZE, remaining))
		if socket.put_data(chunk) != OK:
			return false
		client["sent"] = int(client["sent"]) + chunk.size()
		return int(client["sent"]) < file.get_length()

	# Phase 1 : lecture de la requête jusqu'à la fin des en-têtes.
	var available := socket.get_available_bytes()
	if available > 0:
		var buffer: PackedByteArray = client["request"]
		buffer.append_array(socket.get_partial_data(available)[1])
		client["request"] = buffer
	var request: String = (client["request"] as PackedByteArray).get_string_from_utf8()
	if not request.contains("\r\n\r\n"):
		return (client["request"] as PackedByteArray).size() < MAX_REQUEST_BYTES
	return _respond(client, socket, request.get_slice("\r\n", 0))

## Répond à la ligne de requête (« GET /chemin HTTP/1.1 »).
func _respond(client: Dictionary, socket: StreamPeerTCP, request_line: String) -> bool:
	var parts := request_line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		_send_error(socket, "405 Method Not Allowed")
		return false
	# On ignore la query (elle sert au navigateur : ?mdp=…).
	var path := parts[1].get_slice("?", 0).uri_decode()
	if path == "/" or path.is_empty():
		path = "/index.html"
	# Anti-traversée : jamais de « .. », jamais de sortie du dossier servi.
	if path.contains(".."):
		_send_error(socket, "403 Forbidden")
		return false
	var full_path := served_directory.path_join(path.trim_prefix("/"))
	var file := FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		_send_error(socket, "404 Not Found")
		return false
	var mime: String = MIME_TYPES.get(full_path.get_extension().to_lower(),
		"application/octet-stream")
	var header := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\n%s" \
		% [mime, file.get_length(), ISOLATION_HEADERS] \
		+ "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
	if socket.put_data(header.to_utf8_buffer()) != OK:
		return false
	if file.get_length() == 0:
		return false
	client["file"] = file
	client["sent"] = 0
	return true

func _send_error(socket: StreamPeerTCP, status: String) -> void:
	socket.put_data(("HTTP/1.1 %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		% status).to_utf8_buffer())
