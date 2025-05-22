#!/bin/bash

# Détecter le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
WIFI_SSID="Max"
WIFI_PASSWORD="1234567890"
LOG_FILE="$BASE_DIR/logs/update_rpi.log"
LOG_DIR="$BASE_DIR/logs"
BG_IMAGE_SOURCE="$BASE_DIR/assets/bg.jpg"  # Changé de .png à .jpg
BG_IMAGE_DEST="/usr/share/backgrounds/maxlink"

# Créer le répertoire de logs s'il n'existe pas
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Fonction pour logger les messages
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local display=${2:-true}
    
    # Toujours écrire dans le fichier de log
    echo "[$timestamp] $message" >> "$LOG_FILE"
    
    # Afficher sur la console uniquement si demandé
    if [ "$display" = true ]; then
        printf "%s\n" "$message"
        sleep 0.5
    fi
    
    # Logger les messages importants au journal système
    if [[ "$message" == *"DÉMARRAGE"* ]] || [[ "$message" == *"ERREUR"* ]] || [[ "$message" == *"TERMINÉ"* ]] || [[ "$message" == *"REDÉMARRAGE"* ]]; then
        logger -t "update_rpi" "$message"
    fi
}

# Fonction pour afficher les sections
section_header() {
    local title="$1"
    echo ""
    echo "# $title"
    echo ""
    sleep 2
}

# Fonction pour afficher les résultats
show_result() {
    local message="$1"
    echo "↦ $message"
    echo ""
    sleep 0.5
}

# Fonction pour configurer le ventilateur
configure_fan() {
    local mode="$1"  # PRODUCTION uniquement
    local temp1="$2"
    local temp2="$3"
    
    CONFIG_FILE="/boot/firmware/config.txt"
    CONFIG_BACKUP="${CONFIG_FILE}.backup"
    
    # S'assurer que le fichier existe
    if [ ! -f "$CONFIG_FILE" ]; then
        log_message "ERREUR: Fichier config.txt introuvable" false
        show_result "ERREUR: Fichier config.txt introuvable"
        return 1
    fi
    
    # Créer une sauvegarde si elle n'existe pas déjà
    if [ ! -f "$CONFIG_BACKUP" ]; then
        cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    fi
    
    # Vérifier si les paramètres du ventilateur existent déjà
    if grep -q "dtparam=fan_temp" "$CONFIG_FILE"; then
        log_message "Mise à jour des paramètres de refroidissement..." false
        sed -i 's/dtparam=fan_temp0=.*/dtparam=fan_temp0=0/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp1=.*/dtparam=fan_temp1='$temp1'/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp2=.*/dtparam=fan_temp2='$temp2'/g' "$CONFIG_FILE"
    else
        log_message "Ajout des nouveaux paramètres de refroidissement..." false
        echo "" >> "$CONFIG_FILE"
        echo "# Configuration de refroidissement" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp0=0" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp1=$temp1" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp2=$temp2" >> "$CONFIG_FILE"
    fi
    
    # Vérifier si l'opération a réussi
    if grep -q "dtparam=fan_temp0=0" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp1=$temp1" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp2=$temp2" "$CONFIG_FILE"; then
        show_result "Refroidissement réglé sur mode <$mode>"
        return 0
    else
        log_message "ERREUR: Configuration du refroidissement échouée" false
        show_result "ERREUR: Configuration du refroidissement échouée"
        return 1
    fi
}

# Fonction pour personnaliser l'interface (version simplifiée)
customize_desktop() {
    # Vérifier si on est dans un environnement graphique
    if [ ! -d "/etc/xdg/lxsession" ]; then
        log_message "AVERTISSEMENT: Environnement graphique non détecté" false
        show_result "AVERTISSEMENT: Environnement graphique non détecté, personnalisation ignorée"
        return 1
    fi
    
    # Déterminer l'utilisateur principal (essayer M4X d'abord)
    local current_user="M4X"
    local user_home="/home/$current_user"
    
    # Vérifier si le répertoire de l'utilisateur existe
    if [ ! -d "$user_home" ]; then
        # Essayer de détecter automatiquement l'utilisateur principal
        current_user=$(ls -la /home | grep -v "^d.* \.$" | grep "^d" | head -1 | awk '{print $3}')
        user_home="/home/$current_user"
        
        # Si toujours pas trouvé, utiliser l'utilisateur exécutant le script
        if [ ! -d "$user_home" ] || [ "$current_user" = "root" ]; then
            current_user=$(who am i | awk '{print $1}')
            user_home="/home/$current_user"
            
            # Dernier recours: utiliser SUDO_USER s'il est défini
            if [ ! -d "$user_home" ] && [ -n "$SUDO_USER" ]; then
                current_user="$SUDO_USER"
                user_home="/home/$current_user"
            fi
        fi
    fi
    
    # Vérifier encore une fois si le répertoire existe
    if [ ! -d "$user_home" ]; then
        log_message "ERREUR: Impossible de trouver un répertoire utilisateur valide" false
        show_result "ERREUR: Impossible de configurer l'interface. Aucun utilisateur trouvé."
        return 1
    fi
    
    log_message "Personnalisation de l'interface pour l'utilisateur: $current_user" false
    
    # 1. Copier l'image de fond d'écran
    echo "Installation du fond d'écran personnalisé :"
    if [ -f "$BG_IMAGE_SOURCE" ]; then
        # Créer le dossier de destination s'il n'existe pas
        mkdir -p "$BG_IMAGE_DEST"
        # Toujours remplacer l'image existante
        cp -f "$BG_IMAGE_SOURCE" "$BG_IMAGE_DEST/bg.jpg"
        chmod 644 "$BG_IMAGE_DEST/bg.jpg"
        show_result "Fond d'écran installé avec succès"
    else
        log_message "AVERTISSEMENT: Image de fond d'écran non trouvée: $BG_IMAGE_SOURCE" false
        show_result "AVERTISSEMENT: Image de fond d'écran non trouvée"
    fi
    
    # 2. Désactiver l'affichage de la corbeille
    echo "Désactivation de l'affichage de la corbeille :"
    
    # Assurer que les dossiers de configuration existent
    mkdir -p "$user_home/.config/pcmanfm/LXDE-pi"
    
    # Configurer le fond d'écran et masquer la corbeille
    # Vérifier si le fichier de configuration existe déjà
    if [ -f "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" ]; then
        # Modifier le fichier existant pour changer uniquement wallpaper et show_trash
        sed -i "s|wallpaper=.*|wallpaper=$BG_IMAGE_DEST/bg.jpg|g" "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf"
        sed -i "s|show_trash=.*|show_trash=0|g" "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf"
    else
        # Créer un nouveau fichier de configuration
        cat > "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" << EOF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$BG_IMAGE_DEST/bg.jpg
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 12
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=0
show_mounts=0
EOF
    fi
    
    # S'assurer que les fichiers appartiennent à l'utilisateur
    chown -R $current_user:$current_user "$user_home/.config"
    
    # Appliquer également les configurations pour les nouveaux utilisateurs
    if [ -d "/etc/xdg" ]; then
        # Créer le dossier si nécessaire
        mkdir -p "/etc/xdg/pcmanfm/LXDE-pi"
        
        # Copier la configuration
        cp "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" "/etc/xdg/pcmanfm/LXDE-pi/"
    fi
    
    show_result "Personnalisation de l'interface réussie pour $current_user"
}

# Réinitialiser le fichier de log
echo "--- Nouvelle session: $(date) ---" > "$LOG_FILE"

# DÉMARRAGE
section_header "DÉMARRAGE DE LA MISE À JOUR DU RASPBERRY PI"

echo "Configuration du système de refroidissement :"
configure_fan "PRODUCTION" "60" "60"
sleep 2

# CONNECTIVITÉ RÉSEAU
section_header "CONNECTIVITÉ RÉSEAU"

echo "Recherche et connexion au réseau WiFi :"
# Tenter de se connecter
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" > /dev/null 2>&1
wifi_status=$?

# Vérifier l'état de la connexion
if [ $wifi_status -ne 0 ]; then
    if nmcli -t -f ACTIVE,SSID device wifi | grep "^yes:$WIFI_SSID$" > /dev/null; then
        show_result "Déjà connecté au réseau $WIFI_SSID"
    else
        echo "Nouvelle tentative de connexion..."
        nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "$WIFI_SSID" > /dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            show_result "ERREUR: Impossible de se connecter au réseau WiFi"
            exit 1
        else
            show_result "Connecté au réseau $WIFI_SSID"
        fi
    fi
else
    show_result "Connecté au réseau $WIFI_SSID"
fi

echo "Stabilisation et test de la connexion :"
sleep 5
echo "En cours..."
sleep 5
ping_result=$(ping -c 1 8.8.8.8 2>/dev/null | grep "time=" | cut -d "=" -f 4)

if [ -n "$ping_result" ]; then
    show_result "Connexion stable avec $ping_result de ping"
else
    echo "Connectivité faible, test alternatif..."
    
    if ping -c 4 google.com > /dev/null 2>&1; then
        show_result "Connexion rétablie"
    else
        show_result "ERREUR: Pas de connexion Internet"
        nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
        exit 1
    fi
fi

# VÉRIFICATION SYSTÈME
section_header "VÉRIFICATION SYSTÈME"

echo "Vérification de l'horloge système :"
current_date=$(date +%s)
online_date=$(curl -s --head http://google.com 2>/dev/null | grep -i "^date:" | sed 's/^[Dd]ate: //g' | date -f - +%s 2>/dev/null || echo 0)

if [ "$online_date" != "0" ]; then
    date_diff=$((current_date - online_date))
    date_diff=${date_diff#-} # Valeur absolue
    
    if [ $date_diff -gt 60 ]; then
        echo "Horloge désynchronisée (${date_diff}s), synchronisation en cours..."
        
        # Installer ntpdate si nécessaire
        if ! command -v ntpdate > /dev/null; then
            log_message "Installation de ntpdate..." false
            apt-get update > /dev/null 2>&1
            apt-get install -y ntpdate > /dev/null 2>&1
        fi
        
        if ntpdate pool.ntp.org > /dev/null 2>&1; then
            show_result "Horloge synchronisée"
        else
            show_result "ERREUR: Échec de la synchronisation d'horloge"
        fi
    else
        show_result "Horloge interne synchronisée"
    fi
else
    show_result "AVERTISSEMENT: Impossible de vérifier l'heure en ligne"
fi

# MISE À JOUR DU SYSTÈME
section_header "MISE À JOUR DU SYSTÈME"

# Créer des fichiers de log pour chaque commande
UPDATE_LOG="$LOG_DIR/apt_update.log"
UPGRADE_LOG="$LOG_DIR/apt_upgrade.log"
CLEAN_LOG="$LOG_DIR/apt_clean.log"

echo "Téléchargement des informations sur les dépôts :"
apt-get update -y >> "$UPDATE_LOG" 2>&1
update_status=$?

if [ $update_status -ne 0 ]; then
    show_result "ERREUR: Échec du téléchargement des informations sur les dépôts"
else
    show_result "Informations sur les dépôts téléchargées avec succès"
    
    echo "Installation des mises à jour système :"
    echo "Cette opération peut prendre plusieurs minutes..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$UPGRADE_LOG" 2>&1
    upgrade_status=$?
    
    if [ $upgrade_status -ne 0 ]; then
        show_result "ERREUR: Échec de l'installation des mises à jour"
    else
        show_result "Installation des mises à jour système terminée"
        
        echo "Nettoyage du système :"
        {
            apt-get autoremove -y
            apt-get autoclean -y
        } >> "$CLEAN_LOG" 2>&1
        show_result "Nettoyage terminé"
    fi
fi

# PERSONNALISATION DE L'INTERFACE
section_header "PERSONNALISATION DE L'INTERFACE"
customize_desktop

# Déconnexion du WiFi
echo "Déconnexion du réseau WiFi :"
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
show_result "Déconnecté du réseau WiFi"

# Affichage du statut final et préparation du redémarrage
if [ $update_status -eq 0 ] && [ $upgrade_status -eq 0 ]; then
    section_header "MISE À JOUR TERMINÉE AVEC SUCCÈS"
else
    section_header "MISE À JOUR TERMINÉE AVEC DES ERREURS"
    echo "Consultez les logs pour plus de détails."
    echo ""
fi

# Art ASCII
cat << "EOF"

 /$$      /$$                     /$$       /$$           /$$   /$$   
| $$$    /$$$                    | $$      |__/          | $$  /$$/   
| $$$$  /$$$$  /$$$$$$  /$$   /$$| $$       /$$ /$$$$$$$ | $$ /$$/    
| $$ $$/$$ $$ |____  $$|  $$ /$$/| $$      | $$| $$__  $$| $$$$$/     
| $$  $$$| $$  /$$$$$$$ \  $$$$/ | $$      | $$| $$  \ $$| $$  $$     
| $$\  $ | $$ /$$__  $$  >$$  $$ | $$      | $$| $$  | $$| $$\  $$    
| $$ \/  | $$|  $$$$$$$ /$$/\  $$| $$$$$$$$| $$| $$  | $$| $$ \  $$   
|__/     |__/ \_______/|__/  \__/|________/|__/|__/  |__/|__/  \__/   
                                                                      
                                                                      
                                                                      
 /$$   /$$                 /$$             /$$                     /$$
| $$  | $$                | $$            | $$                    | $$
| $$  | $$  /$$$$$$   /$$$$$$$  /$$$$$$  /$$$$$$    /$$$$$$       | $$
| $$  | $$ /$$__  $$ /$$__  $$ |____  $$|_  $$_/   /$$__  $$      | $$
| $$  | $$| $$  \ $$| $$  | $$  /$$$$$$$  | $$    | $$$$$$$$      |__/
| $$  | $$| $$  | $$| $$  | $$ /$$__  $$  | $$ /$$| $$_____/          
|  $$$$$$/| $$$$$$$/|  $$$$$$$|  $$$$$$$  |  $$$$/|  $$$$$$$       /$$
 \______/ | $$____/  \_______/ \_______/   \___/   \_______/      |__/
          | $$                                                        
          | $$                                                        
          |__/                                                        

EOF

show_result "Le système va redémarrer dans 15 secondes..."
sleep 15

log_message "REDÉMARRAGE DU SYSTÈME" false
# Ajout d'un délai final pour s'assurer que le message est vu
sleep 2
reboot