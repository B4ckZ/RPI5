import tkinter as tk
from tkinter import scrolledtext, messagebox
import subprocess
import os
import threading
from datetime import datetime

# Couleurs du thème Nord - Interface principale
COLORS = {
    "nord0": "#2E3440",  # Fond sombre
    "nord1": "#3B4252",  # Fond moins sombre
    "nord3": "#4C566A",  # Bordure sélection
    "nord4": "#D8DEE9",  # Texte tertiaire
    "nord6": "#ECEFF4",  # Texte
    "nord8": "#88C0D0",  # Accent primaire (bleu clair)
    "nord10": "#5E81AC", # Bouton Installer
    "nord11": "#BF616A", # Rouge / Erreur / Désinstaller
    "nord14": "#A3BE8C", # Vert / Démarrer
    "nord15": "#B48EAD", # Violet / Tester
}

class MaxLinkApp:
    def __init__(self, root):
        self.root = root
        
        # Titre standard dans la barre de titre de la fenêtre
        self.root.title("MaxLink™ Admin Panel V2.0 - © 2025 WERIT. Tous droits réservés. - Usage non autorisé strictement interdit.")
        self.root.geometry("1200x700")
        self.root.configure(bg=COLORS["nord0"])
        
        # Chemins et initialisation
        self.base_path = os.path.dirname(os.path.abspath(__file__))
        self.services = [
            {"id": "update", "name": "Update RPI", "status": "active"},
            {"id": "ap", "name": "Network AP", "status": "active"},
            {"id": "nginx", "name": "NginX Web", "status": "inactive"},
            {"id": "mqtt", "name": "MQTT BKR", "status": "inactive"}
        ]
        self.selected_service = self.services[0]
        
        # Créer l'interface
        self.create_interface()
        
    def create_interface(self):
        # Conteneur principal
        main = tk.Frame(self.root, bg=COLORS["nord0"], padx=15, pady=15)
        main.pack(fill="both", expand=True)
        
        # Panneau gauche (services + boutons)
        self.left_frame = tk.Frame(main, bg=COLORS["nord1"], width=350)
        self.left_frame.pack_propagate(False)
        self.left_frame.pack(side="left", fill="both", padx=(0, 15))
        
        # Zone des services
        services_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=15, pady=15)
        services_frame.pack(fill="both", expand=True)
        
        services_title = tk.Label(
            services_frame,
            text="Services Disponibles",
            font=("Arial", 16, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        services_title.pack(pady=(0, 15))
        
        # Créer les éléments de service
        for service in self.services:
            self.create_service_item(services_frame, service)
        
        # Zone des boutons d'action
        buttons_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=15, pady=20)
        buttons_frame.pack(fill="x")
        
        # Créer les boutons d'action
        self.create_action_buttons(buttons_frame)
        
        # Panneau droit (console)
        right_frame = tk.Frame(main, bg=COLORS["nord1"])
        right_frame.pack(side="right", fill="both", expand=True)
        
        # Console de sortie
        console_frame = tk.Frame(right_frame, bg=COLORS["nord1"], padx=15, pady=15)
        console_frame.pack(fill="both", expand=True)
        
        console_title = tk.Label(
            console_frame,
            text="Console de Sortie",
            font=("Arial", 16, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        console_title.pack(pady=(0, 10))
        
        self.console = scrolledtext.ScrolledText(
            console_frame, 
            bg=COLORS["nord0"], 
            fg=COLORS["nord6"],
            font=("Monospace", 11),
            wrap=tk.WORD
        )
        self.console.pack(fill="both", expand=True)
        
        # Message d'accueil dans la console
        welcome_msg = """MaxLink Admin Panel V2.0 - Console Prête

Instructions:
1. Sélectionnez un service dans la liste
2. Choisissez une action (Installer/Démarrer/Tester/Désinstaller)
3. Suivez l'exécution en temps réel dans cette console

Logging avancé:
• Tous les scripts génèrent des logs détaillés
• Snapshots système automatiques
• Historique complet des opérations

Version simplifiée:
• Scripts optimisés pour NetworkManager
• Gestion intelligente des conflits
• Redémarrage automatique après chaque opération

Prêt pour l'action !

"""
        self.console.insert(tk.END, welcome_msg)
        self.console.config(state=tk.DISABLED)
        
        # Appliquer la sélection initiale
        self.update_selection()
        
    def create_service_item(self, parent, service):
        # Frame pour le service
        frame = tk.Frame(
            parent,
            bg=COLORS["nord1"],
            highlightthickness=3,  # Augmenté de 2 à 3
            padx=10,
            pady=10
        )
        frame.pack(fill="x", pady=8)
        
        # Configure les événements de clic
        for widget in [frame]:
            widget.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Nom du service (centré)
        label = tk.Label(
            frame, 
            text=service["name"],
            font=("Arial", 14, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"],
            anchor="center"
        )
        label.pack(side="left", fill="both", expand=True)
        label.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Indicateur de statut
        status_color = COLORS["nord14"] if service["status"] == "active" else COLORS["nord11"]
        indicator = tk.Canvas(frame, width=20, height=20, bg=COLORS["nord1"], highlightthickness=0)
        indicator.pack(side="right", padx=10)
        indicator.create_oval(2, 2, 18, 18, fill=status_color, outline="")
        indicator.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Stocker les références
        service["frame"] = frame
        service["indicator"] = indicator
        
    def create_action_buttons(self, parent):
        # Style commun
        button_style = {
            "font": ("Arial", 16, "bold"),
            "width": 20,
            "height": 2,
            "borderwidth": 0,
            "highlightthickness": 0,
            "cursor": "hand2"
        }
        
        # Boutons d'action
        actions = [
            {"text": "Installer", "bg": COLORS["nord10"], "action": "install"},
            {"text": "Démarrer", "bg": COLORS["nord14"], "action": "start"},
            {"text": "Tester", "bg": COLORS["nord15"], "action": "test"},
            {"text": "Désinstaller", "bg": COLORS["nord11"], "action": "uninstall"}
        ]
        
        for action in actions:
            btn = tk.Button(
                parent, 
                text=action["text"],
                bg=action["bg"],
                fg=COLORS["nord6"],
                command=lambda a=action["action"]: self.run_action(a),
                **button_style
            )
            btn.pack(fill="x", pady=5)
        
    def select_service(self, service):
        self.selected_service = service
        self.update_selection()
            
    def update_selection(self):
        for service in self.services:
            is_selected = service == self.selected_service
            # Couleur plus visible pour la sélection
            border_color = COLORS["nord8"] if is_selected else COLORS["nord1"]  # Changé de nord3 à nord8
            service["frame"].config(highlightbackground=border_color, highlightcolor=border_color)
            
    def run_action(self, action):
        if not self.selected_service:
            return
            
        service = self.selected_service
        service_id = service["id"]
        
        # Confirmation spéciale pour les désinstallations
        if action == "uninstall":
            result = messagebox.askyesno(
                "Confirmation de désinstallation",
                f"⚠️ ATTENTION ⚠️\n\n"
                f"Vous êtes sur le point de désinstaller complètement :\n"
                f"• {service['name']}\n\n"
                f"Cette opération :\n"
                f"• Supprimera toutes les configurations\n"
                f"• Restaurera les paramètres par défaut\n"
                f"• Redémarrera automatiquement le système\n"
                f"• Ne peut pas être annulée facilement\n\n"
                f"Êtes-vous sûr de vouloir continuer ?",
                icon="warning"
            )
            
            if not result:
                self.update_console(f"Désinstallation de {service['name']} annulée par l'utilisateur.\n\n")
                return
        
        # Nouveau chemin basé sur les sous-dossiers
        script_path = f"scripts/{action}/{service_id}_{action}.sh"
        
        # Afficher l'action dans la console
        action_header = f"""
{'='*80}
EXÉCUTION: {service['name']} - {action.upper()}
{'='*80}
Script: {script_path}
Logs détaillés: logs/{service_id}_{action}.log
{'='*80}

"""
        self.update_console(action_header)
        
        # Exécuter le script en arrière-plan
        threading.Thread(target=self.execute_script, args=(script_path, service, action), daemon=True).start()
    
    def get_timestamp(self):
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    def execute_script(self, script_path, service, action):
        try:
            # Construire le chemin complet du script relatif à l'emplacement de la clé USB
            full_script_path = os.path.join(self.base_path, script_path)
            
            # Vérifier si le script existe
            if not os.path.exists(full_script_path):
                self.update_console(f"ERREUR: Script {script_path} non trouvé\n")
                self.update_console(f"Chemin recherché: {full_script_path}\n\n")
                return
                
            # Exécuter le script (déjà avec sudo car le programme est lancé avec sudo)
            cmd = f"bash {full_script_path}"
            
            self.update_console(f"Exécution de la commande: {cmd}\n\n")
            
            process = subprocess.Popen(
                cmd,
                shell=True,
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE, 
                text=True, 
                bufsize=1
            )
            
            # Afficher la sortie en temps réel
            for line in iter(process.stdout.readline, ''):
                if line:
                    self.update_console(line)
            
            for line in iter(process.stderr.readline, ''):
                if line:
                    self.update_console(line, error=True)
            
            # Attendre la fin du processus
            return_code = process.wait()
            
            # Message de fin avec statut
            end_message = f"""
{'='*80}
TERMINÉ: {service['name']} - {action.upper()}
Code de sortie: {return_code}
Logs complets: logs/{service['id']}_{action}.log
{'='*80}

"""
            self.update_console(end_message)
            
            # Mettre à jour le statut (simulation)
            if return_code == 0:
                if action == "start" or action == "install":
                    service["status"] = "active"
                    self.update_status_indicator(service, True)
                elif action == "uninstall":
                    service["status"] = "inactive"
                    self.update_status_indicator(service, False)
            else:
                self.update_console(f"Le script s'est terminé avec des erreurs (code {return_code})\n")
                self.update_console("Consultez les logs pour plus de détails.\n\n")
            
        except Exception as e:
            self.update_console(f"ERREUR SYSTÈME: {str(e)}\n\n", error=True)
    
    def update_status_indicator(self, service, is_active):
        if "indicator" in service:
            status_color = COLORS["nord14"] if is_active else COLORS["nord11"]
            service["indicator"].delete("all")
            service["indicator"].create_oval(2, 2, 18, 18, fill=status_color, outline="")
    
    def update_console(self, text, error=False):
        # Utilisation de after pour la thread-safety
        self.root.after(0, self._update_console, text, error)
    
    def _update_console(self, text, error):
        self.console.config(state=tk.NORMAL)
        
        if error:
            self.console.tag_configure("error", foreground=COLORS["nord11"])
            self.console.insert(tk.END, text, "error")
        else:
            self.console.insert(tk.END, text)
            
        self.console.see(tk.END)
        self.console.config(state=tk.DISABLED)

if __name__ == "__main__":
    root = tk.Tk()
    app = MaxLinkApp(root)
    root.mainloop()