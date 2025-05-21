#!/bin/bash

# Détecter le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vérifier si l'utilisateur a des privilèges sudo
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec des privilèges sudo."
    echo "Veuillez utiliser: sudo bash $0"
    exit 1
fi

# Créer le répertoire de logs
mkdir -p "$SCRIPT_DIR/logs"
chmod 777 "$SCRIPT_DIR/logs"

# Vérifier si Python et tkinter sont installés
if ! command -v python3 &> /dev/null; then
    echo "Python3 n'est pas installé. Installation en cours..."
    apt-get update
    apt-get install -y python3 python3-pip
fi

if ! python3 -c "import tkinter" &> /dev/null; then
    echo "Tkinter n'est pas installé. Installation en cours..."
    apt-get install -y python3-tk
fi

# Rendre les scripts exécutables
chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || echo "Aucun script trouvé ou permission refusée"

# Lancer l'interface graphique
echo "Démarrage de l'interface MaxLink..."
python3 "$SCRIPT_DIR/interface.py"