#!/bin/bash

# Détecter le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
WIFI_SSID="Max"
WIFI_PASSWORD="1234567890"
LOG_FILE="$BASE_DIR/logs/update_rpi.log"
LOG_DIR="$BASE_DIR/logs"

# Créer le répertoire de logs s'il n'existe pas
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Fonction pour logger les messages (optimisée)
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local display=${2:-true}  # Paramètre optionnel pour contrôler l'affichage
    
    # Toujours écrire dans le fichier de log
    echo "[$timestamp] $message" >> "$LOG_FILE"
    
    # Afficher sur la console uniquement si demandé
    if [ "$display" = true ]; then
        printf "%s\n" "$message"
        # Petit délai pour une meilleure lisibilité
        sleep 0.2
    fi
    
    # Logger uniquement les messages importants
    if [[ "$message" == *"DÉMARRAGE"* ]] || [[ "$message" == *"ERREUR"* ]] || [[ "$message" == *"TERMINÉ"* ]] || [[ "$message" == *"REDÉMARRAGE"* ]]; then
        logger -t "update_rpi" "$message"
    fi
}

# Fonction pour les transitions entre les étapes principales
next_section() {
    local title="$1"
    echo ""
    log_message "$title"
    sleep 1  # Délai plus long entre les sections principales
}

# Réinitialiser le fichier de log
echo "--- Nouvelle session: $(date) ---" > "$LOG_FILE"

next_section "DÉMARRAGE DE LA MISE À JOUR DU RASPBERRY PI"

# Configuration du ventilateur
log_message "Configuration du refroidissement..."

CONFIG_FILE="/boot/firmware/config.txt"
CONFIG_BACKUP="${CONFIG_FILE}.backup"

# Vérifier et configurer en journalisant de manière détaillée dans le fichier
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    
    # Vérifier et mettre à jour les paramètres du ventilateur (journalisation détaillée dans le fichier uniquement)
    if grep -q "dtparam=fan_temp" "$CONFIG_FILE"; then
        log_message "Mise à jour des paramètres de refroidissement existants..." false
        sed -i 's/dtparam=fan_temp0=.*/dtparam=fan_temp0=0/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp1=.*/dtparam=fan_temp1=60/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp2=.*/dtparam=fan_temp2=60/g' "$CONFIG_FILE"
    else
        log_message "Ajout des nouveaux paramètres de refroidissement..." false
        echo "" >> "$CONFIG_FILE"
        echo "# Configuration de refroidissement" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp0=0" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp1=60" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp2=60" >> "$CONFIG_FILE"
    fi
    
    # Vérifier si l'opération a réussi
    if grep -q "dtparam=fan_temp0=0" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp1=60" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp2=60" "$CONFIG_FILE"; then
        log_message "Refroidissement réglé sur mode <Production>"
    else
        log_message "ERREUR: Configuration du refroidissement échouée"
    fi
else
    log_message "ERREUR: Fichier config.txt introuvable"
fi

sleep 1

# Connexion au WiFi
next_section "CONNECTIVITÉ RÉSEAU"
log_message "Connexion au réseau WiFi..."

# Tenter de se connecter
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" > /dev/null 2>&1
wifi_status=$?

# Vérifier l'état de la connexion
if [ $wifi_status -ne 0 ]; then
    if nmcli -t -f ACTIVE,SSID device wifi | grep "^yes:$WIFI_SSID$" > /dev/null; then
        log_message "Déjà connecté au réseau $WIFI_SSID"
    else
        log_message "Nouvelle tentative de connexion..."
        nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "$WIFI_SSID" > /dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            log_message "ERREUR: Impossible de se connecter au réseau WiFi"
            exit 1
        fi
    fi
else
    log_message "Connecté au réseau $WIFI_SSID"
fi

# Attente pour stabilisation
log_message "Stabilisation de la connexion (15s)..."
sleep 15

# Test de connectivité Internet
log_message "Test de connectivité Internet..."

if ping -c 4 8.8.8.8 > /dev/null 2>&1; then
    log_message "Connectivité Internet OK"
else
    log_message "Connectivité faible, test alternatif..."
    
    if ping -c 4 google.com > /dev/null 2>&1; then
        log_message "Connexion rétablie"
    else
        log_message "ERREUR: Pas de connexion Internet"
        nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
        exit 1
    fi
fi

sleep 1

# Vérification de l'horloge système
log_message "Vérification de l'horloge système..."

current_date=$(date +%s)
online_date=$(curl -s --head http://google.com 2>/dev/null | grep -i "^date:" | sed 's/^[Dd]ate: //g' | date -f - +%s 2>/dev/null || echo 0)

if [ "$online_date" != "0" ]; then
    date_diff=$((current_date - online_date))
    date_diff=${date_diff#-} # Valeur absolue
    
    if [ $date_diff -gt 60 ]; then
        log_message "Horloge désynchronisée (${date_diff}s), synchronisation en cours..."
        
        # Installer ntpdate si nécessaire et synchroniser (log détaillé dans le fichier uniquement)
        if ! command -v ntpdate > /dev/null; then
            log_message "Installation de ntpdate..." false
            apt-get update > /dev/null 2>&1
            apt-get install -y ntpdate > /dev/null 2>&1
        fi
        
        if ntpdate pool.ntp.org > /dev/null 2>&1; then
            log_message "Horloge synchronisée"
        else
            log_message "ERREUR: Échec de la synchronisation d'horloge"
        fi
    else
        log_message "Horloge système OK"
    fi
else
    log_message "AVERTISSEMENT: Impossible de vérifier l'heure en ligne"
fi

sleep 1

# Mise à jour du système
next_section "MISE À JOUR DU SYSTÈME"

# Créer des fichiers de log pour chaque commande
UPDATE_LOG="$LOG_DIR/apt_update.log"
UPGRADE_LOG="$LOG_DIR/apt_upgrade.log"
CLEAN_LOG="$LOG_DIR/apt_clean.log"

# apt update
log_message "Mise à jour des dépôts..."
apt-get update -y >> "$UPDATE_LOG" 2>&1
update_status=$?

if [ $update_status -ne 0 ]; then
    log_message "ERREUR: Échec de la mise à jour des dépôts"
else
    # apt upgrade
    log_message "Mise à niveau des paquets (peut prendre plusieurs minutes)..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$UPGRADE_LOG" 2>&1
    upgrade_status=$?
    
    if [ $upgrade_status -ne 0 ]; then
        log_message "ERREUR: Échec de la mise à niveau des paquets"
    else
        log_message "Mise à niveau des paquets terminée"
        
        # Nettoyage combiné
        log_message "Nettoyage du système..."
        {
            apt-get autoremove -y
            apt-get autoclean -y
        } >> "$CLEAN_LOG" 2>&1
        log_message "Nettoyage terminé"
    fi
fi

sleep 1

# Déconnexion du WiFi
log_message "Déconnexion du réseau WiFi..."
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1

# Affichage du statut final et préparation du redémarrage
if [ $update_status -eq 0 ] && [ $upgrade_status -eq 0 ]; then
    next_section "MISE À JOUR TERMINÉE AVEC SUCCÈS"
    
    # Art ASCII
    cat << "EOF"
  __  __            _     _       _    
 |  \/  |          | |   (_)     | |   
 | \  / | __ ___  _| |    _ _ __ | | __
 | |\/| |/ _' \ \/ / |   | | '_ \| |/ /
 | |  | | (_| |>  <| |___| | | | |   < 
 |_|  |_|\__,_/_/\_\_____|_|_| |_|_|\_\
                                       
EOF
else
    next_section "MISE À JOUR TERMINÉE AVEC DES ERREURS"
    
    # Art ASCII avec message d'erreur
    cat << "EOF"
  __  __            _     _       _    
 |  \/  |          | |   (_)     | |   
 | \  / | __ ___  _| |    _ _ __ | | __
 | |\/| |/ _' \ \/ / |   | | '_ \| |/ /
 | |  | | (_| |>  <| |___| | | | |   < 
 |_|  |_|\__,_/_/\_\_____|_|_| |_|_|\_\

 Consultez les logs pour plus de détails.
EOF
fi

log_message "Le système va redémarrer dans 15 secondes..."
sleep 15

log_message "REDÉMARRAGE DU SYSTÈME"
# Ajout d'un délai final pour s'assurer que le message est vu
sleep 1
reboot