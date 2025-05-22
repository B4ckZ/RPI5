#!/bin/bash

# Détecter le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vérifier si l'utilisateur a des privilèges sudo
if [ "$EUID" -ne 0 ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "  MaxLink™ Admin Panel V2.0 - Configuration"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "❌ Ce script doit être exécuté avec des privilèges sudo."
    echo ""
    echo "Usage correct:"
    echo "  sudo bash $0"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    exit 1
fi

# Header d'accueil
clear
echo "════════════════════════════════════════════════════════════════"
echo "  MaxLink™ Admin Panel V2.0 - Initialisation"
echo "  © 2025 WERIT. Tous droits réservés."
echo "════════════════════════════════════════════════════════════════"
echo ""

# Créer le répertoire de logs avec permissions appropriées
echo "📁 Création des répertoires nécessaires..."
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/logs/archived"
chmod 755 "$SCRIPT_DIR/logs"
chmod 755 "$SCRIPT_DIR/logs/archived"

# Créer les répertoires de scripts s'ils n'existent pas
mkdir -p "$SCRIPT_DIR/scripts/install"
mkdir -p "$SCRIPT_DIR/scripts/start"
mkdir -p "$SCRIPT_DIR/scripts/test"
mkdir -p "$SCRIPT_DIR/scripts/uninstall"
mkdir -p "$SCRIPT_DIR/scripts/common"

echo "✅ Structure des dossiers créée"

# Rendre les scripts exécutables
echo "🔧 Configuration des permissions..."
find "$SCRIPT_DIR/scripts" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || echo "Aucun script trouvé (normal lors de la première installation)"

echo "✅ Permissions configurées"

# Vérifier si Python et tkinter sont installés
echo "🐍 Vérification de Python et des dépendances..."

if ! command -v python3 &> /dev/null; then
    echo "⚠️  Python3 n'est pas installé. Installation en cours..."
    apt-get update > /dev/null 2>&1
    apt-get install -y python3 python3-pip > /dev/null 2>&1
    echo "✅ Python3 installé"
else
    echo "✅ Python3 détecté"
fi

if ! python3 -c "import tkinter" &> /dev/null; then
    echo "⚠️  Tkinter n'est pas installé. Installation en cours..."
    apt-get install -y python3-tk > /dev/null 2>&1
    echo "✅ Tkinter installé"
else
    echo "✅ Tkinter disponible"
fi

# Vérifier que les outils réseau de base sont présents
echo "🌐 Vérification des outils réseau..."

tools_needed=("nmcli" "iw" "ip" "ping")
missing_tools=()

for tool in "${tools_needed[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "⚠️  Installation des outils réseau manquants: ${missing_tools[*]}"
    apt-get update > /dev/null 2>&1
    apt-get install -y wireless-tools net-tools iputils-ping > /dev/null 2>&1
    echo "✅ Outils réseau installés"
else
    echo "✅ Tous les outils réseau sont disponibles"
fi

# Informations système
echo ""
echo "📊 Informations système:"
echo "  • OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  • Kernel: $(uname -r)"
echo "  • Architecture: $(uname -m)"
echo "  • Python: $(python3 --version)"

# Vérifier l'interface WiFi
if ip link show wlan0 > /dev/null 2>&1; then
    echo "  • Interface WiFi: wlan0 ✅"
else
    echo "  • Interface WiFi: ⚠️  wlan0 non détectée"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  🚀 Lancement de l'interface MaxLink Admin Panel V2.0"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "💡 Informations importantes:"
echo "  • Tous les scripts génèrent des logs détaillés dans logs/"
echo "  • Les snapshots système sont automatiques"
echo "  • Chaque opération redémarre le système pour finaliser"
echo "  • Version simplifiée optimisée pour NetworkManager"
echo ""

# Petit délai pour laisser lire les informations
sleep 3

# Lancer l'interface graphique
echo "🎯 Démarrage de l'interface..."
sleep 1

# S'assurer qu'on a les bonnes permissions pour l'affichage
if [ -n "$SUDO_USER" ]; then
    # Permettre à l'utilisateur sudo d'afficher sur X11
    export DISPLAY="${DISPLAY:-:0}"
    xhost +local: > /dev/null 2>&1 || true
    
    # Lancer l'interface avec l'utilisateur original
    sudo -u "$SUDO_USER" DISPLAY="$DISPLAY" python3 "$SCRIPT_DIR/interface.py"
else
    # Lancer directement
    python3 "$SCRIPT_DIR/interface.py"
fi

# Message de fin
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  MaxLink™ Admin Panel V2.0 - Session terminée"
echo "════════════════════════════════════════════════════════════════"