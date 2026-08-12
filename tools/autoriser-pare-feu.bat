@echo off
chcp 65001 >nul
title Derniere Carte - autoriser le pare-feu
echo.
echo ==========================================================
echo   DERNIERE CARTE - autorisation du pare-feu Windows
echo ==========================================================
echo.
echo   A lancer UNE SEULE FOIS, et seulement sur le PC qui
echo   HEBERGE la partie.
echo.
echo   Ce script autorise les connexions ENTRANTES sur deux
echo   ports, pour que tes amis puissent entrer :
echo.
echo     - port 8080 (TCP) : la page du jeu dans leur navigateur
echo     - port 4242 (TCP) : la partie elle-meme
echo.

rem --- Verification des droits administrateur ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   [!] DROITS ADMINISTRATEUR MANQUANTS
    echo.
    echo   Ferme cette fenetre, puis fais un CLIC DROIT sur
    echo   "autoriser-pare-feu.bat" et choisis :
    echo.
    echo       "Executer en tant qu'administrateur"
    echo.
    pause
    exit /b 1
)

rem On efface d'eventuelles anciennes regles du meme nom : si une
rem autorisation precedente ne couvrait que l'UDP, elle ne sert plus a
rem rien (le jeu communique maintenant en TCP) et pourrait meme genher.
netsh advfirewall firewall delete rule name="Derniere Carte - jeu (TCP 4242)" >nul 2>&1
netsh advfirewall firewall delete rule name="Derniere Carte - page web (TCP 8080)" >nul 2>&1

netsh advfirewall firewall add rule name="Derniere Carte - jeu (TCP 4242)" dir=in action=allow protocol=TCP localport=4242 profile=private,domain >nul
if %errorlevel% neq 0 goto echec
netsh advfirewall firewall add rule name="Derniere Carte - page web (TCP 8080)" dir=in action=allow protocol=TCP localport=8080 profile=private,domain >nul
if %errorlevel% neq 0 goto echec

echo   [OK] C'est fait !
echo.
echo   Lance maintenant DerniereCarte.exe, clique "Heberger",
echo   et partage le lien affiche a tes amis.
echo.
echo   Si ca ne marche toujours pas, ton reseau est peut-etre
echo   classe "Public" par Windows. Va dans :
echo     Parametres ^> Reseau ^> ton wifi ^> Type de profil reseau
echo   et choisis "Reseau prive".
echo.
pause
exit /b 0

:echec
echo   [!] La commande a echoue.
echo.
echo   Autre solution, a la main :
echo     Parametres ^> Confidentialite et securite ^> Securite Windows
echo     ^> Pare-feu et protection du reseau
echo     ^> Autoriser une application via le pare-feu
echo   puis cocher les deux cases (Prive ET Public) pour
echo   DerniereCarte.exe
echo.
pause
exit /b 1
