# Rustine appliquée APRÈS chaque export web.
#
# Pourquoi : dans le code généré par Godot, GodotAudio.init() appelle
#     ctx.audioWorklet.addModule(...)
# SANS vérifier que audioWorklet existe. Or un navigateur ne fournit
# audioWorklet que dans un « contexte sécurisé » (HTTPS ou localhost) : servi
# en HTTP sur une IP locale — le cas de nos invités — audioWorklet vaut
# undefined et le jeu meurt au démarrage sur
#     « Cannot read properties of undefined (reading 'addModule') ».
#
# Le moteur sait pourtant se replier : _godot_audio_has_worklet() renvoie 0
# dans ce cas, et il choisit alors le pilote ScriptProcessor. Il suffit donc
# que cet appel-là ne plante pas. On le garde, et on remplace la promesse par
# une promesse qui ne se résout jamais : le worklet de POSITION (lecture
# « Sample ») n'est ainsi jamais branché — c'est voulu, le projet force la
# lecture « Stream » sur le web (voir project.godot).
#
# Usage : python3 tools/patch_web_audio.py <dossier_export_web>
# Le script ÉCHOUE bruyamment si le motif est absent : une mise à jour de
# Godot doit nous alerter, pas produire silencieusement un build cassé.
import sys
import pathlib

MOTIF = "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)"
RUSTINE = ("GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet"
           "?ctx.audioWorklet.addModule(path)"
           ":new Promise(function(){})")

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_web_audio.py <dossier_export_web>")
        return 2
    js_files = sorted(pathlib.Path(sys.argv[1]).glob("*.js"))
    cibles = [f for f in js_files if MOTIF in f.read_text(encoding="utf-8", errors="replace")]
    if not cibles:
        deja = [f for f in js_files if "?ctx.audioWorklet.addModule(path)" in
                f.read_text(encoding="utf-8", errors="replace")]
        if deja:
            print("RUSTINE_DEJA_APPLIQUEE")
            return 0
        print("ECHEC : motif audioWorklet introuvable — Godot a-t-il changé "
              "son code généré ? Vérifier avant de distribuer.")
        return 1
    for fichier in cibles:
        contenu = fichier.read_text(encoding="utf-8", errors="replace")
        fichier.write_text(contenu.replace(MOTIF, RUSTINE), encoding="utf-8")
        print("RUSTINE_APPLIQUEE %s" % fichier.name)
    return 0

if __name__ == "__main__":
    sys.exit(main())
