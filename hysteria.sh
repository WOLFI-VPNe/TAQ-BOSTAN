#!/bin/bash
set -Eeuo pipefail
trap 'colorEcho "Script terminated prematurely." red' ERR SIGINT SIGTERM

# ------------------ Color Output Function ------------------
colorEcho() {
  local text="$1"
  local color="$2"
  case "$color" in
    red)     echo -e "\e[31m${text}\e[0m" ;;
    green)   echo -e "\e[32m${text}\e[0m" ;;
    yellow)  echo -e "\e[33m${text}\e[0m" ;;
    blue)    echo -e "\e[34m${text}\e[0m" ;;
    magenta) echo -e "\e[35m${text}\e[0m" ;;
    cyan)    echo -e "\e[36m${text}\e[0m" ;;
    *)       echo "$text" ;;
  esac
}
# ------------------ draw_menu ------------------
draw_menu() {
  local title="$1"
  shift
  local options=("$@")

  local GREEN='\e[32m'
  local WHITE='\e[97m'
  local RESET='\e[0m'

  local width=42
  local inner_width=$((width - 2))
  local line=$(printf "%${inner_width}s" "" | sed "s/ /═/g")

  local border_top="╔"
  local border_mid="╠"
  local border_bottom="╚"
  local border_side="║"
  local border_right="╗"
  local border_mid_right="╣"
  local border_bottom_right="╝"

  local title_length=${#title}
  local padding_left=$(( (inner_width - title_length) / 2 ))
  local padding_right=$(( inner_width - title_length - padding_left ))
  local title_line="$(printf "%${padding_left}s" "")${title}$(printf "%${padding_right}s" "")"

  echo -e "${GREEN}${border_top}${line}${border_right}${RESET}"
  echo -e "${GREEN}${border_side}${WHITE}${title_line}${GREEN}${border_side}${RESET}"
  echo -e "${GREEN}${border_mid}${line}${border_mid_right}${RESET}"

  for opt in "${options[@]}"; do
    printf "${GREEN}${border_side} ${WHITE}%-*s${GREEN} ${border_side}${RESET}\n" $((inner_width - 2)) "$opt"
  done

  echo -e "${GREEN}${border_mid}${line}${border_mid_right}${RESET}"
  printf "${GREEN}${border_side} ${GREEN}%-*s${GREEN} ${border_side}${RESET}\n" $((inner_width - 2)) "Enter your choice:"
  echo -e "${GREEN}${border_bottom}${line}${border_bottom_right}${RESET}"
  echo -ne "${WHITE}> ${RESET}"
}

# ------------------ Initialization ------------------
ARCH=$(uname -m)
HYSTERIA_VERSION_AMD64="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.1/hysteria-linux-amd64"
HYSTERIA_VERSION_ARM="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.1/hysteria-linux-arm"
HYSTERIA_VERSION_ARM64="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.1/hysteria-linux-arm64"

case "$ARCH" in
  x86_64)   DOWNLOAD_URL="$HYSTERIA_VERSION_AMD64" ;;
  armv7l|armv6l) DOWNLOAD_URL="$HYSTERIA_VERSION_ARM" ;;
  aarch64)  DOWNLOAD_URL="$HYSTERIA_VERSION_ARM64" ;;
  *)
    colorEcho "Unsupported architecture: $ARCH" red
    exit 1
    ;;
esac

if [ -f "/usr/local/bin/hysteria" ]; then
 colorEcho "Hysteria binary already exists at /usr/local/bin/hysteria. Skipping download." yellow
 else
 colorEcho "Downloading Hysteria binary for: $ARCH" cyan
 if ! curl -fsSL "$DOWNLOAD_URL" -o hysteria; then
   colorEcho "Failed to download hysteria binary." red
   exit 1
 fi
 chmod +x hysteria
 sudo mv hysteria /usr/local/bin/
 fi
sudo mkdir -p /etc/hysteria/
MAPPING_FILE="/etc/hysteria/port_mapping.txt"
if [ ! -f "$MAPPING_FILE" ]; then
  sudo touch "$MAPPING_FILE"
fi
sudo mkdir -p /var/log/hysteria/

# Create dedicated hysteria user if it doesn't exist
if ! id -u hysteria >/dev/null 2>&1; then
  sudo useradd -r -s /usr/sbin/nologin hysteria
  colorEcho "Created dedicated 'hysteria' user." green
fi
# Give hysteria user access to necessary directories
sudo chown -R hysteria:hysteria /etc/hysteria/ /var/log/hysteria/

# Install iptables setup script for tunnels (SIMPLE!)
sudo tee /etc/hysteria/setup_iptables.sh > /dev/null << 'IPTABLES_EOF'
#!/bin/bash
MAPPING_FILE="/etc/hysteria/port_mapping.txt"
WEB_PORT=3388

# Clear old rules
for chain in $(iptables -t mangle -L -n 2>/dev/null | grep '^Chain' | awk '{print $2}' | grep '^HYST_'); do
    iptables -t mangle -F "$chain" 2>/dev/null
    iptables -t mangle -X "$chain" 2>/dev/null
done
iptables -t mangle -F HYSTERIA_TRAFFIC 2>/dev/null
iptables -t mangle -X HYSTERIA_TRAFFIC 2>/dev/null

# Create main chain
iptables -t mangle -N HYSTERIA_TRAFFIC

# EXCLUDE WEB MANAGER PORT FIRST (so it's NOT counted!)
iptables -t mangle -A HYSTERIA_TRAFFIC -p tcp --dport $WEB_PORT -j RETURN
iptables -t mangle -A HYSTERIA_TRAFFIC -p tcp --sport $WEB_PORT -j RETURN
iptables -t mangle -A HYSTERIA_TRAFFIC -p udp --dport $WEB_PORT -j RETURN
iptables -t mangle -A HYSTERIA_TRAFFIC -p udp --sport $WEB_PORT -j RETURN

# Hook into INPUT and OUTPUT chains
iptables -t mangle -A INPUT -j HYSTERIA_TRAFFIC
iptables -t mangle -A OUTPUT -j HYSTERIA_TRAFFIC

# Add rules for each tunnel
if [ -f "$MAPPING_FILE" ]; then
    while IFS='|' read -r cfg service port_str; do
        [ -z "$cfg" ] && continue
        name="${cfg##*iran-}"
        name="${name%.yaml}"
        iptables -t mangle -N "HYST_$name" 2>/dev/null
        iptables -t mangle -A "HYST_$name" -j RETURN
        IFS=',' read -ra ports <<< "$port_str"
        for port in "${ports[@]}"; do
            [ -z "$port" ] && continue
            iptables -t mangle -A HYSTERIA_TRAFFIC -p tcp --dport "$port" -j "HYST_$name"
            iptables -t mangle -A HYSTERIA_TRAFFIC -p tcp --sport "$port" -j "HYST_$name"
            iptables -t mangle -A HYSTERIA_TRAFFIC -p udp --dport "$port" -j "HYST_$name"
            iptables -t mangle -A HYSTERIA_TRAFFIC -p udp --sport "$port" -j "HYST_$name"
        done
    done < "$MAPPING_FILE"
fi

echo "Iptables rules updated! (Web port excluded)"
IPTABLES_EOF

sudo chmod +x /etc/hysteria/setup_iptables.sh

# Run iptables setup now
sudo /etc/hysteria/setup_iptables.sh

# ------------------ Manage Tunnels Function ------------------
manage_tunnels() {
  set +e
  set +o pipefail
  colorEcho "Managing existing tunnels..." cyan
  echo "Existing tunnels:"
  shopt -s nullglob
  local config_files=(/etc/hysteria/iran-*.yaml)
  shopt -u nullglob
  for cfg in "${config_files[@]}"; do
    local name="${cfg##*/iran-}"
    name="${name%.yaml}"
    echo -e "\n=== Tunnel: ${name} ==="
    grep "server:" "$cfg" | cut -d'"' -f2
    grep "auth:"   "$cfg" | cut -d'"' -f2
    echo "Status: $(systemctl is-active "hysteria-${name}")"
  done

  echo -e "\nWhat would you like to do?"
  echo "1) Edit a tunnel"
  echo "2) Delete a tunnel"
  echo "3) Back to previous menu"
  read -rp "> " MANAGE_CHOICE

  case "$MANAGE_CHOICE" in
    1)
      read -rp "Enter tunnel name to edit: " TUNNEL_NAME
      local cfg="/etc/hysteria/iran-${TUNNEL_NAME}.yaml"
      if [ -f "$cfg" ]; then
        read -rp "Enter new server address (or press Enter to keep current): " NEW_SERVER
        read -rp "Enter new password       (or press Enter to keep current): " NEW_PASSWORD
        read -rp "Enter new SNI            (or press Enter to keep current): " NEW_SNI

        [ -n "$NEW_SERVER"   ] && sed -i "s|server: .*|server: \"$NEW_SERVER\"|"   "$cfg"
        [ -n "$NEW_PASSWORD" ] && sed -i "s|auth: .*|auth: \"$NEW_PASSWORD\"|"     "$cfg"
        [ -n "$NEW_SNI"      ] && sed -i "s|sni: .*|sni: \"$NEW_SNI\"|"           "$cfg"

        systemctl restart "hysteria-${TUNNEL_NAME}"
        colorEcho "Tunnel '${TUNNEL_NAME}' updated and restarted." green
      else
        colorEcho "Tunnel '${TUNNEL_NAME}' does not exist." red
      fi
      ;;
    2)
      read -rp "Enter tunnel name to delete: " TUNNEL_NAME
      local cfg="/etc/hysteria/iran-${TUNNEL_NAME}.yaml"
      if [ -f "$cfg" ]; then
        systemctl stop   "hysteria-${TUNNEL_NAME}"
        systemctl disable "hysteria-${TUNNEL_NAME}"
        rm "$cfg"
        rm "/etc/systemd/system/hysteria-${TUNNEL_NAME}.service"
        systemctl daemon-reload
        colorEcho "Tunnel '${TUNNEL_NAME}' deleted." green
      else
        colorEcho "Tunnel '${TUNNEL_NAME}' does not exist." red
      fi
      sed -i "\%^iran-${TUNNEL_NAME}\.yaml|%d" "$MAPPING_FILE"
      ;;
    3)
      return
      ;;
    *)
      colorEcho "Invalid choice. Returning..." red
      ;;
  esac
  set -e
  set -o pipefail
}

# ------------------ Monitor Ports Function ------------------
monitor_ports() {

  set +e
  set +o pipefail

  clear
  colorEcho "=== Monitoring Traffic Ports ===" cyan
  echo ""

  # Use ss (socket statistics) instead of netstat (more modern)
  if ! command -v ss &> /dev/null; then
    colorEcho "Installing iproute2..." yellow
    sudo apt-get update -qq
    sudo apt-get install -y iproute2 >/dev/null 2>&1
  fi

  local found=0
  # Cache ss output once for all port checks
  local tcp_listen
  local udp_listen
  tcp_listen=$(ss -tln 2>/dev/null)
  udp_listen=$(ss -uln 2>/dev/null)

  # Use glob-based discovery
  shopt -s nullglob
  local config_files=(/etc/hysteria/iran-*.yaml)
  shopt -u nullglob

  for cfg in "${config_files[@]}"; do
    local name="${cfg##*/iran-}"
    name="${name%.yaml}"
    ((found++))

    echo "🔵 Tunnel: ${name}"
    echo "----------------------------------------"

    local srv
    srv=$(grep "server:" "$cfg" | cut -d'"' -f2)
    echo "📡 Server: $srv"
    if systemctl is-active --quiet "hysteria-${name}"; then
      echo "🟢 Service: Active"
    else
      echo "🔴 Service: Inactive"
    fi

    echo -e "\n🔌 Ports Status:"

    echo "TCP Ports:"
    while read -r line; do
      # Extract port from "listen: 0.0.0.0:1234" or "listen: [::]:1234"
      port=$(echo "$line" | awk -F: '{print $NF}' | tr -d "'\" ")
      if [ -n "$port" ]; then
        # Check if port is in ss output
        if echo "$tcp_listen" | grep -q ":$port "; then
          echo "   ✅ $port (Active)"
        else
          echo "   ❌ $port (Inactive)"
        fi
      fi
    done < <(
      grep -A50 "tcpForwarding:" "$cfg" 2>/dev/null \
      | grep "listen:" 2>/dev/null
    )

    echo -e "\nUDP Ports:"
    while read -r line; do
      port=$(echo "$line" | awk -F: '{print $NF}' | tr -d "'\" ")
      if [ -n "$port" ]; then
        if echo "$udp_listen" | grep -q ":$port "; then
          echo "   ✅ $port (Active)"
        else
          echo "   ❌ $port (Inactive)"
        fi
      fi
    done < <(
      grep -A50 "udpForwarding:" "$cfg" 2>/dev/null \
      | grep "listen:" 2>/dev/null
    )

    echo "----------------------------------------"
    echo ""
  done

  if [ $found -eq 0 ]; then
    colorEcho "No tunnels found!" yellow
  fi

  colorEcho "Press Enter to return..." green
  read -r

  set -e
  set -o pipefail
}

# ------------------ View Logs Function ------------------
view_logs() {
  colorEcho "=== View Tunnel Logs ===" cyan
  shopt -s nullglob
  local config_files=(/etc/hysteria/iran-*.yaml)
  shopt -u nullglob


  if [ ${#config_files[@]} -eq 0 ]; then
    colorEcho "No tunnels found!" yellow
    sleep 2
    return
  fi

  local options=()
  local names=()
  local i=1
  for cfg in "${config_files[@]}"; do
    local name="${cfg##*/iran-}"
    name="${name%.yaml}"
    options+=("$i | $name")
    names+=("$name")
    ((i++))
  done
  options+=("A | All Tunnels")
  options+=("B | Back")

  draw_menu "Select Tunnel for Logs" "${options[@]}"
  read -rp "> " LOG_CHOICE

  if [[ "$LOG_CHOICE" =~ ^[Bb]$ ]]; then
    return
  fi

  local filter_cmd="cat"
  # Optional: Add color highlighting for keywords
  if command -v grep &> /dev/null; then
    filter_cmd="grep --color=always -E 'error|failed|connected|accepted|accepted|auth|Hysteria|$'"
  fi

  if [[ "$LOG_CHOICE" =~ ^[Aa]$ ]]; then
    clear
    colorEcho "--- Logs for All Tunnels (last 50 lines) ---" magenta
    for name in "${names[@]}"; do
      echo -e "\n🔵 Tunnel: ${name}"
      sudo journalctl -u "hysteria-${name}" -n 50 --no-pager | eval "$filter_cmd"
    done
  elif [[ "$LOG_CHOICE" =~ ^[0-9]+$ ]] && [ "$LOG_CHOICE" -le "${#names[@]}" ]; then
    local selected_name="${names[$((LOG_CHOICE-1))]}"
    clear
    colorEcho "--- Logs for Tunnel: ${selected_name} (last 100 lines) ---" magenta
    sudo journalctl -u "hysteria-${selected_name}" -n 100 --no-pager | eval "$filter_cmd"
  else
    colorEcho "Invalid option." red
    sleep 2
    return
  fi

  colorEcho "Press Enter to return to menu..." green
  read -r
}

# ------------------ Web Management Functions ------------------
setup_web_manager() {
  colorEcho "Setting up Web Management Interface..." cyan

  # Create web manager file inline
  sudo tee /etc/hysteria/web_manager.py > /dev/null << 'END_WEB_MGR'
from flask import Flask, render_template_string, request, redirect, url_for, session
import subprocess
import os
import glob
import yaml
import sqlite3
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = os.urandom(24)  # Random secret key for session security

CONFIG_DIR = "/etc/hysteria"
LOG_DIR = "/var/log/hysteria"
MAPPING_FILE = "/etc/hysteria/port_mapping.txt"
DB_FILE = "/etc/hysteria/web_manager.db"


def init_db():
  conn = sqlite3.connect(DB_FILE)
  cursor = conn.cursor()

  # Create users table
  cursor.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      is_admin INTEGER DEFAULT 0
    )
  ''')

  # Create tunnel assignments table
  cursor.execute('''
    CREATE TABLE IF NOT EXISTS user_tunnels (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      tunnel_name TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users (id),
      UNIQUE(user_id, tunnel_name)
    )
  ''')

  # Check if admin exists, create default if not
  cursor.execute("SELECT * FROM users WHERE is_admin = 1")
  if not cursor.fetchone():
    default_pass = generate_password_hash("admin123")
    cursor.execute("INSERT INTO users (username, password_hash, is_admin) VALUES (?, ?, ?)",
                  ("admin", default_pass, 1))
    conn.commit()

  conn.close()


init_db()  # Initialize the database on startup


def get_db_connection():
  conn = sqlite3.connect(DB_FILE)
  conn.row_factory = sqlite3.Row
  return conn


HTML_TEMPLATE_LOGIN = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ورود | مدیریت Hysteria</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { font-family: 'Vazirmatn', sans-serif; }
    body {
      background: radial-gradient(circle at top left, #1e1b4b 0, #020617 50%, #000000 100%);
      min-height: 100vh;
      overflow-x: hidden;
    }
    .glass-card {
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(24px);
      border: 1px solid rgba(148, 163, 184, 0.2);
      box-shadow: 0 25px 50px -12px rgba(15, 23, 42, 0.8), 0 0 0 1px rgba(15, 23, 42, 0.5);
    }
    .btn-primary {
      background: linear-gradient(135deg, #6366f1 0%, #a855f7 100%);
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }
    .btn-primary:hover {
      box-shadow: 0 0 40px rgba(99, 102, 241, 0.4);
      transform: translateY(-2px);
    }
    .input-field {
      background: rgba(15, 23, 42, 0.7);
      border: 1px solid rgba(51, 65, 85, 0.8);
      transition: all 0.3s;
    }
    .input-field:focus {
      border-color: #6366f1;
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.15);
    }
    .gradient-text {
      background: linear-gradient(135deg, #818cf8 0%, #e879f9 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    .pulse-dot {
      width: 8px; height: 8px; background: #22c55e; border-radius: 9999px;
      box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.7);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.7); }
      70% { box-shadow: 0 0 0 10px rgba(34, 197, 94, 0); }
      100% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0); }
    }
  </style>
</head>
<body class="flex items-center justify-center p-4">
  <div class="w-full max-w-md">
    <div class="glass-card rounded-3xl p-8 sm:p-10">
      <div class="text-center mb-8">
        <div class="flex justify-center mb-4">
          <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-500 flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
        </div>
        <h1 class="text-3xl font-bold gradient-text">ورود به مدیریت</h1>
        <p class="text-slate-400 mt-2 text-sm">مدیریت تونل‌های Hysteria خود را انجام دهید</p>
      </div>
      {% if error %}
      <div class="mb-6 p-4 rounded-xl bg-red-900/30 border border-red-500/30 text-red-300 text-sm text-center">
        {{ error }}
      </div>
      {% endif %}
      <form method="post" action="{{ url_for('login') }}" class="space-y-5">
        <div>
          <label for="username" class="block text-sm font-medium text-slate-300 mb-2">نام کاربری</label>
          <input type="text" id="username" name="username" required autofocus
                 class="input-field w-full px-4 py-3 rounded-xl text-white placeholder-slate-500 focus:outline-none">
        </div>
        <div>
          <label for="password" class="block text-sm font-medium text-slate-300 mb-2">رمز عبور</label>
          <input type="password" id="password" name="password" required
                 class="input-field w-full px-4 py-3 rounded-xl text-white placeholder-slate-500 focus:outline-none">
        </div>
        <button type="submit" class="btn-primary w-full py-3 px-4 rounded-xl text-white font-semibold">
          ورود
        </button>
      </form>
      <div class="mt-8 pt-6 border-t border-slate-700/50">
        <p class="text-center text-xs text-slate-500">
          نام کاربری پیش‌فرض: <span class="text-slate-300">admin</span> | رمز عبور: <span class="text-slate-300">admin123</span>
        </p>
      </div>
    </div>
  </div>
</body>
</html>
"""

HTML_TEMPLATE_MAIN = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>داشبورد | مدیریت Hysteria</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { font-family: 'Vazirmatn', sans-serif; }
    body {
      background: radial-gradient(circle at top left, #1e1b4b 0, #020617 50%, #000000 100%);
      min-height: 100vh;
      overflow-x: hidden;
    }
    .glass-card {
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(24px);
      border: 1px solid rgba(148, 163, 184, 0.2);
      box-shadow: 0 25px 50px -12px rgba(15, 23, 42, 0.8), 0 0 0 1px rgba(15, 23, 42, 0.5);
    }
    .glass-tunnel {
      background: rgba(15, 23, 42, 0.7);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(51, 65, 85, 0.6);
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }
    .glass-tunnel:hover {
      border-color: rgba(99, 102, 241, 0.6);
      transform: translateY(-2px);
      box-shadow: 0 10px 25px -5px rgba(99, 102, 241, 0.2);
    }
    .status-active {
      background: linear-gradient(135deg, #16a34a 0%, #22c55e 100%);
      box-shadow: 0 0 20px rgba(34, 197, 94, 0.3);
    }
    .status-inactive {
      background: linear-gradient(135deg, #dc2626 0%, #ef4444 100%);
      box-shadow: 0 0 20px rgba(239, 68, 68, 0.3);
    }
    .btn-primary {
      background: linear-gradient(135deg, #6366f1 0%, #a855f7 100%);
      transition: all 0.3s;
    }
    .btn-primary:hover {
      box-shadow: 0 0 30px rgba(99, 102, 241, 0.4);
      transform: translateY(-1px);
    }
    .btn-success {
      background: linear-gradient(135deg, #16a34a 0%, #22c55e 100%);
    }
    .btn-danger {
      background: linear-gradient(135deg, #dc2626 0%, #ef4444 100%);
    }
    .btn-warning {
      background: linear-gradient(135deg, #d97706 0%, #f59e0b 100%);
    }
    .stat-card {
      background: linear-gradient(135deg, rgba(15, 23, 42, 0.9), rgba(30, 64, 175, 0.4));
      border: 1px solid rgba(37, 99, 235, 0.3);
    }
    .port-chip {
      background: linear-gradient(135deg, rgba(99, 102, 241, 0.2), rgba(168, 85, 247, 0.2));
      border: 1px solid rgba(99, 102, 241, 0.4);
    }
  </style>
</head>
<body class="text-slate-100">
  <div class="min-h-screen p-4 sm:p-6 lg:p-8">
    <div class="max-w-7xl mx-auto">
      <!-- Header -->
      <header class="glass-card rounded-3xl p-4 sm:p-6 mb-8">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-500 flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="w-7 h-7 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <div>
              <h1 class="text-2xl sm:text-3xl font-bold bg-gradient-to-r from-indigo-300 via-purple-300 to-pink-300 bg-clip-text text-transparent">
                مدیریت Hysteria
              </h1>
              <p class="text-slate-400 text-sm mt-1">خوش آمدید, {{ username }}!</p>
            </div>
          </div>
          <div class="flex items-center gap-3">
            {% if is_admin %}
            <a href="{{ url_for('admin_panel') }}" class="btn-primary px-4 py-2 rounded-xl text-sm font-semibold flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              مدیریت کاربران
            </a>
            {% endif %}
            <a href="{{ url_for('logout') }}" class="px-4 py-2 rounded-xl text-sm font-semibold bg-slate-800/70 border border-slate-700 hover:bg-slate-700 transition">
              خروج
            </a>
          </div>
        </div>
      </header>

      <!-- Top Controls -->
      <div class="glass-card rounded-2xl p-4 mb-8">
        <h3 class="text-slate-300 font-semibold mb-3 flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          به‌روزرسانی خودکار
        </h3>
        <div class="flex items-center gap-3">
          <select id="refresh-interval" onchange="updateRefreshInterval()"
                  class="flex-1 bg-slate-900/70 border border-slate-700 text-slate-200 text-sm rounded-xl px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-indigo-500">
            <option value="5">5 ثانیه</option>
            <option value="10" selected>10 ثانیه</option>
            <option value="30">30 ثانیه</option>
            <option value="60">1 دقیقه</option>
            <option value="0">خاموش</option>
          </select>
        </div>
      </div>

      <!-- Tunnels List -->
      <div class="glass-card rounded-3xl p-6 sm:p-8">
        <h2 class="text-xl sm:text-2xl font-bold mb-6 flex items-center gap-3">
          <span class="inline-block w-1 h-8 rounded-full bg-gradient-to-b from-indigo-500 to-purple-500"></span>
          لیست تونل‌ها
        </h2>

        {% if tunnels %}
        <div class="grid gap-4">
          {% for tunnel in tunnels %}
          <div class="glass-tunnel rounded-2xl p-5 sm:p-6">
            <!-- Tunnel Header -->
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-5">
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-2xl bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center border border-slate-600">
                  <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                </div>
                <div>
                  <h3 class="text-xl font-bold text-white">{{ tunnel.name }}</h3>
                  <p class="text-slate-400 text-sm">{{ tunnel.server }}</p>
                </div>
              </div>
              <span class="px-4 py-1.5 rounded-full text-xs font-bold text-white {{ 'status-active' if tunnel.status == 'active' else 'status-inactive' }}">
                {{ tunnel.status_text }}
              </span>
            </div>

            <!-- Tunnel Info -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-5">
              <div class="stat-card rounded-xl p-4">
                <p class="text-slate-400 text-xs mb-1">SNI</p>
                <p class="text-lg font-semibold text-white">{{ tunnel.sni }}</p>
              </div>
              <div class="stat-card rounded-xl p-4">
                <p class="text-slate-400 text-xs mb-1">ترافیک مصرفی</p>
                <p class="text-lg font-semibold text-white">{{ tunnel.traffic }}</p>
              </div>
              <div class="stat-card rounded-xl p-4">
                <p class="text-slate-400 text-xs mb-1">وضعیت سرویس</p>
                <p class="text-lg font-semibold {{ 'text-emerald-400' if tunnel.status == 'active' else 'text-red-400' }}">
                  {{ tunnel.status_text }}
                </p>
              </div>
            </div>

            <!-- Ports -->
            {% if tunnel.tcp_ports or tunnel.udp_ports %}
            <div class="mb-5">
              {% if tunnel.tcp_ports %}
              <div class="mb-3">
                <p class="text-slate-400 text-xs mb-2">پورت‌های TCP</p>
                <div class="flex flex-wrap gap-2">
                  {% for port in tunnel.tcp_ports %}
                  <span class="port-chip px-3 py-1.5 rounded-lg text-sm text-indigo-200 font-medium">
                    {{ port }}
                  </span>
                  {% endfor %}
                </div>
              </div>
              {% endif %}
              {% if tunnel.udp_ports %}
              <div>
                <p class="text-slate-400 text-xs mb-2">پورت‌های UDP</p>
                <div class="flex flex-wrap gap-2">
                  {% for port in tunnel.udp_ports %}
                  <span class="port-chip px-3 py-1.5 rounded-lg text-sm text-purple-200 font-medium">
                    {{ port }}
                  </span>
                  {% endfor %}
                </div>
              </div>
              {% endif %}
            </div>
            {% endif %}

            <!-- Actions -->
            {% if is_admin %}
            <div class="flex flex-wrap gap-2 pt-4 border-t border-slate-700/50">
              {% if tunnel.status == 'inactive' %}
              <a href="{{ url_for('start_tunnel', name=tunnel.name) }}" class="btn-success px-4 py-2 rounded-xl text-sm font-semibold text-white">
                ▶️ شروع
              </a>
              {% else %}
              <a href="{{ url_for('stop_tunnel', name=tunnel.name) }}" class="btn-danger px-4 py-2 rounded-xl text-sm font-semibold text-white">
                ⏹️ توقف
              </a>
              {% endif %}
              <a href="{{ url_for('restart_tunnel', name=tunnel.name) }}" class="btn-warning px-4 py-2 rounded-xl text-sm font-semibold text-white">
                🔄 ری‌استارت
              </a>
              <a href="{{ url_for('view_logs', name=tunnel.name) }}" class="btn-primary px-4 py-2 rounded-xl text-sm font-semibold text-white">
                📋 لاگ‌ها
              </a>
              <a href="{{ url_for('reset_traffic', name=tunnel.name) }}" class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-slate-700/70 border border-slate-600 hover:bg-slate-700 transition">
                🔢 ریست ترافیک
              </a>
            </div>
            {% endif %}

            <!-- Logs -->
            {% if is_admin and tunnel.show_logs %}
            <div class="mt-5 bg-slate-950/80 border border-slate-800 rounded-xl p-4 overflow-x-auto">
              <pre class="text-xs sm:text-sm text-emerald-300 whitespace-pre-wrap direction-ltr">{{ tunnel.logs }}</pre>
            </div>
            {% endif %}
          </div>
          {% endfor %}
        </div>
        {% else %}
        <div class="text-center py-12">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-slate-600 mx-auto mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
          <p class="text-slate-500 text-lg">هیچ تونلی یافت نشد!</p>
        </div>
        {% endif %}
      </div>
    </div>
  </div>

  <script>
    let refreshInterval = null;

    function updateRefreshInterval() {
      const select = document.getElementById('refresh-interval');
      const interval = parseInt(select.value);

      if (refreshInterval) {
        clearInterval(refreshInterval);
        refreshInterval = null;
      }

      if (interval > 0) {
        refreshInterval = setInterval(() => {
          window.location.reload();
        }, interval * 1000);
      }
    }

    document.addEventListener('DOMContentLoaded', () => {
      updateRefreshInterval();
    });
  </script>
</body>
</html>
"""

HTML_TEMPLATE_ADMIN = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>مدیریت کاربران | Hysteria</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; font-family: 'Vazirmatn', sans-serif; }
    body {
      background: radial-gradient(circle at top left, #1e1b4b 0, #020617 50%, #000000 100%);
      min-height: 100vh;
      color: #e5e7eb;
    }
    .glass-card {
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(24px);
      border: 1px solid rgba(148, 163, 184, 0.18);
      box-shadow: 0 25px 50px -12px rgba(15, 23, 42, 0.8), 0 0 0 1px rgba(15, 23, 42, 0.5);
    }
    .field-card {
      background: rgba(15, 23, 42, 0.7);
      border: 1px solid rgba(51, 65, 85, 0.8);
      transition: all 0.3s;
    }
    .field-card:hover {
      border-color: rgba(99, 102, 241, 0.35);
    }
    label {
      display: block;
      margin-bottom: 8px;
      font-weight: 600;
      color: #cbd5e1;
    }
    input, select {
      width: 100%;
      padding: 12px 14px;
      border-radius: 14px;
      border: 1px solid rgba(51, 65, 85, 0.85);
      background: rgba(2, 6, 23, 0.75);
      color: white;
      font-size: 15px;
    }
    input:focus, select:focus {
      outline: none;
      border-color: rgba(99, 102, 241, 0.9);
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.15);
    }
    .btn {
      padding: 12px 18px;
      border: none;
      border-radius: 14px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      background: linear-gradient(135deg, #6366f1, #a855f7);
      color: white;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }
    .btn:hover {
      transform: translateY(-1px);
      box-shadow: 0 0 30px rgba(99, 102, 241, 0.35);
    }
    .btn-danger {
      background: linear-gradient(135deg, #ef4444, #dc2626);
    }
    .btn-danger:hover {
      box-shadow: 0 0 30px rgba(239, 68, 68, 0.35);
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      padding: 16px 14px;
      text-align: right;
      border-bottom: 1px solid rgba(51, 65, 85, 0.7);
      vertical-align: top;
    }
    th {
      background: rgba(15, 23, 42, 0.9);
      font-weight: 700;
      color: #cbd5e1;
    }
    .tunnel-checkboxes {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
      gap: 12px;
      margin-top: 10px;
    }
    .checkbox-item {
      background: rgba(15, 23, 42, 0.72);
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(51, 65, 85, 0.8);
      color: #e2e8f0;
    }
    .role-badge {
      display: inline-flex;
      align-items: center;
      border-radius: 9999px;
      padding: 6px 12px;
      font-size: 12px;
      font-weight: 700;
    }
    .role-admin {
      background: rgba(168, 85, 247, 0.2);
      color: #e9d5ff;
      border: 1px solid rgba(168, 85, 247, 0.4);
    }
    .role-user {
      background: rgba(59, 130, 246, 0.18);
      color: #bfdbfe;
      border: 1px solid rgba(59, 130, 246, 0.35);
    }
    .section-title {
      color: #fff;
      font-size: 1.35rem;
      font-weight: 800;
      margin-bottom: 18px;
    }
    .table-wrap {
      overflow-x: auto;
    }
  </style>
</head>
<body class="text-slate-100">
  <div class="min-h-screen p-4 sm:p-6 lg:p-8">
    <div class="max-w-7xl mx-auto">
      <header class="glass-card rounded-3xl p-5 sm:p-6 mb-8">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl sm:text-3xl font-bold bg-gradient-to-r from-indigo-300 via-purple-300 to-pink-300 bg-clip-text text-transparent">مدیریت کاربران</h1>
            <p class="text-slate-400 text-sm mt-2">ایجاد، ویرایش و تخصیص تونل برای کاربران پنل وب</p>
          </div>
          <a href="{{ url_for('index') }}" class="btn">بازگشت به داشبورد</a>
        </div>
      </header>

      <div class="grid grid-cols-1 xl:grid-cols-3 gap-6">
        <section class="glass-card rounded-3xl p-6 xl:col-span-1">
          <h2 class="section-title">ایجاد کاربر جدید</h2>
          <form method="post" action="{{ url_for('create_user') }}" class="space-y-4">
            <div class="field-card rounded-2xl p-4">
              <label for="new_username">نام کاربری</label>
              <input type="text" id="new_username" name="username" required>
            </div>
            <div class="field-card rounded-2xl p-4">
              <label for="new_password">رمز عبور</label>
              <input type="password" id="new_password" name="password" required>
            </div>
            <div class="field-card rounded-2xl p-4">
              <label for="is_admin">سطح دسترسی</label>
              <select id="is_admin" name="is_admin">
                <option value="0">کاربر عادی</option>
                <option value="1">ادمین</option>
              </select>
            </div>
            <div class="field-card rounded-2xl p-4">
              <label>تخصیص تانل‌ها</label>
              <div class="tunnel-checkboxes">
                {% for tunnel in all_tunnels %}
                <label class="checkbox-item">
                  <input type="checkbox" name="tunnels" value="{{ tunnel }}">
                  {{ tunnel }}
                </label>
                {% endfor %}
              </div>
            </div>
            <button type="submit" class="btn w-full">ایجاد کاربر</button>
          </form>
        </section>

        <section class="glass-card rounded-3xl p-6 xl:col-span-2">
          <h2 class="section-title">لیست کاربران</h2>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>نام کاربری</th>
                  <th>نقش</th>
                  <th>تانل‌های تخصیص‌یافته</th>
                  <th>عملیات</th>
                </tr>
              </thead>
              <tbody>
                {% for user in users %}
                <tr>
                  <td class="font-semibold text-white">{{ user.username }}</td>
                  <td>
                    <span class="role-badge {{ 'role-admin' if user.is_admin else 'role-user' }}">
                      {{ 'ادمین' if user.is_admin else 'کاربر' }}
                    </span>
                  </td>
                  <td class="text-slate-300">{{ ', '.join(user.tunnels) if user.tunnels else 'هیچ‌کدام' }}</td>
                  <td>
                    <form method="post" action="{{ url_for('edit_user', user_id=user.id) }}" class="space-y-3">
                      <input type="password" name="new_password" placeholder="رمز جدید (اختیاری)">
                      <select name="is_admin">
                        <option value="0" {% if not user.is_admin %}selected{% endif %}>کاربر</option>
                        <option value="1" {% if user.is_admin %}selected{% endif %}>ادمین</option>
                      </select>
                      <div>
                        <label>تخصیص تانل‌ها</label>
                        <div class="tunnel-checkboxes">
                          {% for tunnel in all_tunnels %}
                          <label class="checkbox-item">
                            <input type="checkbox" name="tunnels" value="{{ tunnel }}" {% if tunnel in user.tunnels %}checked{% endif %}>
                            {{ tunnel }}
                          </label>
                          {% endfor %}
                        </div>
                      </div>
                      <div class="flex flex-wrap gap-2">
                        <button type="submit" class="btn">ذخیره تغییرات</button>
                      </div>
                    </form>
                    <form method="post" action="{{ url_for('delete_user', user_id=user.id) }}" class="inline-flex mt-2">
                      <button type="submit" class="btn btn-danger">حذف</button>
                    </form>
                  </td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  </div>
</body>
</html>
"""


def get_tunnel_status(name):
  try:
    result = subprocess.run(
      ["systemctl", "is-active", f"hysteria-{name}"],
      capture_output=True,
      text=True
    )
    return "active" if result.returncode == 0 else "inactive"
  except Exception:
    return "inactive"


def format_bytes(bytes_val):
  for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
    if bytes_val < 1024.0:
      return f"{bytes_val:.2f} {unit}"
    bytes_val /= 1024.0
  return f"{bytes_val:.2f} PB"


def get_traffic_usage(name):
  try:
    # DIRECTLY read iptables counter for this tunnel (SIMPLE!)
    chain_name = f"HYST_{name}"
    result = subprocess.run(
      ["iptables", "-t", "mangle", "-L", chain_name, "-v", "-n", "-x"],
      capture_output=True,
      text=True
    )
    if result.returncode == 0:
      lines = result.stdout.strip().splitlines()
      # The first data line (after headers) has the counter
      for line in lines[2:]:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[0].isdigit():
          total_bytes = int(parts[1])
          return format_bytes(total_bytes)
  except Exception as e:
    pass
  return "0 B"

def parse_tunnel_config(config_path):
  try:
    with open(config_path, 'r', encoding='utf-8') as f:
      config = yaml.safe_load(f)

    name = os.path.basename(config_path).replace("iran-", "").replace(".yaml", "")

    tcp_ports = []
    if "tcpForwarding" in config:
      for forward in config["tcpForwarding"]:
        if "listen" in forward:
          port = str(forward["listen"].split(":")[-1])
          tcp_ports.append(port)

    udp_ports = []
    if "udpForwarding" in config:
      for forward in config["udpForwarding"]:
        if "listen" in forward:
          port = str(forward["listen"].split(":")[-1])
          udp_ports.append(port)

    return {
      "name": name,
      "server": config.get("server", ""),
      "sni": config.get("tls", {}).get("sni", ""),
      "status": get_tunnel_status(name),
      "status_text": "فعال" if get_tunnel_status(name) == "active" else "غیرفعال",
      "tcp_ports": tcp_ports,
      "udp_ports": udp_ports,
      "traffic": get_traffic_usage(name),
      "show_logs": False,
      "logs": ""
    }
  except Exception as e:
    return None


def get_all_tunnel_names():
  tunnels = []
  config_files = glob.glob(os.path.join(CONFIG_DIR, "iran-*.yaml"))
  for config_path in config_files:
    name = os.path.basename(config_path).replace("iran-", "").replace(".yaml", "")
    tunnels.append(name)
  return tunnels


def get_user_tunnels(user_id, is_admin):
  conn = get_db_connection()
  if is_admin:
    config_files = glob.glob(os.path.join(CONFIG_DIR, "iran-*.yaml"))
  else:
    cursor = conn.cursor()
    cursor.execute("SELECT tunnel_name FROM user_tunnels WHERE user_id = ?", (user_id,))
    assigned_tunnels = [row["tunnel_name"] for row in cursor.fetchall()]
    config_files = [os.path.join(CONFIG_DIR, f"iran-{t}.yaml") for t in assigned_tunnels
                   if os.path.exists(os.path.join(CONFIG_DIR, f"iran-{t}.yaml"))]
  conn.close()

  tunnels = []
  for config_path in config_files:
    tunnel = parse_tunnel_config(config_path)
    if tunnel:
      tunnels.append(tunnel)
  return tunnels


@app.route('/')
def index():
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT username, is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user:
    return redirect(url_for('login'))

  tunnels = get_user_tunnels(session['user_id'], user['is_admin'])

  return render_template_string(HTML_TEMPLATE_MAIN,
                              username=user['username'],
                              is_admin=user['is_admin'],
                              tunnels=tunnels)


@app.route('/login', methods=['GET', 'POST'])
def login():
  if request.method == 'POST':
    username = request.form['username']
    password = request.form['password']

    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, password_hash FROM users WHERE username = ?", (username,))
    user = cursor.fetchone()
    conn.close()

    if user and check_password_hash(user['password_hash'], password):
      session['user_id'] = user['id']
      return redirect(url_for('index'))
    else:
      return render_template_string(HTML_TEMPLATE_LOGIN, error="نام کاربری یا رمز عبور اشتباه است!")

  return render_template_string(HTML_TEMPLATE_LOGIN)


@app.route('/logout')
def logout():
  session.pop('user_id', None)
  return redirect(url_for('login'))


@app.route('/admin')
def admin_panel():
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  # Get all users with their tunnels
  cursor.execute("SELECT id, username, is_admin FROM users")
  users_db = cursor.fetchall()

  users = []
  for u in users_db:
    cursor.execute("SELECT tunnel_name FROM user_tunnels WHERE user_id = ?", (u['id'],))
    tunnels = [row['tunnel_name'] for row in cursor.fetchall()]
    users.append({
      "id": u['id'],
      "username": u['username'],
      "is_admin": u['is_admin'],
      "tunnels": tunnels
    })

  all_tunnels = get_all_tunnel_names()
  conn.close()

  return render_template_string(HTML_TEMPLATE_ADMIN, users=users, all_tunnels=all_tunnels)


@app.route('/admin/create', methods=['POST'])
def create_user():
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  username = request.form['username']
  password = request.form['password']
  is_admin = int(request.form.get('is_admin', 0))
  selected_tunnels = request.form.getlist('tunnels')

  hashed_pw = generate_password_hash(password)

  try:
    cursor.execute("INSERT INTO users (username, password_hash, is_admin) VALUES (?, ?, ?)",
                  (username, hashed_pw, is_admin))
    user_id = cursor.lastrowid

    for tunnel_name in selected_tunnels:
      cursor.execute("INSERT OR IGNORE INTO user_tunnels (user_id, tunnel_name) VALUES (?, ?)",
                    (user_id, tunnel_name))

    conn.commit()
  except sqlite3.IntegrityError:
    pass  # User already exists

  conn.close()
  return redirect(url_for('admin_panel'))


@app.route('/admin/edit/<int:user_id>', methods=['POST'])
def edit_user(user_id):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  current_user = cursor.fetchone()

  if not current_user or not current_user['is_admin']:
    return redirect(url_for('index'))

  new_password = request.form.get('new_password')
  selected_tunnels = request.form.getlist('tunnels')
  is_admin = request.form.get('is_admin')

  if new_password:
    hashed_pw = generate_password_hash(new_password)
    cursor.execute("UPDATE users SET password_hash = ? WHERE id = ?", (hashed_pw, user_id))

  if is_admin is not None:
    cursor.execute("UPDATE users SET is_admin = ? WHERE id = ?", (int(is_admin), user_id))

  # Update tunnel assignments
  cursor.execute("DELETE FROM user_tunnels WHERE user_id = ?", (user_id,))
  for tunnel_name in selected_tunnels:
    cursor.execute("INSERT OR IGNORE INTO user_tunnels (user_id, tunnel_name) VALUES (?, ?)",
                  (user_id, tunnel_name))

  conn.commit()
  conn.close()
  return redirect(url_for('admin_panel'))


@app.route('/admin/delete/<int:user_id>', methods=['POST'])
def delete_user(user_id):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  current_user = cursor.fetchone()

  if not current_user or not current_user['is_admin']:
    return redirect(url_for('index'))

  # Don't allow deleting yourself
  if user_id == session['user_id']:
    return redirect(url_for('admin_panel'))

  cursor.execute("DELETE FROM user_tunnels WHERE user_id = ?", (user_id,))
  cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
  conn.commit()
  conn.close()

  return redirect(url_for('admin_panel'))


@app.route('/start/<name>')
def start_tunnel(name):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  # Check if user is admin
  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  try:
    subprocess.run(["systemctl", "start", f"hysteria-{name}"], check=True)
  except Exception:
    pass
  return redirect(url_for('index'))


@app.route('/stop/<name>')
def stop_tunnel(name):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  # Check if user is admin
  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  try:
    subprocess.run(["systemctl", "stop", f"hysteria-{name}"], check=True)
  except Exception:
    pass
  return redirect(url_for('index'))


@app.route('/restart/<name>')
def restart_tunnel(name):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  # Check if user is admin
  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  try:
    subprocess.run(["systemctl", "restart", f"hysteria-{name}"], check=True)
  except Exception:
    pass
  return redirect(url_for('index'))


@app.route('/logs/<name>')
def view_logs(name):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT username, is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  tunnels = get_user_tunnels(session['user_id'], user['is_admin'])

  for tunnel in tunnels:
    if tunnel["name"] == name:
      try:
        log_path = os.path.join(LOG_DIR, f"hysteria-{name}.log")
        if os.path.exists(log_path):
          with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            tunnel["logs"] = f.read()[-2000:] if os.path.getsize(log_path) > 2000 else f.read()
        else:
          tunnel["logs"] = "فایل لاگ یافت نشد!"
      except Exception as e:
        tunnel["logs"] = f"خطا در خواندن لاگ: {str(e)}"
      tunnel["show_logs"] = True

  return render_template_string(HTML_TEMPLATE_MAIN,
                              username=user['username'],
                              is_admin=user['is_admin'],
                              tunnels=tunnels)


@app.route('/reset/<name>')
def reset_traffic(name):
  if 'user_id' not in session:
    return redirect(url_for('login'))

  # Check if user is admin
  conn = get_db_connection()
  cursor = conn.cursor()
  cursor.execute("SELECT is_admin FROM users WHERE id = ?", (session['user_id'],))
  user = cursor.fetchone()
  conn.close()

  if not user or not user['is_admin']:
    return redirect(url_for('index'))

  try:
    data_file = "/etc/hysteria/traffic_data.json"
    import json
    # Read current data
    with open(data_file, "r") as f:
      data = json.load(f)
    # Reset traffic for this tunnel
    if name in data:
      del data[name]
    # Write back
    with open(data_file, "w") as f:
      json.dump(data, f, indent=2)
  except Exception:
    pass
  return redirect(url_for('index'))

if __name__ == '__main__':
  # Ensure iptables rules are set up on web manager start
  try:
    subprocess.run(["/etc/hysteria/setup_iptables.sh"], capture_output=True, text=True)
  except Exception:
    pass
  app.run(host='0.0.0.0', port=3388, debug=False)
END_WEB_MGR

  sudo chmod +x /etc/hysteria/web_manager.py
  sudo mkdir -p /var/log/hysteria
  colorEcho "Web manager file updated." green

  # Create systemd service for web manager
  sudo tee /etc/systemd/system/hysteria-web.service > /dev/null << 'EOF'
[Unit]
Description=Hysteria Web Management Interface
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/hysteria/web_manager.py
Restart=always
RestartSec=5
StandardOutput=file:/var/log/hysteria/web_manager.log
StandardError=file:/var/log/hysteria/web_manager.err

[Install]
WantedBy=multi-user.target
EOF

  # Install Python dependencies
  colorEcho "Checking Python dependencies..." cyan
  if ! python3 -c "import flask, yaml, werkzeug" >/dev/null 2>&1; then
    colorEcho "Installing required packages..." yellow
    sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y python3-flask python3-yaml python3-werkzeug >/dev/null 2>&1
  else
    colorEcho "Required packages already installed. Skipping apt install." green
  fi

  colorEcho "Reloading systemd service..." cyan
  sudo systemctl daemon-reload
  sudo systemctl enable hysteria-web >/dev/null 2>&1
  sudo systemctl restart hysteria-web

  if sudo systemctl is-active --quiet hysteria-web; then
    colorEcho "Web Management Interface is ready: http://YOUR_SERVER_IP:3388" green
  else
    colorEcho "Web service failed to start. Check: journalctl -u hysteria-web --no-pager -n 50" red
  fi
}

manage_web() {
  while true; do
    draw_menu "Web Management" \
      "1 | Install/Update Web Interface" \
      "2 | Start Web Service" \
      "3 | Stop Web Service" \
      "4 | Restart Web Service" \
      "5 | Show Web Service Status" \
      "6 | Create Web User (Admin Only)" \
      "7 | Back"

    read -rp "> " WEB_CHOICE

    case "$WEB_CHOICE" in
      1)
        setup_web_manager
        ;;
      2)
        sudo systemctl start hysteria-web
        colorEcho "Web service started!" green
        ;;
      3)
        sudo systemctl stop hysteria-web
        colorEcho "Web service stopped!" green
        ;;
      4)
        sudo systemctl restart hysteria-web
        colorEcho "Web service restarted!" green
        ;;
      5)
        sudo systemctl status hysteria-web --no-pager
        ;;
      6)
        manage_web_users
        ;;
      7)
        return
        ;;
      *)
        colorEcho "Invalid option!" red
        ;;
    esac
  done
}

manage_web_users() {
  while true; do
    draw_menu "Web User Management" \
      "1 | Create New User" \
      "2 | List All Users" \
      "3 | Edit User" \
      "4 | Delete User" \
      "5 | Back"

    read -rp "> " USER_CHOICE

    case "$USER_CHOICE" in
      1)
        read -rp "Enter new username: " NEW_USER
        read -rp "Enter password for $NEW_USER: " NEW_PASS
        read -rp "Is this user an admin? (y/n): " IS_ADMIN

        # Get list of existing tunnels
        shopt -s nullglob
        tunnel_files=(/etc/hysteria/iran-*.yaml)
        shopt -u nullglob

        # Extract tunnel names
        tunnel_names=()
        for cfg in "${tunnel_files[@]}"; do
            name="${cfg##*/iran-}"
            name="${name%.yaml}"
            tunnel_names+=("$name")
        done

        # If there are tunnels, ask which ones to assign
        selected_tunnels=()
        if [ ${#tunnel_names[@]} -gt 0 ]; then
            colorEcho "Available tunnels:" cyan
            for i in "${!tunnel_names[@]}"; do
                echo "  $((i+1))) ${tunnel_names[$i]}"
            done
            echo "  Enter tunnel numbers separated by spaces (or press Enter for none):"
            read -rp "> " tunnel_choices

            # Parse selected choices
            for choice in $tunnel_choices; do
                if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#tunnel_names[@]} ]; then
                    selected_tunnels+=("${tunnel_names[$((choice-1))]}")
                fi
            done
        fi

        # Convert selected tunnels to Python list string
        tunnels_python="["
        first=1
        for t in "${selected_tunnels[@]}"; do
            if [ $first -eq 1 ]; then
                first=0
            else
                tunnels_python="$tunnels_python, "
            fi
            tunnels_python="$tunnels_python'$t'"
        done
        tunnels_python="$tunnels_python]"

        # Use Python to interact with the database
        python3 << END_CREATE_USER
import sqlite3
from werkzeug.security import generate_password_hash
import os

DB_FILE = "/etc/hysteria/web_manager.db"
os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)

conn = sqlite3.connect(DB_FILE)
cursor = conn.cursor()

# Initialize tables if they don't exist
cursor.execute('''
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_admin INTEGER DEFAULT 0
  )
''')
cursor.execute('''
  CREATE TABLE IF NOT EXISTS user_tunnels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tunnel_name TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id),
    UNIQUE(user_id, tunnel_name)
  )
''')

# Create user
try:
    hashed = generate_password_hash("$NEW_PASS")
    is_admin_val = 1 if "$IS_ADMIN" == "y" or "$IS_ADMIN" == "Y" else 0
    cursor.execute(
        "INSERT INTO users (username, password_hash, is_admin) VALUES (?, ?, ?)",
        ("$NEW_USER", hashed, is_admin_val)
    )
    user_id = cursor.lastrowid

    # Assign selected tunnels
    selected_tunnels = $tunnels_python
    for tunnel_name in selected_tunnels:
        cursor.execute(
            "INSERT OR IGNORE INTO user_tunnels (user_id, tunnel_name) VALUES (?, ?)",
            (user_id, tunnel_name)
        )

    conn.commit()
    print("✅ User $NEW_USER created successfully!")
except sqlite3.IntegrityError:
    print("❌ Error: User $NEW_USER already exists!")

conn.close()
END_CREATE_USER
        ;;
      2)
        python3 << 'END_LIST_USERS'
import sqlite3
import os

DB_FILE = "/etc/hysteria/web_manager.db"
if os.path.exists(DB_FILE):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT username, is_admin FROM users")
    users = cursor.fetchall()

    print("\\n=== Web Users ===")
    for user in users:
        role = "Admin" if user[1] else "User"
        print(f" - {user[0]} ({role})")
    conn.close()
else:
    print("Database not found!")
END_LIST_USERS
        ;;
      3)
        read -rp "Enter username to edit: " USER_TO_CHANGE

        # Get list of existing tunnels
        shopt -s nullglob
        tunnel_files=(/etc/hysteria/iran-*.yaml)
        shopt -u nullglob

        # Extract tunnel names
        tunnel_names=()
        for cfg in "${tunnel_files[@]}"; do
            name="${cfg##*/iran-}"
            name="${name%.yaml}"
            tunnel_names+=("$name")
        done

        # Ask for new password (optional)
        read -rp "Enter new password (or press Enter to keep current): " NEW_PASS

        # Ask if admin
        read -rp "Is this user an admin? (y/n, or press Enter to keep current): " IS_ADMIN

        # Ask for tunnel assignments if there are tunnels
        selected_tunnels=()
        if [ ${#tunnel_names[@]} -gt 0 ]; then
            colorEcho "Available tunnels:" cyan
            for i in "${!tunnel_names[@]}"; do
                echo "  $((i+1))) ${tunnel_names[$i]}"
            done
            echo "  Enter tunnel numbers separated by spaces (or press Enter to keep current):"
            read -rp "> " tunnel_choices

            # Parse selected choices
            for choice in $tunnel_choices; do
                if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#tunnel_names[@]} ]; then
                    selected_tunnels+=("${tunnel_names[$((choice-1))]}")
                fi
            done
        fi

        # Prepare Python variables
        new_pass_python="None"
        if [ -n "$NEW_PASS" ]; then
            new_pass_python="'$NEW_PASS'"
        fi

        is_admin_python="None"
        if [ -n "$IS_ADMIN" ]; then
            if [ "$IS_ADMIN" = "y" ] || [ "$IS_ADMIN" = "Y" ]; then
                is_admin_python="1"
            else
                is_admin_python="0"
            fi
        fi

        # Convert selected tunnels to Python list string, or None if empty
        tunnels_python="None"
        if [ ${#selected_tunnels[@]} -gt 0 ]; then
            tunnels_python="["
            first=1
            for t in "${selected_tunnels[@]}"; do
                if [ $first -eq 1 ]; then
                    first=0
                else
                    tunnels_python="$tunnels_python, "
                fi
                tunnels_python="$tunnels_python'$t'"
            done
            tunnels_python="$tunnels_python]"
        fi

        # Use Python to interact with the database
        python3 << END_EDIT_USER
import sqlite3
from werkzeug.security import generate_password_hash
import os

DB_FILE = "/etc/hysteria/web_manager.db"
if os.path.exists(DB_FILE):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # Get user
    cursor.execute("SELECT id, is_admin FROM users WHERE username = ?", ("$USER_TO_CHANGE",))
    user = cursor.fetchone()
    if not user:
        print("❌ User not found!")
        conn.close()
        exit()

    user_id = user[0]
    current_is_admin = user[1]

    # Update password if provided
    new_pass = $new_pass_python
    if new_pass is not None:
        hashed = generate_password_hash(new_pass)
        cursor.execute(
            "UPDATE users SET password_hash = ? WHERE id = ?",
            (hashed, user_id)
        )

    # Update admin status if provided
    new_is_admin = $is_admin_python
    if new_is_admin is not None:
        cursor.execute(
            "UPDATE users SET is_admin = ? WHERE id = ?",
            (new_is_admin, user_id)
        )

    # Update tunnel assignments if provided
    new_tunnels = $tunnels_python
    if new_tunnels is not None:
        cursor.execute("DELETE FROM user_tunnels WHERE user_id = ?", (user_id,))
        for tunnel_name in new_tunnels:
            cursor.execute(
                "INSERT OR IGNORE INTO user_tunnels (user_id, tunnel_name) VALUES (?, ?)",
                (user_id, tunnel_name)
            )

    conn.commit()
    print("✅ User updated successfully!")
    conn.close()
else:
    print("Database not found!")
END_EDIT_USER
        ;;
      4)
        read -rp "Enter username to delete: " USER_TO_DELETE
        if [ "$USER_TO_DELETE" = "admin" ]; then
            colorEcho "Cannot delete the default admin user!" red
            continue
        fi

        python3 << END_DELETE_USER
import sqlite3
import os

DB_FILE = "/etc/hysteria/web_manager.db"
if os.path.exists(DB_FILE):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # Get user id
    cursor.execute("SELECT id FROM users WHERE username = ?", ("$USER_TO_DELETE",))
    user = cursor.fetchone()
    if not user:
        print("❌ User not found!")
        conn.close()
        exit()

    # Delete user and their tunnel assignments
    cursor.execute("DELETE FROM user_tunnels WHERE user_id = ?", (user[0],))
    cursor.execute("DELETE FROM users WHERE id = ?", (user[0],))
    conn.commit()
    conn.close()
    print("✅ User deleted!")
else:
    print("Database not found!")
END_DELETE_USER
        ;;
      5)
        return
        ;;
      *)
        colorEcho "Invalid option!" red
        ;;
    esac
    echo ""
    colorEcho "Press Enter to continue..." green
    read -r
  done
}

# ------------------ View Tunnel Information Function ------------------
view_tunnel_info() {
  colorEcho "=== View Tunnel Information ===" cyan
  shopt -s nullglob
  local config_files=(/etc/hysteria/iran-*.yaml)
  shopt -u nullglob

  if [ ${#config_files[@]} -eq 0 ]; then
    colorEcho "No tunnels found!" yellow
    sleep 2
    return
  fi

  for cfg in "${config_files[@]}"; do
    local name="${cfg##*/iran-}"
    name="${name%.yaml}"
    
    echo -e "\n$(printf -- '═%.0s' {1..50})"
    colorEcho "Tunnel Name: ${name}" magenta
    echo "$(printf -- '─%.0s' {1..50})"
    
    local server=$(grep "server:" "$cfg" | cut -d'"' -f2)
    local auth=$(grep "auth:" "$cfg" | cut -d'"' -f2)
    local sni=$(grep "sni:" "$cfg" | cut -d'"' -f2)
    
    echo -e "📡 Server   : \e[33m${server}\e[0m"
    echo -e "🔑 Password : \e[33m${auth}\e[0m"
    echo -e "🌐 SNI      : \e[33m${sni}\e[0m"
    
    echo -e "\n🔌 Forwarded Ports:"
    echo "  TCP:"
    grep -A50 "tcpForwarding:" "$cfg" | grep "listen:" | awk '{print "    - "$NF}'
    echo "  UDP:"
    grep -A50 "udpForwarding:" "$cfg" | grep "listen:" | awk '{print "    - "$NF}'
    
    echo "$(printf -- '═%.0s' {1..50})"
  done

  echo ""
  colorEcho "Press Enter to return to menu..." green
  read -r
}

# ------------------ Restart Management Function ------------------
restart_management() {
  colorEcho "=== Restart Management ===" cyan
  shopt -s nullglob
  local config_files=(/etc/hysteria/iran-*.yaml)
  shopt -u nullglob

  if [ ${#config_files[@]} -eq 0 ]; then
    colorEcho "No tunnels found!" yellow
    sleep 2
    return
  fi

  local options=()
  local names=()
  local i=1
  for cfg in "${config_files[@]}"; do
    local name="${cfg##*/iran-}"
    name="${name%.yaml}"
    options+=("$i | $name")
    names+=("$name")
    ((i++))
  done
  options+=("A | All Tunnels")
  options+=("B | Back")

  draw_menu "Select Tunnel to Restart" "${options[@]}"
  read -rp "> " CHOICE

  if [[ "$CHOICE" =~ ^[Bb]$ ]]; then
    return
  fi

  if [[ "$CHOICE" =~ ^[Aa]$ ]]; then
    colorEcho "Restarting all tunnels..." yellow
    for name in "${names[@]}"; do
      systemctl restart "hysteria-${name}"
      echo "Restarted: ${name}"
    done
  elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#names[@]}" ]; then
    local selected_name="${names[$((CHOICE-1))]}"
    colorEcho "Restarting tunnel: ${selected_name}..." yellow
    systemctl restart "hysteria-${selected_name}"
    colorEcho "Done." green
  else
    colorEcho "Invalid option." red
    sleep 2
    return
  fi
  sleep 2
}

# ------------------ Cronjob Management Function ------------------
manage_cronjobs() {
  while true; do
    draw_menu "Cronjob Management" \
      "1 | Show Current Cronjobs" \
      "2 | Enable Daily Restart (04:00 AM) for All Tunnels" \
      "3 | Disable All Hysteria Cronjobs" \
      "4 | Back"
    read -rp "> " CRON_CHOICE

    case "$CRON_CHOICE" in
      1)
        clear
        colorEcho "Current Hysteria Cronjobs:" magenta
        crontab -l 2>/dev/null | grep "hysteria" || echo "No hysteria cronjobs found."
        echo ""
        read -rp "Press Enter to continue..."
        ;;
      2)
        local CRON_CMD="0 4 * * * systemctl restart hysteria-*.service"
        local TMP_CRON=$(mktemp)
        crontab -l 2>/dev/null | grep -v "hysteria-*.service" > "$TMP_CRON" || true
        echo "$CRON_CMD" >> "$TMP_CRON"
        crontab "$TMP_CRON"
        rm -f "$TMP_CRON"
        colorEcho "Daily restart cronjob enabled at 04:00 AM." green
        sleep 2
        ;;
      3)
        local TMP_CRON=$(mktemp)
        crontab -l 2>/dev/null | grep -v "hysteria" > "$TMP_CRON" || true
        crontab "$TMP_CRON"
        rm -f "$TMP_CRON"
        colorEcho "All Hysteria cronjobs disabled." green
        sleep 2
        ;;
      4)
        return
        ;;
      *)
        colorEcho "Invalid selection." red
        sleep 2
        ;;
    esac
  done
}

# ------------------ Sudo Authentication ------------------
colorEcho "Please enter your sudo password to continue:" cyan
sudo -v
while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
done 2>/dev/null &

# ------------------ Server Type Menu ------------------
while true; do
draw_menu "Server Type Selection" \
    "1 | Setup Iranian Server" \
    "2 | Setup Foreign Server" \
    "3 | Exit"
  read -r SERVER_CHOICE
  case "$SERVER_CHOICE" in
    1)
      while true; do
        draw_menu "Iranian Server Options" \
          "1 | Create New Tunnel" \
          "2 | Edit Tunnel List" \
          "3 | Monitor Traffic Ports" \
          "4 | View System Logs" \
          "5 | View Tunnel Information" \
          "6 | Restart Management" \
          "7 | Cronjob Management" \
          "8 | Web Management" \
          "9 | Exit"
        read -rp "> " IRAN_CHOICE
        case "$IRAN_CHOICE" in
          1) 
            SERVER_TYPE="iran"; break 2
            ;;
          2) 
            manage_tunnels 
            ;;
          3) 
            monitor_ports     
            ;;
          4)
            view_logs
            ;;
          5)
            view_tunnel_info
            ;;
          6)
            restart_management
            ;;
          7)
            manage_cronjobs
            ;;
          8)
            manage_web
            ;;
          9) 
            colorEcho "Exiting..." yellow; exit 0 
            ;;
          *) 
            colorEcho "Invalid selection. Please enter 1-9." red 
            ;;
        esac
      done
      ;;
    2)
      SERVER_TYPE="foreign"
      break
      ;;
    3)
      colorEcho "Exiting..." yellow
      exit 0
      ;;
    *)
      colorEcho "Invalid selection. Please enter 1, 2, or 3." red
      ;;
  esac
done

# ------------------ Port Input Menu ------------------
collect_ports() {
  local collected_ports=()

  # Redirect draw_menu and colorEcho to stderr temporarily, and read from /dev/tty
  while true; do
    # Call draw_menu, redirecting output to stderr
    draw_menu "Port Forwarding Type" \
      "1 | Single Port" \
      "2 | Port Range (e.g., 1000-2000)" \
      "3 | Finished (Continue)" >&2
    # Read from /dev/tty to avoid issues with stdin
    read -rp "> " PORT_TYPE_CHOICE < /dev/tty

    case "$PORT_TYPE_CHOICE" in
      1)
        while true; do
          read -rp "Enter single port (1-65535): " SINGLE_PORT < /dev/tty
          if [[ "$SINGLE_PORT" =~ ^[0-9]+$ ]] && (( SINGLE_PORT >= 1 && SINGLE_PORT <= 65535 )); then
            collected_ports+=("$SINGLE_PORT")
            colorEcho "Port $SINGLE_PORT added." green >&2
            break
          else
            colorEcho "Invalid port! Enter a number between 1 and 65535." red >&2
          fi
        done
        ;;
      2)
        while true; do
          read -rp "Enter port range (e.g., 1000-2000): " RANGE_INPUT < /dev/tty
          if [[ "$RANGE_INPUT" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            if (( start >= 1 && start <= 65535 && end >= 1 && end <= 65535 && start <= end )); then
              for (( p=start; p<=end; p++ )); do
                collected_ports+=("$p")
              done
              colorEcho "Ports $start to $end added." green >&2
              break
            else
              colorEcho "Invalid range! Start must be <= end and both between 1-65535." red >&2
            fi
          else
            colorEcho "Invalid format! Use format: START-END (e.g., 1000-2000)." red >&2
          fi
        done
        ;;
      3)
        if [ ${#collected_ports[@]} -eq 0 ]; then
          colorEcho "You must add at least one port first!" red >&2
        else
          break
        fi
        ;;
      *)
        colorEcho "Invalid selection. Please choose 1-3." red >&2
        ;;
    esac
  done

  # Only send the final port list to stdout
  echo "${collected_ports[@]}"
}

# ------------------ IP Version Menu (Only for Iran) ------------------
if [ "$SERVER_TYPE" == "iran" ]; then
  while true; do
    draw_menu "IP Version Selection" \
      "1 | IPv4" \
      "2 | IPv6" \
      "3 | Exit"
    read -r IP_VERSION_CHOICE

    case "$IP_VERSION_CHOICE" in
      1)
        REMOTE_IP="0.0.0.0"
        break
        ;;
      2)
        REMOTE_IP="[::]"
        break
        ;;
      3)
        # Return to previous menu
        continue 2
        ;;
      *)
        colorEcho "Invalid selection. Please enter 1, 2, or 3." red
        ;;
    esac
  done
fi

# ------------------ Obfuscation Option ------------------
read -p "Do you want to enable Obfuscation (obfs)? [y/N]: " ENABLE_OBFS
ENABLE_OBFS=$(echo "$ENABLE_OBFS" | tr '[:upper:]' '[:lower:]')

if [[ "$ENABLE_OBFS" == "y" || "$ENABLE_OBFS" == "yes" ]]; then
  OBFS_CONFIG=$(cat <<EOF
obfs:
  type: salamander
  salamander:
    password: "__REPLACE_PASSWORD__"
EOF
)
else
  OBFS_CONFIG=""
fi

# ------------------ QUIC Settings Based on Usage ------------------
draw_menu "Expected Simultaneous Users" \
  "1 | 1 to 50 users (Light load)" \
  "2 | 50 to 100 users (Medium load)" \
  "3 | 100 to 300 users (Heavy load)"
read -r USAGE_CHOICE

case "$USAGE_CHOICE" in
  1)
    QUIC_SETTINGS=$(cat <<EOF
quic:
  initStreamReceiveWindow: 25165824
  maxStreamReceiveWindow: 50331648
  initConnReceiveWindow: 50331648
  maxConnReceiveWindow: 100663296
  maxIdleTimeout: 15s
  keepAliveInterval: 10s
  maxIncomingStreams: 4096
  disablePathMTUDiscovery: false
EOF
)
    ;;
  2)
    QUIC_SETTINGS=$(cat <<EOF
quic:
  initStreamReceiveWindow: 50331648
  maxStreamReceiveWindow: 100663296
  initConnReceiveWindow: 100663296
  maxConnReceiveWindow: 201326592
  maxIdleTimeout: 15s
  keepAliveInterval: 10s
  maxIncomingStreams: 8192
  disablePathMTUDiscovery: false
EOF
)
    ;;
  3)
    QUIC_SETTINGS=$(cat <<EOF
quic:
  initStreamReceiveWindow: 100663296
  maxStreamReceiveWindow: 201326592
  initConnReceiveWindow: 201326592
  maxConnReceiveWindow: 402653184
  maxIdleTimeout: 15s
  keepAliveInterval: 10s
  maxIncomingStreams: 24576
  disablePathMTUDiscovery: false
EOF
)
    ;;
  *)
    echo "Invalid option. Defaulting to 1-50 users (light load)."
    QUIC_SETTINGS=$(cat <<EOF
quic:
  initStreamReceiveWindow: 25165824
  maxStreamReceiveWindow: 50331648
  initConnReceiveWindow: 50331648
  maxConnReceiveWindow: 100663296
  maxIdleTimeout: 15s
  keepAliveInterval: 10s
  maxIncomingStreams: 4096
  disablePathMTUDiscovery: false
EOF
)
    ;;
esac

# ------------------ Foreign Server Setup ------------------
if [ "$SERVER_TYPE" == "foreign" ]; then
  colorEcho "Setting up foreign server..." green

  if ! command -v openssl &> /dev/null; then
    sudo apt update -y && sudo apt install -y openssl
  fi

  colorEcho "Generating self-signed certificate..." cyan
  sudo openssl req -x509 -nodes -days 3650 -newkey ed25519 \
    -keyout /etc/hysteria/self.key \
    -out /etc/hysteria/self.crt \
    -subj "/CN=myserver"
  sudo chmod 600 /etc/hysteria/self.*

  while true; do
    read -p "Enter Hysteria port ex.(443) or (1-65535): " H_PORT
    if [[ "$H_PORT" =~ ^[0-9]+$ ]] && (( H_PORT > 0 && H_PORT < 65536 )); then
      break
    else
      colorEcho "Invalid port. Try again." red
    fi
  done

  while true; do
    read -p "Enter password: " H_PASSWORD
    if [[ -z "$H_PASSWORD" ]]; then
      colorEcho "Password cannot be empty. Please enter a valid password." red
    else
      break
    fi
  done

  cat << EOF | sudo tee /etc/hysteria/server-config.yaml > /dev/null
listen: ":$H_PORT"
tls:
  cert: /etc/hysteria/self.crt
  key: /etc/hysteria/self.key
auth:
  type: password
  password: "$H_PASSWORD"
$(echo "$OBFS_CONFIG" | sed "s/__REPLACE_PASSWORD__/$H_PASSWORD/")
$(echo "$QUIC_SETTINGS")
speedTest: true
EOF

  cat << EOF | sudo tee /etc/systemd/system/hysteria.service > /dev/null
[Unit]
Description=Hysteria2 Tunnel Service
After=network.target

[Service]
Type=simple
User=hysteria
Group=hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/server-config.yaml
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=file:/var/log/hysteria/hysteria.log
StandardError=file:/var/log/hysteria/hysteria.err

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now hysteria
  sudo systemctl reload-or-restart hysteria
  CRON_CMD='0 4 * * * /usr/bin/systemctl restart hysteria'
  TMP_FILE=$(mktemp)

  crontab -l 2>/dev/null | grep -vF "$CRON_CMD" > "$TMP_FILE" || true
  echo "$CRON_CMD" >> "$TMP_FILE"
  crontab "$TMP_FILE"
  rm -f "$TMP_FILE"

  colorEcho "Foreign server setup completed." green

# ------------------ Iranian Client Setup ------------------
elif [ "$SERVER_TYPE" == "iran" ]; then
  colorEcho "Setting up Iranian server..." green

  read -p "How many foreign servers do you have? " SERVER_COUNT

  for (( i=1; i<=SERVER_COUNT; i++ )); do
    colorEcho "Foreign server #$i:" cyan
    
    read -p "Enter a custom name for this tunnel (e.g., london): " TUNNEL_NAME
    while true; do
      read -p "Enter IP Address or Domain for Foreign server: " SERVER_ADDRESS
      if [[ "$SERVER_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        break
      elif [[ "$SERVER_ADDRESS" =~ ^[0-9a-fA-F:]+$ ]]; then
        SERVER_ADDRESS="[${SERVER_ADDRESS}]"
        break
      elif [[ "$SERVER_ADDRESS" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        break
      else
        colorEcho "Invalid input. Please enter a valid IP or domain." red
      fi
    done

    read -p "Hysteria Port ex.(443): " PORT

    while true; do
      read -p "Password: " PASSWORD
      if [[ -z "$PASSWORD" ]]; then
        colorEcho "Password cannot be empty. Please enter a valid password." red
      else
        break
      fi
    done

    read -p "SNI ex.(google.com): " SNI
    colorEcho "Now let's configure port forwarding..." cyan

    TCP_FORWARD=""
    UDP_FORWARD=""
    FORWARDED_PORTS=""

    # Get all ports using our new function
    ports_array=($(collect_ports))

    for TUNNEL_PORT in "${ports_array[@]}"; do
      TCP_FORWARD+="  - listen: 0.0.0.0:$TUNNEL_PORT
    remote: '$REMOTE_IP:$TUNNEL_PORT'
"
      UDP_FORWARD+="  - listen: 0.0.0.0:$TUNNEL_PORT
    remote: '$REMOTE_IP:$TUNNEL_PORT'
"
      if [ -z "$FORWARDED_PORTS" ]; then
        FORWARDED_PORTS="$TUNNEL_PORT"
      else
        FORWARDED_PORTS="$FORWARDED_PORTS,$TUNNEL_PORT"
      fi
    done

    # Create configuration and service files for each tunnel
    CONFIG_FILE="/etc/hysteria/iran-${TUNNEL_NAME}.yaml"
    SERVICE_FILE="/etc/systemd/system/hysteria-${TUNNEL_NAME}.service"

    cat << EOF | sudo tee "$CONFIG_FILE" > /dev/null
server: "$SERVER_ADDRESS:$PORT"
auth: "$PASSWORD"
tls:
  sni: "$SNI"
  insecure: true
$(echo "$OBFS_CONFIG" | sed "s/__REPLACE_PASSWORD__/$PASSWORD/")
$(echo "$QUIC_SETTINGS")
tcpForwarding:
$TCP_FORWARD
udpForwarding:
$UDP_FORWARD
EOF

    cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Hysteria2 Client ${TUNNEL_NAME}
After=network.target

[Service]
Type=simple
User=hysteria
Group=hysteria
ExecStart=/usr/local/bin/hysteria client -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=file:/var/log/hysteria/hysteria-${TUNNEL_NAME}.log
StandardError=file:/var/log/hysteria/hysteria-${TUNNEL_NAME}.err

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "hysteria-${TUNNEL_NAME}"
    sudo systemctl reload-or-restart "hysteria-${TUNNEL_NAME}"

    
    # Add cron job for each tunnel

    echo "iran-${TUNNEL_NAME}.yaml|hysteria-${TUNNEL_NAME}|${FORWARDED_PORTS}" \
    | sudo tee -a "$MAPPING_FILE" > /dev/null
    # Re-setup iptables rules to include new tunnel
    sudo /etc/hysteria/setup_iptables.sh
    colorEcho "Tunnel '${TUNNEL_NAME}' setup completed." green
  done

# --- Install Web Management Interface ---
colorEcho "Setting up Web Management Interface on port 3388..." cyan

# Install Python dependencies using apt (avoids externally-managed-environment error)
sudo apt-get update -qq
sudo apt-get install -y python3-flask python3-yaml >/dev/null 2>&1

# Copy web manager files
if [ -f "web_manager.py" ]; then
  sudo cp web_manager.py /etc/hysteria/
  sudo chmod +x /etc/hysteria/web_manager.py
fi

# Create systemd service for web manager
if [ -f "hysteria-web.service" ]; then
  sudo cp hysteria-web.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable hysteria-web
  sudo systemctl start hysteria-web
fi

sudo systemctl daemon-reload

  colorEcho "All tunnels set up successfully." green
  colorEcho "Web Management Interface is available at http://YOUR_SERVER_IP:3388" green
else
  colorEcho "Invalid server type. Please enter 'Iran' or 'Foreign'." red
  exit 1
fi
