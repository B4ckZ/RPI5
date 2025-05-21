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

# Fonction pour logger les messages (mode ultra simple)
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Écrire dans le fichier de log avec timestamp
    echo "[$timestamp] $message" >> "$LOG_FILE"
    
    # Afficher sur la console sans aucune séquence d'échappement
    printf "%s\n" "$message"
    
    # Envoyer au journal système
    logger -t "update_rpi" "$message"
}

# Vider le fichier de log précédent
echo "" > "$LOG_FILE"

log_message "=== DÉMARRAGE DE LA MISE À JOUR DU RASPBERRY PI ==="

# Nouvelle étape: Configuration du ventilateur du Raspberry Pi
log_message "> Configuration de refroidissement"

# Chemin du fichier de configuration
CONFIG_FILE="/boot/firmware/config.txt"
CONFIG_BACKUP="${CONFIG_FILE}.backup"

# Vérifier si le fichier config.txt existe
if [ -f "$CONFIG_FILE" ]; then
    # Créer une sauvegarde du fichier original
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    
    # Vérifier si les paramètres du ventilateur existent déjà
    if grep -q "dtparam=fan_temp" "$CONFIG_FILE"; then
        log_message "  Mise à jour des paramètres de refroidissement..."
        
        # Utiliser sed pour remplacer les lignes existantes
        sed -i 's/dtparam=fan_temp0=.*/dtparam=fan_temp0=0/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp1=.*/dtparam=fan_temp1=60/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp2=.*/dtparam=fan_temp2=60/g' "$CONFIG_FILE"
    else
        log_message "  Ajout des nouveaux paramètres de refroidissement..."
        
        # Ajouter les paramètres à la fin du fichier
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
        log_message "  Paramètre de refroidissement réglé sur le mode <Production>"
    else
        log_message "  Échec de la configuration de refroidissement"
    fi
else
    log_message "  Fichier config.txt introuvable"
fi

# Étape 1: Connexion au WiFi
log_message "> Connexion au réseau WiFi..."
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    # Vérifier si on est déjà connecté à ce réseau
    if nmcli -t -f ACTIVE,SSID device wifi | grep "^yes:$WIFI_SSID$" > /dev/null; then
        log_message "  Déjà connecté au réseau $WIFI_SSID"
    else
        # Si on ne peut pas se connecter, on tente de créer une nouvelle connexion
        log_message "  Tentative de création d'une nouvelle connexion..."
        nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "$WIFI_SSID" > /dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            log_message "  Impossible de se connecter au réseau. Arrêt."
            exit 1
        fi
    fi
else
    log_message "  Connecté au réseau $WIFI_SSID"
fi

# Attente pour stabilisation de la connexion
log_message "  Attente de stabilisation de la connexion..."
sleep 15
log_message "  Connexion stabilisée"

# Étape 2: Vérification de la connectivité Internet
log_message "> Test & Vérification de la connectivité Internet..."

if ping -c 4 8.8.8.8 > /dev/null 2>&1; then
    log_message "  Connectivité Internet OK"
else
    log_message "  Connectivité faible, test alternatif..."
    
    if ping -c 4 google.com > /dev/null 2>&1; then
        log_message "  Connexion rétablie"
    else
        log_message "  Pas de connexion Internet. Arrêt."
        nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
        exit 1
    fi
fi

# Étape 3: Vérification de l'horloge système
log_message "> Vérification de l'horloge système..."

current_date=$(date +%s)
online_date=$(curl -s --head http://google.com 2>/dev/null | grep -i "^date:" | sed 's/^[Dd]ate: //g' | date -f - +%s 2>/dev/null || echo 0)

# Si la date en ligne est valide (différente de 0)
if [ "$online_date" != "0" ]; then
    # Calculer la différence en secondes
    date_diff=$((current_date - online_date))
    date_diff=${date_diff#-} # Valeur absolue
    
    if [ $date_diff -gt 60 ]; then
        log_message "  Horloge désynchronisée (${date_diff}s)"
        log_message "  Synchronisation en cours..."
        
        # Installer ntpdate si nécessaire
        if ! command -v ntpdate > /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y ntpdate > /dev/null 2>&1
        fi
        
        # Synchroniser l'horloge
        if ntpdate pool.ntp.org > /dev/null 2>&1; then
            log_message "  Horloge synchronisée"
        else
            log_message "  Échec de la synchronisation"
        fi
    else
        log_message "  Horloge système OK"
    fi
else
    log_message "  Impossible de vérifier l'heure en ligne"
fi

# Étape 4: Mise à jour du système
log_message "=== MISE À JOUR DU SYSTÈME ==="

# Créer des fichiers de log temporaires pour chaque commande
UPDATE_LOG="$LOG_DIR/apt_update.log"
UPGRADE_LOG="$LOG_DIR/apt_upgrade.log"
AUTOREMOVE_LOG="$LOG_DIR/apt_autoremove.log"
AUTOCLEAN_LOG="$LOG_DIR/apt_autoclean.log"

# Exécuter apt update
log_message "> Mise à jour des dépôts (apt update)..."
apt-get update -y >> "$UPDATE_LOG" 2>&1
update_status=$?
if [ $update_status -eq 0 ]; then
    log_message "  Mise à jour des dépôts terminée"
else
    log_message "  Échec de la mise à jour des dépôts"
fi

if [ $update_status -eq 0 ]; then
    # Exécuter apt upgrade
    log_message "> Mise à niveau des paquets (apt upgrade)..."
    log_message "  Cette opération peut prendre plusieurs minutes..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$UPGRADE_LOG" 2>&1
    upgrade_status=$?
    
    if [ $upgrade_status -eq 0 ]; then
        log_message "  Mise à niveau des paquets terminée"
        
        # Nettoyage du système
        log_message "> Nettoyage du système..."
        apt-get autoremove -y >> "$AUTOREMOVE_LOG" 2>&1
        log_message "  Suppression des paquets obsolètes terminée"
        
        apt-get autoclean -y >> "$AUTOCLEAN_LOG" 2>&1
        log_message "  Nettoyage du cache APT terminé"
    else
        log_message "  Échec de la mise à niveau des paquets"
    fi
else
    log_message "  Mise à niveau annulée à cause d'erreurs précédentes"
fi

# Étape 6: Déconnexion du WiFi
log_message "> Déconnexion du réseau WiFi..."
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
log_message "  Déconnecté du réseau WiFi"

# Étape 7: Affichage d'un art ASCII
if [ $update_status -eq 0 ] && [ $upgrade_status -eq 0 ]; then
    log_message "=== MISE À JOUR TERMINÉE AVEC SUCCÈS ==="
    
    cat << "EOF"
  __  __            _     _       _    
 |  \/  |          | |   (_)     | |   
 | \  / | __ ___  _| |    _ _ __ | | __
 | |\/| |/ _' \ \/ / |   | | '_ \| |/ /
 | |  | | (_| |>  <| |___| | | | |   < 
 |_|  |_|\__,_/_/\_\_____|_|_| |_|_|\_\
                                       
 Mise à jour terminée avec succès!
EOF
else
    log_message "=== MISE À JOUR TERMINÉE AVEC DES ERREURS ==="
    
    cat << "EOF"
  __  __            _     _       _    
 |  \/  |          | |   (_)     | |   
 | \  / | __ ___  _| |    _ _ __ | | __
 | |\/| |/ _' \ \/ / |   | | '_ \| |/ /
 | |  | | (_| |>  <| |___| | | | |   < 
 |_|  |_|\__,_/_/\_\_____|_|_| |_|_|\_\
                                       
 Mise à jour terminée avec des erreurs!
 Consultez les logs pour plus de détails.
EOF
fi

# Étape 8: Attente avant redémarrage
log_message "  Le système va redémarrer dans 15 secondes..."
sleep 15

# Étape 9: Redémarrage du système
log_message "=== REDÉMARRAGE DU SYSTÈME ==="
reboot