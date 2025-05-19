#!/bin/bash

#########################################################
#              CONFIGURATION PERSONNALISÉE              #
#########################################################

# Configuration du point d'accès
AP_SSID="MaxLink-NETWORK"       # Nom du réseau WiFi
AP_PASSWORD="ouinon"   			# Mot de passe du réseau WiFi (minimum 8 caractères)
AP_BAND="bg"                    # Bande WiFi: bg (2.4GHz) ou a (5GHz)

# Configuration du réseau
AP_IP="192.168.4.1"             # Adresse IP du Raspberry Pi
AP_NETMASK="24"                 # Masque de sous-réseau (24 = 255.255.255.0)
DHCP_START="192.168.4.10"       # Début de la plage DHCP
DHCP_END="192.168.4.50"         # Fin de la plage DHCP

# FIN DE LA CONFIGURATION PERSONNALISÉE
#########################################################

# Fonction pour afficher les messages avec couleurs
print_status() {
    echo -e "\e[1;34m[INFO]\e[0m $1"
}

print_success() {
    echo -e "\e[1;32m[SUCCÈS]\e[0m $1"
}

print_error() {
    echo -e "\e[1;31m[ERREUR]\e[0m $1"
}

# Vérification que le script est exécuté en tant que root
if [ "$(id -u)" != "0" ]; then
   print_error "Ce script doit être exécuté en tant que root ou avec sudo"
   exit 1
fi

# Afficher les informations de configuration
clear
echo "==============================================================="
echo "    INSTALLATION DU POINT D'ACCÈS WIFI PROJET MAXLINK"
echo "==============================================================="
echo ""
echo "- Point d'accès WiFi: $AP_SSID"
echo "- Adresse IP du serveur: $AP_IP/$AP_NETMASK"
echo "- Plage DHCP: $DHCP_START - $DHCP_END"
echo ""
echo "L'installation prendra quelques secondes..."
echo "==============================================================="
echo ""

# Demande de confirmation avant de continuer
read -p "Continuer l'installation? (o/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    print_status "Installation annulée."
    exit 0
fi

# Installer NetworkManager et ses dépendances
print_status "Installation de NetworkManager et des paquets nécessaires..."
apt update -y
apt install -y network-manager network-manager-gnome

# Arrêter dhcpcd pour éviter les conflits
print_status "Désactivation de dhcpcd pour éviter les conflits avec NetworkManager..."
systemctl stop dhcpcd
systemctl disable dhcpcd
systemctl mask dhcpcd

# Activer NetworkManager
print_status "Activation de NetworkManager..."
systemctl enable NetworkManager
systemctl start NetworkManager

# Attendre que NetworkManager soit complètement démarré
print_status "Attente du démarrage complet de NetworkManager..."
sleep 5

# Créer et configurer le point d'accès WiFi
print_status "Configuration du point d'accès WiFi avec NetworkManager..."

# Supprimer toute connexion hotspot existante
EXISTING_HOTSPOT=$(nmcli -g NAME connection show | grep "$AP_SSID" || true)
if [ -n "$EXISTING_HOTSPOT" ]; then
    print_status "Suppression de la connexion hotspot existante..."
    nmcli connection delete "$EXISTING_HOTSPOT"
fi

# Créer un nouveau point d'accès WiFi
print_status "Création du point d'accès '$AP_SSID'..."
nmcli connection add type wifi ifname wlan0 con-name "$AP_SSID" autoconnect yes ssid "$AP_SSID"

# Configurer les paramètres WiFi
print_status "Configuration des paramètres WiFi..."
nmcli connection modify "$AP_SSID" 802-11-wireless.mode ap 802-11-wireless.band "$AP_BAND"

# Configurer la sécurité WiFi
print_status "Configuration de la sécurité WiFi avec WPA2..."
nmcli connection modify "$AP_SSID" 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$AP_PASSWORD"

# Configurer l'adresse IP et le serveur DHCP
print_status "Configuration de l'adresse IP et du serveur DHCP..."
nmcli connection modify "$AP_SSID" ipv4.method shared ipv4.addresses "$AP_IP/$AP_NETMASK"

# Configuration avancée du serveur DHCP intégré
if [ -f /etc/NetworkManager/dnsmasq-shared.d/dhcp-range.conf ]; then
    mv /etc/NetworkManager/dnsmasq-shared.d/dhcp-range.conf /etc/NetworkManager/dnsmasq-shared.d/dhcp-range.conf.backup
fi

# Créer le répertoire de configuration si nécessaire
mkdir -p /etc/NetworkManager/dnsmasq-shared.d/

# Configurer la plage DHCP
print_status "Configuration de la plage DHCP personnalisée..."
cat > /etc/NetworkManager/dnsmasq-shared.d/dhcp-range.conf << EOL
dhcp-range=$DHCP_START,$DHCP_END,12h
EOL

# Créer le script de connexion temporaire à un réseau WiFi
print_status "Création des scripts de gestion..."
cat > /home/$(logname)/connect-wifi.sh << 'EOL'
#!/bin/bash
# Script pour se connecter temporairement à un réseau WiFi existant
# Usage: ./connect-wifi.sh "SSID" "Password"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <ssid> <password>"
  exit 1
fi

SSID="$1"
PASSWORD="$2"

echo "Configuration de la connexion WiFi pour '$SSID'..."

# Vérifier si la connexion existe déjà
CONNECTION_EXISTS=$(sudo nmcli -g NAME connection show | grep "$SSID" || true)

if [ -n "$CONNECTION_EXISTS" ]; then
    echo "Une connexion pour '$SSID' existe déjà, connexion en cours..."
    sudo nmcli connection up "$SSID"
else
    echo "Création d'une nouvelle connexion pour '$SSID'..."
    sudo nmcli device wifi connect "$SSID" password "$PASSWORD"
fi

# Vérifier la connexion
sleep 3
CONNECTION_ACTIVE=$(nmcli -g GENERAL.STATE device show wlan0 | grep 'connected' || true)
if [ -n "$CONNECTION_ACTIVE" ]; then
    IPADDR=$(ip addr show wlan0 | grep -o "inet [0-9.]*" | cut -d' ' -f2)
    echo "Connexion établie avec l'adresse IP: $IPADDR"
    echo "Le point d'accès MaxLink-AP est toujours accessible pour les autres appareils."
    echo "Pour revenir en mode point d'accès uniquement, utilisez: ./disconnect-wifi.sh"
else
    echo "Échec de la connexion. Vérifiez le SSID et le mot de passe."
fi
EOL

# Créer le script de retour au mode point d'accès
cat > /home/$(logname)/disconnect-wifi.sh << 'EOL'
#!/bin/bash
# Script pour revenir au mode point d'accès uniquement

echo "Déconnexion des réseaux WiFi clients..."

# Obtenir la liste des connexions actives (sauf le point d'accès)
AP_NAME=$(sudo nmcli -g NAME,TYPE connection show | grep ":wifi" | grep -v "ap" | cut -d':' -f1)

if [ -n "$AP_NAME" ]; then
    echo "Désactivation de la connexion '$AP_NAME'..."
    sudo nmcli connection down "$AP_NAME"
    echo "Déconnecté du réseau WiFi client."
else
    echo "Aucune connexion WiFi client active."
fi

# Vérifier que le point d'accès est actif
AP_HOTSPOT=$(sudo nmcli -g NAME,TYPE connection show | grep ":wifi" | grep ":ap" | cut -d':' -f1)
if [ -n "$AP_HOTSPOT" ]; then
    echo "Activation du point d'accès '$AP_HOTSPOT'..."
    sudo nmcli connection up "$AP_HOTSPOT"
    echo "Point d'accès activé."
else
    echo "ATTENTION: Aucun point d'accès configuré n'a été trouvé."
fi
EOL

# Créer le script d'état des connexions
cat > /home/$(logname)/network-status.sh << 'EOL'
#!/bin/bash
# Script pour vérifier l'état des connexions réseau

echo "===== État des connexions réseau ====="
nmcli connection show --active

echo ""
echo "===== État des interfaces réseau ====="
nmcli device status

echo ""
echo "===== Informations sur le point d'accès ====="
AP_NAME=$(sudo nmcli -g NAME,TYPE connection show | grep ":wifi" | grep ":ap" | cut -d':' -f1)
if [ -n "$AP_NAME" ]; then
    echo "Point d'accès configuré: $AP_NAME"
    # Vérifier si le point d'accès est actif
    AP_ACTIVE=$(nmcli -g NAME connection show --active | grep "$AP_NAME" || true)
    if [ -n "$AP_ACTIVE" ]; then
        echo "Statut: Actif"
        IP=$(ip addr show wlan0 | grep -o "inet [0-9.]*" | cut -d' ' -f2)
        echo "Adresse IP: $IP"
        
        # Afficher les clients connectés
        echo ""
        echo "Clients connectés:"
        CLIENTS=$(iw dev wlan0 station dump | grep Station | wc -l)
        echo "$CLIENTS client(s) connecté(s)"
        if [ "$CLIENTS" -gt 0 ]; then
            iw dev wlan0 station dump | grep -E "Station|signal|connected time"
        fi
    else
        echo "Statut: Inactif"
    fi
else
    echo "Aucun point d'accès configuré."
fi

echo ""
echo "===== Connexion WiFi client ====="
CLIENT_NAME=$(sudo nmcli -g NAME,TYPE connection show --active | grep ":wifi" | grep -v ":ap" | cut -d':' -f1)
if [ -n "$CLIENT_NAME" ]; then
    echo "Connecté au réseau WiFi: $CLIENT_NAME"
    nmcli connection show "$CLIENT_NAME" | grep -E "ipv4.addresses|GENERAL.DEVICES|802-11-wireless.ssid"
else
    echo "Aucune connexion WiFi client active."
fi
EOL

# Ajuster les permissions des scripts
chown $(logname):$(logname) /home/$(logname)/*.sh
chmod +x /home/$(logname)/*.sh

# Redémarrer NetworkManager pour appliquer les changements
print_status "Redémarrage de NetworkManager pour appliquer les changements..."
systemctl restart NetworkManager

# Attendre que NetworkManager soit complètement redémarré
sleep 5

# Activer le point d'accès
print_status "Activation du point d'accès..."
nmcli connection up "$AP_SSID" || print_error "Échec de l'activation du point d'accès. Vérifiez les logs avec 'journalctl -u NetworkManager'"

# Vérification de l'installation
print_success "Installation terminée avec succès!"
echo ""
echo "Configuration du point d'accès:"
echo "- SSID: $AP_SSID"
echo "- Mot de passe: $AP_PASSWORD"
echo "- Adresse IP du serveur: $AP_IP/$AP_NETMASK"
echo "- Plage DHCP: $DHCP_START - $DHCP_END"
echo ""
echo "Scripts disponibles dans votre répertoire personnel:"
echo "- connect-wifi.sh: Pour se connecter à un WiFi normal temporairement"
echo "- disconnect-wifi.sh: Pour revenir au mode point d'accès uniquement"
echo "- network-status.sh: Pour vérifier l'état des connexions"
echo ""
echo "Utilisation:"
echo "Pour vous connecter à un WiFi normal: ./connect-wifi.sh \"SSID\" \"MotDePasse\""
echo "Pour revenir au mode point d'accès: ./disconnect-wifi.sh"
echo "Pour vérifier l'état: ./network-status.sh"
echo ""
echo "Le point d'accès démarrera automatiquement au prochain redémarrage."
echo "Un redémarrage est recommandé pour finaliser l'installation."
echo "Voulez-vous redémarrer maintenant?"
read -p "(o/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Oo]$ ]]; then
    print_status "Le système va redémarrer dans 5 secondes..."
    sleep 5
    reboot
else
    print_status "N'oubliez pas de redémarrer plus tard avec 'sudo reboot'"
fi