#!/bin/bash

# ===============================================================================
# SYSTÈME DE LOGGING AVANCÉ MAXLINK
# ===============================================================================
# Ce fichier doit être sourcé au début de chaque script :
# source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/common/logging.sh"
# ===============================================================================

# Détection automatique des chemins
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
fi
if [ -z "$BASE_DIR" ]; then
    BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi

# Configuration globale des logs
LOG_DIR="$BASE_DIR/logs"
SYSTEM_LOG="$LOG_DIR/system.log"
ERROR_LOG="$LOG_DIR/errors.log"
DEBUG_LOG="$LOG_DIR/debug.log"

# Nom du script appelant (sans extension)
SCRIPT_NAME=$(basename "${BASH_SOURCE[1]}" .sh)
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"

# Création des répertoires de logs
mkdir -p "$LOG_DIR"
mkdir -p "$LOG_DIR/archived"

# Niveaux de log
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
    ["CRITICAL"]=4
)

# Configuration par défaut
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_TO_CONSOLE=${LOG_TO_CONSOLE:-true}
LOG_TO_FILE=${LOG_TO_FILE:-true}
LOG_TO_SYSLOG=${LOG_TO_SYSLOG:-true}

# Couleurs pour l'affichage console
declare -A COLORS=(
    ["DEBUG"]="\033[0;36m"      # Cyan
    ["INFO"]="\033[0;32m"       # Vert
    ["WARN"]="\033[0;33m"       # Jaune
    ["ERROR"]="\033[0;31m"      # Rouge
    ["CRITICAL"]="\033[1;31m"   # Rouge gras
    ["RESET"]="\033[0m"         # Reset
    ["BOLD"]="\033[1m"          # Gras
)

# ===============================================================================
# FONCTIONS DE LOGGING PRINCIPALES
# ===============================================================================

# Fonction de logging universelle
log() {
    local level="$1"
    local message="$2"
    local show_console="${3:-$LOG_TO_CONSOLE}"
    
    # Vérifier le niveau de log
    if [ ${LOG_LEVELS[$level]} -lt ${LOG_LEVELS[$LOG_LEVEL]} ]; then
        return 0
    fi
    
    # Timestamp précis
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local log_entry="[$timestamp] [$level] [$SCRIPT_NAME] $message"
    
    # Log vers console (SANS couleurs pour éviter les bugs d'affichage)
    if [ "$show_console" = true ]; then
        printf "[%s] %s\n" "$level" "$message"
    fi
    
    # Log vers fichier du script
    if [ "$LOG_TO_FILE" = true ]; then
        echo "$log_entry" >> "$SCRIPT_LOG"
    fi
    
    # Log vers fichier système global
    echo "$log_entry" >> "$SYSTEM_LOG"
    
    # Log vers fichier d'erreurs (si ERROR ou CRITICAL)
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" ]]; then
        echo "$log_entry" >> "$ERROR_LOG"
    fi
    
    # Log vers syslog
    if [ "$LOG_TO_SYSLOG" = true ]; then
        case $level in
            "DEBUG") logger -t "maxlink-$SCRIPT_NAME" -p daemon.debug "$message" ;;
            "INFO") logger -t "maxlink-$SCRIPT_NAME" -p daemon.info "$message" ;;
            "WARN") logger -t "maxlink-$SCRIPT_NAME" -p daemon.warning "$message" ;;
            "ERROR") logger -t "maxlink-$SCRIPT_NAME" -p daemon.error "$message" ;;
            "CRITICAL") logger -t "maxlink-$SCRIPT_NAME" -p daemon.crit "$message" ;;
        esac
    fi
}

# Fonctions de logging spécialisées
log_debug() { log "DEBUG" "$1" "${2:-false}"; }
log_info() { log "INFO" "$1" "${2:-true}"; }
log_warn() { log "WARN" "$1" "${2:-true}"; }
log_error() { log "ERROR" "$1" "${2:-true}"; }
log_critical() { log "CRITICAL" "$1" "${2:-true}"; }

# ===============================================================================
# FONCTIONS D'AFFICHAGE AMÉLIORÉES
# ===============================================================================

# Section header avec logging
section_header() {
    local title="$1"
    local separator=$(printf '=%.0s' {1..80})
    
    echo ""
    printf "%s\n" "$separator"
    printf "# %s\n" "$title"
    printf "%s\n" "$separator"
    echo ""
    
    log_info "=== SECTION: $title ==="
    sleep 1
}

# Résultat avec logging automatique
show_result() {
    local message="$1"
    local level="${2:-INFO}"
    
    printf "↦ %s\n" "$message"
    echo ""
    
    # Déterminer le niveau de log basé sur le contenu
    if [[ "$message" == *"ERREUR"* || "$message" == *"ÉCHEC"* ]]; then
        log_error "$message"
    elif [[ "$message" == *"AVERTISSEMENT"* || "$message" == *"⚠"* ]]; then
        log_warn "$message"
    else
        log_info "$message"
    fi
    
    sleep 0.5
}

# ===============================================================================
# FONCTIONS DE DEBUG ET DIAGNOSTIC
# ===============================================================================

# Capture de l'état système
capture_system_state() {
    local state_file="$LOG_DIR/system_state_$(date +%Y%m%d_%H%M%S).log"
    
    log_debug "Capture de l'état système dans $state_file"
    
    {
        echo "=== ÉTAT SYSTÈME MAXLINK ==="
        echo "Date: $(date)"
        echo "Script: $SCRIPT_NAME"
        echo "Utilisateur: $(whoami)"
        echo "PWD: $(pwd)"
        echo ""
        
        echo "=== SERVICES RÉSEAU ==="
        systemctl status dhcpcd NetworkManager wpa_supplicant 2>/dev/null || true
        echo ""
        
        echo "=== INTERFACES RÉSEAU ==="
        ip addr show
        echo ""
        
        echo "=== CONNEXIONS NETWORKMANAGER ==="
        nmcli connection show 2>/dev/null || echo "NetworkManager non disponible"
        echo ""
        
        echo "=== CONNEXIONS ACTIVES ==="
        nmcli connection show --active 2>/dev/null || echo "NetworkManager non disponible"
        echo ""
        
        echo "=== RÉSEAUX WIFI ==="
        nmcli device wifi list 2>/dev/null || iwlist wlan0 scan 2>/dev/null | grep ESSID || echo "Scan WiFi impossible"
        echo ""
        
        echo "=== PROCESSUS RÉSEAU ==="
        ps aux | grep -E "(dhcpcd|NetworkManager|wpa_supplicant)" | grep -v grep
        echo ""
        
        echo "=== UTILISATION MÉMOIRE ==="
        free -h
        echo ""
        
        echo "=== UTILISATION DISQUE ==="
        df -h
        echo ""
        
    } > "$state_file"
    
    log_info "État système capturé: $state_file"
}

# Commande avec logging de sortie
run_command() {
    local cmd="$1"
    local description="$2"
    local log_output="${3:-true}"
    
    log_debug "Exécution: $cmd"
    
    if [ -n "$description" ]; then
        log_info "$description"
    fi
    
    # Fichier temporaire pour capturer la sortie
    local temp_output=$(mktemp)
    local temp_error=$(mktemp)
    
    # Exécuter la commande
    if eval "$cmd" > "$temp_output" 2> "$temp_error"; then
        local exit_code=0
        log_debug "Commande réussie: $cmd"
    else
        local exit_code=$?
        log_error "Commande échouée (code $exit_code): $cmd"
    fi
    
    # Logger la sortie si demandé
    if [ "$log_output" = true ] && [ -s "$temp_output" ]; then
        log_debug "Sortie standard: $(cat "$temp_output")"
    fi
    
    if [ -s "$temp_error" ]; then
        log_error "Sortie erreur: $(cat "$temp_error")"
    fi
    
    # Nettoyer
    rm -f "$temp_output" "$temp_error"
    
    return $exit_code
}

# ===============================================================================
# FONCTIONS D'INITIALISATION ET NETTOYAGE
# ===============================================================================

# Initialisation du logging pour un script
init_logging() {
    local script_description="$1"
    
    # Rotation des logs si nécessaire
    rotate_logs_if_needed
    
    # Header de début de script
    {
        echo ""
        echo "$(printf '=%.0s' {1..80})"
        echo "DÉMARRAGE: $SCRIPT_NAME"
        if [ -n "$script_description" ]; then
            echo "Description: $script_description"
        fi
        echo "Date: $(date)"
        echo "Utilisateur: $(whoami)"
        echo "PID: $$"
        echo "$(printf '=%.0s' {1..80})"
        echo ""
    } >> "$SCRIPT_LOG"
    
    log_info "Script $SCRIPT_NAME démarré" false
    
    # Capturer l'état initial
    capture_system_state
}

# Finalisation du logging
finalize_logging() {
    local exit_code="${1:-0}"
    
    log_info "Script $SCRIPT_NAME terminé avec le code $exit_code" false
    
    # Footer de fin de script
    {
        echo ""
        echo "$(printf '=%.0s' {1..80})"
        echo "FIN: $SCRIPT_NAME"
        echo "Code de sortie: $exit_code"
        echo "Date: $(date)"
        echo "$(printf '=%.0s' {1..80})"
        echo ""
    } >> "$SCRIPT_LOG"
    
    # Capturer l'état final si erreur
    if [ "$exit_code" -ne 0 ]; then
        capture_system_state
    fi
}

# Rotation des logs
rotate_logs_if_needed() {
    local max_size=$((10 * 1024 * 1024))  # 10MB
    
    for log_file in "$SYSTEM_LOG" "$ERROR_LOG" "$SCRIPT_LOG"; do
        if [ -f "$log_file" ] && [ $(stat -c%s "$log_file" 2>/dev/null || echo 0) -gt $max_size ]; then
            local archive_name="${log_file##*/}.$(date +%Y%m%d_%H%M%S)"
            mv "$log_file" "$LOG_DIR/archived/$archive_name"
            log_info "Log rotaté: $archive_name"
        fi
    done
}

# ===============================================================================
# INITIALISATION AUTOMATIQUE
# ===============================================================================

# Trap pour capturer la fin du script
trap 'finalize_logging $?' EXIT

# Exporter les fonctions pour utilisation dans les sous-scripts
export -f log log_debug log_info log_warn log_error log_critical
export -f section_header show_result capture_system_state run_command
export -f init_logging finalize_logging

# Variables d'environnement pour les scripts
export LOG_DIR SCRIPT_LOG SYSTEM_LOG ERROR_LOG DEBUG_LOG
export SCRIPT_NAME BASE_DIR