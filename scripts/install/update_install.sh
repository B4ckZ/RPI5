#!/bin/bash

# Source du système de logging
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/common/logging.sh"

# Configuration
WIFI_SSID="Max"
WIFI_PASSWORD="1234567890"
BG_IMAGE_SOURCE="$BASE_DIR/assets/bg.jpg"
BG_IMAGE_DEST="/usr/share/backgrounds/maxlink"

# Initialisation du logging
init_logging "Mise à jour système et personnalisation Raspberry Pi"

# Fonction pour configurer le ventilateur
configure_fan() {
    local mode="$1"
    local temp1="$2"
    local temp2="$3"
    
    CONFIG_FILE="/boot/firmware/config.txt"
    CONFIG_BACKUP="${CONFIG_FILE}.backup"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Fichier config.txt introuvable"
        show_result "ERREUR: Fichier config.txt introuvable"
        return 1
    fi
    
    if [ ! -f "$CONFIG_BACKUP" ]; then
        cp "$CONFIG_FILE" "$CONFIG_BACKUP"
        log_info "Sauvegarde de config.txt créée"
    fi
    
    if grep -q "dtparam=fan_temp" "$CONFIG_FILE"; then
        log_info "Mise à jour des paramètres de refroidissement existants"
        sed -i 's/dtparam=fan_temp0=.*/dtparam=fan_temp0=0/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp1=.*/dtparam=fan_temp1='$temp1'/g' "$CONFIG_FILE"
        sed -i 's/dtparam=fan_temp2=.*/dtparam=fan_temp2='$temp2'/g' "$CONFIG_FILE"
    else
        log_info "Ajout des nouveaux paramètres de refroidissement"
        echo "" >> "$CONFIG_FILE"
        echo "# Configuration de refroidissement" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp0=0" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp1=$temp1" >> "$CONFIG_FILE"
        echo "dtparam=fan_temp2=$temp2" >> "$CONFIG_FILE"
    fi
    
    if grep -q "dtparam=fan_temp0=0" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp1=$temp1" "$CONFIG_FILE" && \
       grep -q "dtparam=fan_temp2=$temp2" "$CONFIG_FILE"; then
        show_result "Refroidissement réglé sur mode $mode"
        log_info "Configuration de refroidissement réussie"
        return 0
    else
        log_error "Configuration du refroidissement échouée"
        show_result "ERREUR: Configuration du refroidissement échouée"
        return 1
    fi
}

# Fonction pour personnaliser l'interface
customize_desktop() {
    if [ ! -d "/etc/xdg/lxsession" ]; then
        log_warn "Environnement graphique non détecté"
        show_result "AVERTISSEMENT: Environnement graphique non détecté, personnalisation ignorée"
        return 1
    fi
    
    # Utilisateur principal configuré pour "max"
    local current_user="max"
    local user_home="/home/$current_user"
    
    # Vérifier si le répertoire de l'utilisateur max existe
    if [ ! -d "$user_home" ]; then
        # Essayer de détecter automatiquement l'utilisateur principal
        current_user=$(ls -la /home | grep -v "^d.* \.$" | grep "^d" | head -1 | awk '{print $3}')
        user_home="/home/$current_user"
        
        if [ ! -d "$user_home" ] || [ "$current_user" = "root" ]; then
            current_user=$(who am i | awk '{print $1}')
            user_home="/home/$current_user"
            
            if [ ! -d "$user_home" ] && [ -n "$SUDO_USER" ]; then
                current_user="$SUDO_USER"
                user_home="/home/$current_user"
            fi
        fi
    fi
    
    if [ ! -d "$user_home" ]; then
        log_error "Impossible de trouver un répertoire utilisateur valide"
        show_result "ERREUR: Aucun utilisateur trouvé pour la personnalisation"
        return 1
    fi
    
    log_info "Personnalisation de l'interface pour l'utilisateur: $current_user"
    
    echo "Installation du fond d'écran personnalisé :"
    if [ -f "$BG_IMAGE_SOURCE" ]; then
        mkdir -p "$BG_IMAGE_DEST"
        cp -f "$BG_IMAGE_SOURCE" "$BG_IMAGE_DEST/bg.jpg"
        chmod 644 "$BG_IMAGE_DEST/bg.jpg"
        show_result "Fond d'écran installé avec succès"
        log_info "Fond d'écran installé: $BG_IMAGE_DEST/bg.jpg"
    else
        log_warn "Image de fond d'écran non trouvée: $BG_IMAGE_SOURCE"
        show_result "AVERTISSEMENT: Image de fond d'écran non trouvée"
    fi
    
    echo "Configuration de l'interface utilisateur :"
    mkdir -p "$user_home/.config/pcmanfm/LXDE-pi"
    
    if [ -f "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" ]; then
        sed -i "s|wallpaper=.*|wallpaper=$BG_IMAGE_DEST/bg.jpg|g" "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf"
        sed -i "s|show_trash=.*|show_trash=0|g" "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf"
    else
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
    
    chown -R $current_user:$current_user "$user_home/.config"
    
    if [ -d "/etc/xdg" ]; then
        mkdir -p "/etc/xdg/pcmanfm/LXDE-pi"
        cp "$user_home/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" "/etc/xdg/pcmanfm/LXDE-pi/"
    fi
    
    show_result "Personnalisation de l'interface réussie pour $current_user"
    log_info "Interface personnalisée pour $current_user"
}

# DÉMARRAGE
section_header "DÉMARRAGE DE LA MISE À JOUR DU RASPBERRY PI"

log_info "Configuration du système de refroidissement"
configure_fan "PRODUCTION" "60" "60"
sleep 2

# CONNECTIVITÉ RÉSEAU
section_header "CONNECTIVITÉ RÉSEAU"

log_info "Recherche et connexion au réseau WiFi $WIFI_SSID"
if run_command "nmcli device wifi connect '$WIFI_SSID' password '$WIFI_PASSWORD'" "Connexion au WiFi"; then
    show_result "Connecté au réseau $WIFI_SSID"
else
    echo "Nouvelle tentative de connexion..."
    if run_command "nmcli device wifi connect '$WIFI_SSID' password '$WIFI_PASSWORD' name '$WIFI_SSID'" "Nouvelle tentative de connexion"; then
        show_result "Connecté au réseau $WIFI_SSID"
    else
        log_error "Impossible de se connecter au réseau WiFi"
        show_result "ERREUR: Impossible de se connecter au réseau WiFi"
        exit 1
    fi
fi

log_info "Test de la connectivité Internet"
sleep 5
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    ping_result=$(ping -c 1 8.8.8.8 2>/dev/null | grep "time=" | cut -d "=" -f 4)
    show_result "Connexion stable avec $ping_result de ping"
    log_info "Connectivité Internet confirmée: $ping_result"
else
    echo "Test alternatif de connectivité..."
    if ping -c 4 google.com > /dev/null 2>&1; then
        show_result "Connexion rétablie"
        log_info "Connectivité Internet rétablie"
    else
        log_error "Pas de connexion Internet"
        show_result "ERREUR: Pas de connexion Internet"
        run_command "nmcli connection delete '$WIFI_SSID'" "Nettoyage connexion"
        exit 1
    fi
fi

# VÉRIFICATION SYSTÈME
section_header "VÉRIFICATION SYSTÈME"

log_info "Vérification de l'horloge système"
current_date=$(date +%s)
online_date=$(curl -s --head http://google.com 2>/dev/null | grep -i "^date:" | sed 's/^[Dd]ate: //g' | date -f - +%s 2>/dev/null || echo 0)

if [ "$online_date" != "0" ]; then
    date_diff=$((current_date - online_date))
    date_diff=${date_diff#-}
    
    if [ $date_diff -gt 60 ]; then
        echo "Horloge désynchronisée (${date_diff}s), synchronisation en cours..."
        log_warn "Horloge désynchronisée de ${date_diff}s"
        
        if ! command -v ntpdate > /dev/null; then
            log_info "Installation de ntpdate"
            run_command "apt-get update" "Mise à jour pour ntpdate" false
            run_command "apt-get install -y ntpdate" "Installation ntpdate" false
        fi
        
        if run_command "ntpdate pool.ntp.org" "Synchronisation horloge" false; then
            show_result "Horloge synchronisée"
            log_info "Horloge synchronisée avec pool.ntp.org"
        else
            show_result "ERREUR: Échec de la synchronisation d'horloge"
            log_error "Échec de la synchronisation d'horloge"
        fi
    else
        show_result "Horloge interne synchronisée"
        log_info "Horloge déjà synchronisée"
    fi
else
    show_result "AVERTISSEMENT: Impossible de vérifier l'heure en ligne"
    log_warn "Impossible de vérifier l'heure en ligne"
fi

# MISE À JOUR DU SYSTÈME
section_header "MISE À JOUR DU SYSTÈME"

log_info "Téléchargement des informations sur les dépôts"
if run_command "apt-get update -y" "Mise à jour des dépôts"; then
    show_result "Informations sur les dépôts téléchargées avec succès"
else
    log_error "Échec du téléchargement des informations sur les dépôts"
    show_result "ERREUR: Mise à jour des dépôts échouée"
fi

log_info "Installation des mises à jour système"
echo "Cette opération peut prendre plusieurs minutes..."
if run_command "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Installation des mises à jour système"; then
    show_result "Installation des mises à jour système terminée"
    log_info "Mises à jour système installées avec succès"
    
    echo "Nettoyage du système :"
    run_command "apt-get autoremove -y" "Suppression des paquets orphelins" false
    run_command "apt-get autoclean -y" "Nettoyage du cache" false
    show_result "Nettoyage terminé"
    log_info "Nettoyage du système terminé"
else
    log_error "Échec de l'installation des mises à jour"
    show_result "ERREUR: Installation des mises à jour échouée"
fi

# PERSONNALISATION DE L'INTERFACE
section_header "PERSONNALISATION DE L'INTERFACE"
customize_desktop

# FINALISATION
section_header "FINALISATION"

log_info "Déconnexion du réseau WiFi"
run_command "nmcli connection delete '$WIFI_SSID'" "Déconnexion du WiFi" false
show_result "Déconnecté du réseau WiFi"

section_header "MISE À JOUR TERMINÉE AVEC SUCCÈS"

log_info "Mise à jour du système terminée avec succès"

echo "Opérations effectuées :"
echo "• Configuration du système de refroidissement"
echo "• Mise à jour des paquets système"
echo "• Personnalisation de l'interface utilisateur"
echo "• Nettoyage du système"

# Art ASCII simple
cat << "EOF"
  _    _ _____  _____       _______ ______ 
 | |  | |  __ \|  __ \   /\|__   __|  ____|
 | |  | | |__) | |  | | /  \  | |  | |__   
 | |  | |  ___/| |  | |/ /\ \ | |  |  __|  
 | |__| | |    | |__| / ____ \| |  | |____ 
  \____/|_|    |_____/_/    \_\_|  |______|

EOF

show_result "Système mis à jour avec succès !"

log_info "Redémarrage programmé dans 10 secondes"
echo "Le système va redémarrer dans 10 secondes pour finaliser..."
for i in {10..1}; do
    echo -ne "\rRedémarrage dans $i secondes..."
    sleep 1
done
echo ""

log_info "Redémarrage du système"
reboot