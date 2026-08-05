# 🎮 Dernière Carte

Jeu multijoueur indépendant orienté **bluff, humour, tension et interactions sociales**, pensé pour Steam. Chaque joueur pioche une carte à tour de rôle — seul lui sait ce qu'elle contient. Les autres doivent lire ses réactions… ou se faire avoir.

## 🚀 Lancer le prototype

1. Installer [Godot 4.7+](https://godotengine.org/download) (version standard, pas .NET).
2. Ouvrir Godot → **Importer** → sélectionner `project.godot`.
3. Lancer avec **F5**.

Aucun asset externe requis : tout le prototype est généré par code (avatars capsules, table, lumières).

### Contrôles

| Touche | Action |
|---|---|
| Souris | Regarder autour de soi |
| **ESPACE** ou **clic sur la pioche** | Piocher (à son tour, assis — la pioche s'illumine) |
| **Molette** | Choisir une carte de sa main |
| **Clic droit** | Utiliser la carte choisie (sur soi, ou **en visant un joueur** si elle se lance) |
| **E** | Se lever / retourner s'asseoir |
| **ZQSD** | Marcher autour de la table (debout) |
| **Clic gauche** sur un joueur | **Gifler** (cible debout, à portée) ou **caillasser** le lambin désigné |
| **1 – 4** | Émotes 😀 😂 😱 🤫 (à tout moment — outil de bluff) |
| **Q / D** (assis) | Pivoter le regard au clavier |
| **Échap** | Libérer / capturer la souris |
| **R** / **M** | Rejouer / retour au menu (fin de partie) |

### Ce que contient le prototype

- **Menu principal** : nom du joueur, nombre de joueurs (2-8), couleur du personnage. **La table s'adapte au nombre de joueurs** (intime à 4, grande tablée à 8).
- **Multijoueur (LAN/IP)** 🌐 : bouton **Héberger** (mot de passe optionnel, port 4242) → salle d'attente qui affiche l'IP à partager ; bouton **Rejoindre** (IP + mot de passe). **Humains et bots se mélangent** : les vrais joueurs remplissent d'abord la table, les bots complètent les sièges restants. L'hôte fait autorité (anti-triche par construction) ; les clients envoient leurs actions et voient tout en miroir. Solo = le même jeu avec 1 humain.
- Bots à personnalités (menteur, peureux, agressif, calculateur, troll, prudent) qui bluffent avec des émotes. Chaque personnage porte un **chapeau distinctif** (haut-de-forme, casquette, chapeau pointu, béret), des sourcils et des pieds ; décor de taverne : murs, plafond, lustre suspendu, tapis, tabourets.
- **10 cartes** data-driven (JSON) : Médikit, Bouclier, Mini-grenade, Poison, Brûlure, Explosion, Absolument Rien (faux indice sonore), la **Carte du Destin** (~0,1 %, mort différée absurde : piano, météorite, extraterrestres…), et deux cartes **lançables sur un joueur** : Grenade lançable 🤾 et Huile chaude 🍳.
- **Main de cartes (3 emplacements)** : les cartes `keepable` (Médikit, Bouclier, lançables) se gardent pour plus tard. Les autres voient seulement « X garde une carte dans sa manche… » — utiliser une carte, en revanche, est un acte public. Les bots gardent leur Médikit pour les coups durs et vous jettent des grenades selon leur agressivité.
- **Se lever pour espionner (E + ZQSD)** : quitter sa chaise, contourner la table et lire par-dessus l'épaule — la carte piochée est **écrite sur sa face 3D**, et s'approcher d'un joueur révèle sa manche dans le journal. Contrepartie : debout, on peut se faire **gifler** (-5 PV + projection). Les grenades, elles, se lancent à tout moment, sur n'importe qui. Il faut être assis à sa place pour piocher. Les bots espionnent et giflent aussi, selon leur personnalité.
- **Cailloux** : un tas devant chaque place. Un joueur **debout** est caillassable **à tout moment** (-6 PV : être debout, ça expose). Et si le joueur dont c'est le tour ne pioche pas sous 15 s, une bannière « 🪨 LAPIDATION AUTORISÉE » s'affiche : le lambin devient caillassable même assis (-3 PV) jusqu'à ce qu'il pioche… ou qu'il y reste. Clic gauche : gifle à portée de bras, caillou au-delà.
- **100 PV**, dégâts progressifs, effets sur la durée (poison, brûlure).
- **Dégradation visible** : paliers 100/75/50/25/10 % → teinte assombrie, tremblements, halètement. *Les PV des autres ne sont jamais affichés : on lit leur corps.*
- Boucle de tours avec **fenêtre de réaction** (le moment du bluff), journal d'événements, fin de partie et rejeu.

## 🏗️ Architecture

```
project.godot          Godot 4.7 · rendu Forward Mobile (petits GPU, Steam Deck)
scenes/main.tscn       Scène principale (assembleur minimal)
data/cards/cards.json  ← LES CARTES. Ajouter une carte = ajouter une entrée JSON.
src/
├── core/
│   ├── event_bus.gd        Autoload. Bus de signaux : les modules ne se
│   │                       référencent JAMAIS directement (prépare le réseau).
│   └── turn_manager.gd     Boucle de tours : pioche → réaction → résolution.
├── cards/
│   ├── card_database.gd    Autoload. Charge le JSON, pioche pondérée par rareté.
│   └── effect_executor.gd  Interprète les effets (damage/heal/shield/dot/fake/doom).
├── characters/
│   ├── character_base.gd   Avatar + langage corporel (dégradation, émotes, mort drôle).
│   ├── health_component.gd PV, bouclier, paliers visuels. Composant pur.
│   └── player_controller.gd Entrées du joueur local.
├── status/
│   └── status_manager.gd   Effets sur la durée (DoT, Carte du Destin).
├── ai/
│   └── bot_brain.gd        Personnalités + bluff des bots.
└── ui/
    ├── hud.gd              HUD du joueur local (construit par code).
    └── fonts.gd            Polices système + repli emoji.
```

**Principes :**
- **Data-driven** : cartes en JSON → base du modding et du Workshop Steam.
- **Découplage total** via `EventBus` : la future couche réseau (ENet/Steam) n'aura qu'à répliquer ces signaux.
- **Composants purs** (`HealthComponent` ne connaît ni l'UI ni le bus) → testables et réutilisables.
- **Performance d'abord** : rendu Forward Mobile, zéro particule, matériaux simples. Cible : 60 FPS sur GTX 1050 Ti / Iris Xe / Steam Deck.

## 🗺️ Prochaines étapes (roadmap)

1. **Équilibrage** : rythme des tours, courbe de dégâts, mort subite si la partie s'éternise (simulation : `godot --headless . -- autoplay turbo`).
1. **Main de cartes physique** : tenir ses cartes en éventail, les réorganiser à la souris (drag & drop), les incliner — la façon de manipuler ses cartes devient elle-même un tell lisible par les autres.
2. **Bots lecteurs** : les IA réagissent aux émotes des autres (accusations, méfiance).
3. **Audio** : faux bruits de goupille, battements de cœur, murmures (module Audio branché sur `fake_event`).
4. **Game Director** : événements aléatoires (coupure de courant, pluie de poulets…).
5. **Multijoueur** : ENet d'abord, puis Steam Networking + lobbies.
6. **Vrais avatars** : modèles Blender expressifs remplaçant les capsules.
