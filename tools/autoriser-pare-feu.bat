@echo off
setlocal
rem ============================================================
rem  DERNIERE CARTE - autorisation du pare-feu Windows
rem
rem  Ouvre les ports ENTRANTS necessaires pour heberger :
rem    - 8080 (TCP) : la page du jeu pour les invites navigateur
rem    - 4242 (TCP) : la partie elle-meme
rem  Uniquement sur les reseaux PRIVES et d'entreprise, jamais
rem  sur les reseaux publics (cafe, hotel, aeroport).
rem
rem  Le jeu lance ce script tout seul au premier hebergement.
rem  Tu peux aussi le lancer a la main : clic droit >
rem  "Executer en tant qu'administrateur".
rem
rem  Pour tout annuler plus tard :
rem    netsh advfirewall firewall delete rule name=DerniereCarte-TCP
rem ============================================================

if /I "%~1"=="/auto" goto appliquer

echo.
echo ==========================================================
echo   DERNIERE CARTE - autorisation du pare-feu Windows
echo ==========================================================
echo.
echo   A lancer sur le PC qui HEBERGE la partie, une seule fois.
echo   Ports ouverts en entree : 8080 et 4242 (TCP),
echo   sur les reseaux prives et d'entreprise uniquement.
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   [!] DROITS ADMINISTRATEUR MANQUANTS
    echo.
    echo   Ferme cette fenetre, puis CLIC DROIT sur
    echo   "autoriser-pare-feu.bat" et choisis :
    echo       "Executer en tant qu'administrateur"
    echo.
    pause
    exit /b 1
)

call :appliquer
if %errorlevel% neq 0 goto echec

echo   [OK] C'est fait, definitivement.
echo.
echo   Lance DerniereCarte.exe, clique "Heberger", et partage
echo   le lien affiche.
echo.
echo   Si tes amis ne passent toujours pas : ton reseau est
echo   peut-etre classe "Public". Va dans
echo     Parametres ^> Reseau ^> ton wifi ^> Type de profil reseau
echo   et choisis "Reseau prive".
echo.
pause
exit /b 0

:appliquer
rem Une ancienne autorisation ne couvrait peut-etre que l'UDP (le jeu
rem communique desormais en TCP) : on repart d'une regle propre.
netsh advfirewall firewall delete rule name=DerniereCarte-TCP >nul 2>&1
netsh advfirewall firewall add rule name=DerniereCarte-TCP dir=in action=allow protocol=TCP localport=4242,8080 profile=private,domain >nul 2>&1
exit /b %errorlevel%

:echec
echo   [!] La commande a echoue.
echo.
echo   Solution manuelle :
echo     Securite Windows ^> Pare-feu et protection du reseau
echo     ^> Autoriser une application via le pare-feu
echo   puis cocher Prive ET Public pour DerniereCarte.exe
echo.
pause
exit /b 1
