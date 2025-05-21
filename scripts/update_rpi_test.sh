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

# Fonction pour logger les messages (sans formatage ANSI dans la console)
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Écrire dans le fichier de log avec timestamp
    echo "[$timestamp] $message" >> "$LOG_FILE"
    
    # Afficher sur la console sans formatage ni timestamp
    echo "$message"
    
    # Envoyer au journal système
    logger -t "update_rpi" "$message"
}

# Fonction pour exécuter une commande et afficher son résultat
run_command() {
    local cmd="$1"
    local msg="$2"
    local logfile="$3"
    
    log_message "► $msg..."
    
    # Exécuter la commande et capturer sa sortie dans le fichier de log
    eval "$cmd >> \"$logfile\" 2>&1"
    local status=$?
    
    if [ $status -eq 0 ]; then
        log_message "✓ $msg terminé avec succès"
        return 0
    else
        log_message "✗ ERREUR: $msg a échoué (code: $status)"
        return $status
    fi
}

# Vider le fichier de log précédent
echo "" > "$LOG_FILE"

log_message "=== DÉMARRAGE DE LA MISE À JOUR DU RASPBERRY PI ==="

# Nouvelle étape: Configuration du ventilateur du Raspberry Pi
log_message "► Configuration du ventilateur..."

# Chemin du fichier de configuration
CONFIG_FILE="/boot/firmware/config.txt"
CONFIG_BACKUP="${CONFIG_FILE}.backup"

# Vérifier si le fichier config.txt existe
if [ -f "$CONFIG_FILE" ]; then
    # Créer une sauvegarde du fichier original
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    
    # Vérifier si les paramètres du ventilateur existent déjà
    if grep -q "dtparam=fan_temp" "$CONFIG_FILE"; then
        log_message "  Mise à jour des paramètres du ventilateur..."
        
        # Utiliser sed pour remplacer les lignes existantes
        sed -i 's/dtparam=fan_temp0=.*/dtparam=fan_temp0=0/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp1=.*/dtparam=fan_temp1=60/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp2=.*/dtparam=fan_temp2=60/g' "$CONFIG_FILE"
    else
        log_message "  Ajout des nouveaux paramètres du ventilateur..."
        
        # Ajouter les paramètres à la fin du fichier
        echo "" >> "$CONFIG_FILE"
        echo "# Configuration du ventilateur" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp0=0" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp1=60" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp2=60" >> "$CONFIG_FILE"
    fi
    
    # Vérifier si l'opération a réussi
    if grep -q "dtparam=fan_temp0=0" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp1=60" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp2=60" "$CONFIG_FILE"; then
        log_message "✓ Configuration du ventilateur réussie"
        log_message "  - Température 0: 0°C (Vitesse minimale)"
        log_message "  - Température 1: 60°C (Vitesse intermédiaire)"
        log_message "  - Température 2: 60°C (Vitesse maximale)"
    else
        log_message "✗ Échec de la configuration du ventilateur"
    fi
else
    log_message "✗ Fichier config.txt introuvable"
fi

# Étape 1: Connexion au WiFi
log_message "► Connexion au réseau WiFi..."
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD"

if [ $? -ne 0 ]; then
    # Vérifier si on est déjà connecté à ce réseau
    if nmcli -t -f ACTIVE,SSID device wifi | grep "^yes:$WIFI_SSID$"; then
        log_message "✓ Déjà connecté au réseau $WIFI_SSID"
    else
        # Si on ne peut pas se connecter, on tente de créer une nouvelle connexion
        log_message "  Tentative de création d'une nouvelle connexion..."
        nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "$WIFI_SSID"
        
        if [ $? -ne 0 ]; then
            log_message "✗ Impossible de se connecter au réseau. Arrêt."
            exit 1
        fi
    fi
else
    log_message "✓ Connecté au réseau $WIFI_SSID"
fi

# Attente pour stabilisation de la connexion
log_message "  Attente de stabilisation de la connexion (15s)..."
sleep 15
log_message "✓ Connexion stabilisée"

# Étape 2: Vérification de la connectivité Internet
log_message "► Vérification de la connectivité Internet..."

if ping -c 4 8.8.8.8 > /dev/null; then
    log_message "✓ Connectivité Internet OK"
else
    log_message "⚠ Connectivité faible, test alternatif..."
    
    if ping -c 4 google.com > /dev/null; then
        log_message "✓ Connexion rétablie"
    else
        log_message "✗ Pas de connexion Internet. Arrêt."
        nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
        exit 1
    fi
fi

# Étape 3: Vérification de l'horloge système
log_message "► Vérification de l'horloge système..."

current_date=$(date +%s)
online_date=$(curl -s --head http://google.com | grep -i "^date:" | sed 's/^[Dd]ate: //g' | date -f - +%s || echo 0)

# Si la date en ligne est valide (différente de 0)
if [ "$online_date" != "0" ]; then
    # Calculer la différence en secondes
    date_diff=$((current_date - online_date))
    date_diff=${date_diff#-} # Valeur absolue
    
    if [ $date_diff -gt 60 ]; then
        log_message "⚠ Horloge désynchronisée (${date_diff}s)"
        log_message "  Synchronisation en cours..."
        
        # Installer ntpdate si nécessaire
        if ! command -v ntpdate > /dev/null; then
            apt-get update > /dev/null
            apt-get install -y ntpdate > /dev/null
        fi
        
        # Synchroniser l'horloge
        if ntpdate pool.ntp.org > /dev/null; then
            log_message "✓ Horloge synchronisée"
        else
            log_message "⚠ Échec de la synchronisation"
        fi
    else
        log_message "✓ Horloge système OK"
    fi
else
    log_message "⚠ Impossible de vérifier l'heure en ligne"
fi

# Étape 4: Mise à jour du système
log_message "=== MISE À JOUR DU SYSTÈME ==="

# Créer des fichiers de log temporaires pour chaque commande
UPDATE_LOG="$LOG_DIR/apt_update.log"
UPGRADE_LOG="$LOG_DIR/apt_upgrade.log"
AUTOREMOVE_LOG="$LOG_DIR/apt_autoremove.log"
AUTOCLEAN_LOG="$LOG_DIR/apt_autoclean.log"

# Exécuter apt update
log_message "► Mise à jour des dépôts (apt update)..."
apt-get update -y >> "$UPDATE_LOG" 2>&1
update_status=$?
if [ $update_status -eq 0 ]; then
    log_message "✓ Mise à jour des dépôts terminée"
else
    log_message "✗ Échec de la mise à jour des dépôts"
fi

if [ $update_status -eq 0 ]; then
    # Exécuter apt upgrade
    log_message "► Mise à niveau des paquets (apt upgrade)..."
    log_message "  Cette opération peut prendre plusieurs minutes..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$UPGRADE_LOG" 2>&1
    upgrade_status=$?
    
    if [ $upgrade_status -eq 0 ]; then
        log_message "✓ Mise à niveau des paquets terminée"
        
        # Nettoyage du système
        log_message "► Nettoyage du système..."
        apt-get autoremove -y >> "$AUTOREMOVE_LOG" 2>&1
        log_message "✓ Suppression des paquets obsolètes terminée"
        
        apt-get autoclean -y >> "$AUTOCLEAN_LOG" 2>&1
        log_message "✓ Nettoyage du cache APT terminé"
    else
        log_message "✗ Échec de la mise à niveau des paquets"
    fi
else
    log_message "✗ Mise à niveau annulée à cause d'erreurs précédentes"
fi

# Étape 6: Déconnexion du WiFi
log_message "► Déconnexion du réseau WiFi..."
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1
log_message "✓ Déconnecté du réseau WiFi"

# Étape 7: Affichage d'un art ASCII
if [ $update_status -eq 0 ] && [ $upgrade_status -eq 0 ]; then
    log_message "✓ MISE À JOUR TERMINÉE AVEC SUCCÈS !"
    
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
    log_message "✗ MISE À JOUR TERMINÉE AVEC DES ERREURS !"
    
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
log_message "► Redémarrage du système..."
log_message "  Le système va redémarrer dans 5 secondes..."
sleep 5

# Étape 9: Redémarrage du système
log_message "=== REDÉMARRAGE DU SYSTÈME ==="
reboot