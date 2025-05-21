import tkinter as tk
from tkinter import scrolledtext
import subprocess
import os
import threading

# Couleurs du thème Nord - Réduit aux essentielles
COLORS = {
    "nord0": "#2E3440",  # Fond sombre
    "nord1": "#3B4252",  # Fond moins sombre
    "nord3": "#4C566A",  # Bordure sélection
    "nord6": "#ECEFF4",  # Texte
    "nord10": "#5E81AC", # Bouton Installer
    "nord11": "#BF616A", # Rouge / Erreur / Désinstaller
    "nord14": "#A3BE8C", # Vert / Démarrer
    "nord15": "#B48EAD", # Violet / Tester
}

class MaxLinkApp:
    def __init__(self, root):
        self.root = root
        self.root.title("MaxLink Config")
        self.root.geometry("1000x550")
        self.root.configure(bg=COLORS["nord0"])
        
        # Chemins et initialisation
        self.base_path = os.path.dirname(os.path.abspath(__file__))
        self.services = [
            {"id": "update_rpi", "name": "Update RPI", "status": "active"},
            {"id": "mqtt", "name": "MQTT BKR", "status": "active"},
            {"id": "nginx", "name": "NginX Web", "status": "active"},
            {"id": "network", "name": "Network AP", "status": "active"}
        ]
        self.selected_service = self.services[0]
        
        # Créer l'interface
        self.create_interface()
        
    def create_interface(self):
        # Conteneur principal
        main = tk.Frame(self.root, bg=COLORS["nord0"], padx=10, pady=10)
        main.pack(fill="both", expand=True)
        
        # Panneau gauche (services + boutons)
        self.left_frame = tk.Frame(main, bg=COLORS["nord1"], width=300)
        self.left_frame.pack_propagate(False)
        self.left_frame.pack(side="left", fill="both", padx=(0, 10))
        
        # Zone des services
        services_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=10, pady=10)
        services_frame.pack(fill="both", expand=True)
        
        # Créer les éléments de service
        for service in self.services:
            self.create_service_item(services_frame, service)
        
        # Zone des boutons d'action
        buttons_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=10, pady=10)
        buttons_frame.pack(fill="x")
        
        # Créer les boutons d'action
        self.create_action_buttons(buttons_frame)
        
        # Panneau droit (console)
        right_frame = tk.Frame(main, bg=COLORS["nord1"])
        right_frame.pack(side="right", fill="both", expand=True)
        
        # Console de sortie
        console_frame = tk.Frame(right_frame, bg=COLORS["nord1"], padx=10, pady=10)
        console_frame.pack(fill="both", expand=True)
        
        self.console = scrolledtext.ScrolledText(
            console_frame, 
            bg=COLORS["nord0"], 
            fg=COLORS["nord6"],
            font=("Monospace", 10)
        )
        self.console.pack(fill="both", expand=True)
        self.console.insert(tk.END, "Console prête. Les sorties des scripts apparaîtront ici.\n\n")
        self.console.config(state=tk.DISABLED)
        
        # Appliquer la sélection initiale
        self.update_selection()
        
    def create_service_item(self, parent, service):
        # Frame pour le service
        frame = tk.Frame(
            parent,
            bg=COLORS["nord1"],
            highlightthickness=2,
            padx=5,
            pady=5
        )
        frame.pack(fill="x", pady=5)
        
        # Configure les événements de clic
        for widget in [frame]:
            widget.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Nom du service
        label = tk.Label(
            frame, 
            text=service["name"],
            font=("Arial", 14, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"],
            padx=10,
            pady=5
        )
        label.pack(side="left", fill="y")
        label.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Indicateur de statut
        status_color = COLORS["nord14"] if service["status"] == "active" else COLORS["nord11"]
        indicator = tk.Canvas(frame, width=16, height=16, bg=COLORS["nord1"], highlightthickness=0)
        indicator.pack(side="right", padx=10)
        indicator.create_oval(2, 2, 14, 14, fill=status_color, outline="")
        indicator.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Stocker les références
        service["frame"] = frame
        service["indicator"] = indicator
        
    def create_action_buttons(self, parent):
        # Style commun
        button_style = {
            "font": ("Arial", 12, "bold"),
            "width": 20,
            "height": 2,
            "borderwidth": 0,
            "highlightthickness": 0
        }
        
        # Boutons d'action
        actions = [
            {"text": "Installer", "bg": COLORS["nord10"], "action": "install"},
            {"text": "Démarrer", "bg": COLORS["nord14"], "action": "start"},
            {"text": "Tester", "bg": COLORS["nord15"], "action": "test"},
            {"text": "Désinstaller", "bg": COLORS["nord11"], "action": "remove"}
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
            border_color = COLORS["nord3"] if is_selected else COLORS["nord1"]
            service["frame"].config(highlightbackground=border_color, highlightcolor=border_color)
            
    def run_action(self, action):
        if not self.selected_service:
            return
            
        service = self.selected_service
        service_id = service["id"]
        
        # Déterminer le chemin du script
        if action == "install":
            script_path = f"scripts/{service_id}_install.sh"
        elif action == "remove":
            script_path = f"scripts/{service_id}_remove.sh"
        else:
            script_path = f"scripts/{service_id}_{action}.sh"
        
        # Afficher l'action dans la console
        self.update_console(f"\n{'='*50}\nExécution: {service['name']} - {action.upper()}\n{'='*50}\n")
        
        # Exécuter le script en arrière-plan
        threading.Thread(target=self.execute_script, args=(script_path, service, action), daemon=True).start()
    
    def execute_script(self, script_path, service, action):
        try:
            # Construire le chemin complet du script relatif à l'emplacement de la clé USB
            full_script_path = os.path.join(self.base_path, script_path)
            
            # Vérifier si le script existe
            if not os.path.exists(full_script_path):
                self.update_console(f"Erreur: Script {script_path} non trouvé\n")
                return
                
            # Exécuter le script (déjà avec sudo car le programme est lancé avec sudo)
            cmd = f"bash {full_script_path}"
            
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
            self.update_console(f"\nTerminé avec le code de sortie: {return_code}\n")
            
            # Mettre à jour le statut (simulation)
            if action == "start":
                service["status"] = "active"
                self.update_status_indicator(service, True)
            elif action == "stop":
                service["status"] = "inactive"
                self.update_status_indicator(service, False)
            
        except Exception as e:
            self.update_console(f"Erreur: {str(e)}", error=True)
    
    def update_status_indicator(self, service, is_active):
        if "indicator" in service:
            status_color = COLORS["nord14"] if is_active else COLORS["nord11"]
            service["indicator"].delete("all")
            service["indicator"].create_oval(2, 2, 14, 14, fill=status_color, outline="")
    
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