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

if [ ! -f /etc/hysteria/hysteria-monitor.py ]; then
  sudo curl -fsSL https://raw.githubusercontent.com/ParsaKSH/TAQ-BOSTAN/main/hysteria-monitor.py \
    -o /etc/hysteria/hysteria-monitor.py
  sudo chmod +x /etc/hysteria/hysteria-monitor.py
fi

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
  <title>ورود - مدیریت Hysteria</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
      min-height: 100vh;
      padding: 40px 20px;
      color: #e5e7eb;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .login-card {
      background: rgba(31, 41, 55, 0.95);
      border-radius: 20px;
      padding: 40px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1);
      backdrop-filter: blur(10px);
      border: 1px solid rgba(102, 126, 234, 0.2);
      width: 100%;
      max-width: 400px;
    }
    h1 {
      text-align: center;
      color: #ffffff;
      margin-bottom: 30px;
      text-shadow: 0 0 20px rgba(102, 126, 234, 0.5);
      font-size: 1.8rem;
    }
    .form-group {
      margin-bottom: 20px;
    }
    label {
      display: block;
      margin-bottom: 8px;
      font-weight: 600;
      font-size: 14px;
    }
    input {
      width: 100%;
      padding: 12px 16px;
      border-radius: 10px;
      border: 1px solid rgba(102, 126, 234, 0.3);
      background: rgba(17, 24, 39, 0.8);
      color: white;
      font-size: 16px;
    }
    input:focus {
      outline: none;
      border-color: rgba(102, 126, 234, 0.8);
      box-shadow: 0 0 15px rgba(102, 126, 234, 0.3);
    }
    .btn {
      width: 100%;
      padding: 14px;
      border: none;
      border-radius: 10px;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      background: linear-gradient(135deg, #667eea, #764ba2);
      color: white;
    }
    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(102, 126, 234, 0.5);
    }
    .error {
      color: #ef4444;
      text-align: center;
      margin-bottom: 20px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="login-card">
    <h1>🔐 ورود به مدیریت</h1>
    {% if error %}
    <p class="error">{{ error }}</p>
    {% endif %}
    <form method="post" action="{{ url_for('login') }}">
      <div class="form-group">
        <label for="username">نام کاربری</label>
        <input type="text" id="username" name="username" required autofocus>
      </div>
      <div class="form-group">
        <label for="password">رمز عبور</label>
        <input type="password" id="password" name="password" required>
      </div>
      <button type="submit" class="btn">ورود</button>
    </form>
    <p style="text-align: center; margin-top: 20px; color: #9ca3af; font-size: 12px;">
      نام کاربری پیش‌فرض: admin | رمز عبور: admin123
    </p>
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
  <title>مدیریت Hysteria</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
      min-height: 100vh;
      padding: 20px;
      color: #e5e7eb;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 30px;
      padding: 15px 25px;
      background: rgba(31, 41, 55, 0.95);
      border-radius: 15px;
      border: 1px solid rgba(102, 126, 234, 0.2);
    }
    h1 {
      text-align: center;
      color: #ffffff;
      text-shadow: 0 0 20px rgba(102, 126, 234, 0.5);
      font-size: 2rem;
    }
    .user-info {
      display: flex;
      gap: 15px;
      align-items: center;
    }
    .user-info span {
      font-weight: 600;
    }
    .btn-small {
      padding: 8px 16px;
      border: none;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      background: linear-gradient(135deg, #ef4444, #dc2626);
      color: white;
    }
    .btn-small:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 15px rgba(239, 68, 68, 0.4);
    }
    .btn-nav {
      padding: 8px 16px;
      border: none;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      background: linear-gradient(135deg, #667eea, #764ba2);
      color: white;
      text-decoration: none;
      display: inline-block;
    }
    .btn-nav:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
    }
    .card {
      background: rgba(31, 41, 55, 0.95);
      border-radius: 20px;
      padding: 30px;
      margin-bottom: 25px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1);
      backdrop-filter: blur(10px);
      border: 1px solid rgba(102, 126, 234, 0.2);
    }
    .tunnel {
      border-left: 5px solid #667eea;
      margin-bottom: 25px;
      padding: 25px;
      background: rgba(55, 65, 81, 0.6);
      border-radius: 15px;
      transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
      position: relative;
      overflow: hidden;
    }
    .tunnel::before {
      content: '';
      position: absolute;
      top: 0;
      left: -100%;
      width: 100%;
      height: 100%;
      background: linear-gradient(90deg, transparent, rgba(102, 126, 234, 0.1), transparent);
      transition: left 0.6s;
    }
    .tunnel:hover::before {
      left: 100%;
    }
    .tunnel:hover {
      transform: translateY(-5px);
      box-shadow: 0 15px 40px rgba(102, 126, 234, 0.3);
    }
    .tunnel.active {
      border-left-color: #10b981;
      background: rgba(16, 185, 129, 0.15);
    }
    .tunnel.inactive {
      border-left-color: #ef4444;
      background: rgba(239, 68, 68, 0.15);
    }
    .tunnel-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;
    }
    .tunnel-name {
      font-size: 28px;
      font-weight: 900;
      color: #ffffff;
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .status-badge {
      padding: 8px 20px;
      border-radius: 25px;
      font-weight: 800;
      font-size: 14px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      box-shadow: 0 4px 15px rgba(0,0,0,0.3);
    }
    .status-badge.active {
      background: linear-gradient(135deg, #10b981, #059669);
      color: white;
    }
    .status-badge.inactive {
      background: linear-gradient(135deg, #ef4444, #dc2626);
      color: white;
    }
    .tunnel-info {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 18px;
      margin-bottom: 20px;
    }
    .info-item {
      background: rgba(17, 24, 39, 0.8);
      padding: 18px;
      border-radius: 12px;
      border: 1px solid rgba(102, 126, 234, 0.3);
      transition: all 0.3s;
    }
    .info-item:hover {
      border-color: rgba(102, 126, 234, 0.8);
      transform: scale(1.02);
    }
    .info-label {
      font-size: 13px;
      color: #9ca3af;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      font-weight: 600;
    }
    .info-value {
      font-size: 18px;
      font-weight: 700;
      color: #ffffff;
    }
    .ports {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 15px;
    }
    .port-tag {
      background: linear-gradient(135deg, #667eea, #764ba2);
      color: white;
      padding: 6px 16px;
      border-radius: 15px;
      font-size: 14px;
      font-weight: 600;
      box-shadow: 0 4px 10px rgba(102, 126, 234, 0.4);
      transition: all 0.3s;
    }
    .port-tag:hover {
      transform: scale(1.1);
      box-shadow: 0 6px 15px rgba(102, 126, 234, 0.6);
    }
    .actions {
      display: flex;
      gap: 12px;
      margin-top: 20px;
      flex-wrap: wrap;
    }
    .btn {
      padding: 12px 24px;
      border: none;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      box-shadow: 0 4px 15px rgba(0,0,0,0.3);
      text-decoration: none;
      display: inline-block;
    }
    .btn-start {
      background: linear-gradient(135deg, #10b981, #059669);
      color: white;
    }
    .btn-stop {
      background: linear-gradient(135deg, #ef4444, #dc2626);
      color: white;
    }
    .btn-restart {
      background: linear-gradient(135deg, #f59e0b, #d97706);
      color: white;
    }
    .btn:hover {
      transform: translateY(-3px) scale(1.05);
      box-shadow: 0 8px 25px rgba(0,0,0,0.4);
    }
    .logs-section {
      background: rgba(0, 0, 0, 0.7);
      color: #10b981;
      padding: 25px;
      border-radius: 12px;
      margin-top: 20px;
      font-family: 'Courier New', Courier, monospace;
      max-height: 350px;
      overflow-y: auto;
      text-align: left;
      direction: ltr;
      border: 1px solid rgba(102, 126, 234, 0.3);
    }
    .refresh-toggle {
      display: flex;
      justify-content: center;
      margin-bottom: 25px;
      gap: 10px;
      align-items: center;
    }
    .refresh-toggle label {
      font-size: 16px;
      font-weight: 600;
    }
    .refresh-toggle select {
      padding: 8px 16px;
      border-radius: 8px;
      border: 1px solid rgba(102, 126, 234, 0.5);
      background: rgba(31, 41, 55, 0.9);
      color: white;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎯 مدیریت Hysteria</h1>
      <div class="user-info">
        <span>{{ username }}</span>
        {% if is_admin %}
        <a href="{{ url_for('admin_panel') }}" class="btn-nav">👥 مدیریت کاربران</a>
        {% endif %}
        <a href="{{ url_for('logout') }}" class="btn-small">🚪 خروج</a>
      </div>
    </div>

    <div style="text-align: center; margin-bottom: 20px;">
      <button id="speedtest-btn" class="btn" style="background: linear-gradient(135deg, #10b981, #059669);">
        🚀 تست سرعت
      </button>
      <div id="speedtest-result" style="margin-top: 10px; color: #e5e7eb;"></div>
    </div>

    <div class="refresh-toggle">
      <label for="refresh-interval">فاصله زمانی به‌روزرسانی:</label>
      <select id="refresh-interval" onchange="updateRefreshInterval()">
        <option value="5">5 ثانیه</option>
        <option value="10" selected>10 ثانیه</option>
        <option value="30">30 ثانیه</option>
        <option value="60">1 دقیقه</option>
        <option value="0">خاموش</option>
      </select>
    </div>

    <div class="card">
      <h2 style="margin-bottom:20px;color:#e5e7eb;">لیست تانل‌ها</h2>
      {% for tunnel in tunnels %}
      <div class="tunnel {{ tunnel.status }}">
        <div class="tunnel-header">
          <span class="tunnel-name">{{ tunnel.name }}</span>
          <span class="status-badge {{ tunnel.status }}">{{ tunnel.status_text }}</span>
        </div>
        <div class="tunnel-info">
          <div class="info-item">
            <div class="info-label">سرور</div>
            <div class="info-value">{{ tunnel.server }}</div>
          </div>
          <div class="info-item">
            <div class="info-label">SNI</div>
            <div class="info-value">{{ tunnel.sni }}</div>
          </div>
          <div class="info-item">
            <div class="info-label">ترافیک مصرفی</div>
            <div class="info-value">{{ tunnel.traffic }}</div>
          </div>
        </div>
        <div>
          <div class="info-label" style="margin-bottom:5px;">پورت‌های TCP</div>
          <div class="ports">
            {% for port in tunnel.tcp_ports %}
            <span class="port-tag">{{ port }}</span>
            {% endfor %}
          </div>
        </div>
        <div style="margin-top:10px;">
          <div class="info-label" style="margin-bottom:5px;">پورت‌های UDP</div>
          <div class="ports">
            {% for port in tunnel.udp_ports %}
            <span class="port-tag">{{ port }}</span>
            {% endfor %}
          </div>
        </div>
        {% if is_admin %}
        <div class="actions">
          {% if tunnel.status == 'inactive' %}
          <a href="{{ url_for('start_tunnel', name=tunnel.name) }}" class="btn btn-start">▶️ شروع</a>
          {% else %}
          <a href="{{ url_for('stop_tunnel', name=tunnel.name) }}" class="btn btn-stop">⏹️ توقف</a>
          {% endif %}
          <a href="{{ url_for('restart_tunnel', name=tunnel.name) }}" class="btn btn-restart">🔄 ری‌استارت</a>
          <a href="{{ url_for('view_logs', name=tunnel.name) }}" class="btn" style="background:linear-gradient(135deg, #667eea, #764ba2);color:white;">📋 لاگ‌ها</a>
          <a href="{{ url_for('reset_traffic', name=tunnel.name) }}" class="btn" style="background:linear-gradient(135deg, #8b5cf6, #7c3aed);color:white;">🔢 ریست ترافیک</a>
        </div>
        {% endif %}
        {% if is_admin and tunnel.show_logs %}
        <div class="logs-section">{{ tunnel.logs }}</div>
        {% endif %}
      </div>
      {% endfor %}
      {% if not tunnels %}
      <div style="text-align:center;color:#9ca3af;margin-top:30px;">
        <p>هیچ تانلی یافت نشد!</p>
      </div>
      {% endif %}
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

    async function runSpeedTest() {
      const btn = document.getElementById('speedtest-btn');
      const resultDiv = document.getElementById('speedtest-result');
      
      btn.disabled = true;
      btn.textContent = '⏳ در حال تست...';
      resultDiv.textContent = '';

      try {
        const response = await fetch('/speedtest');
        const result = await response.text();
        resultDiv.textContent = result;
      } catch (error) {
        resultDiv.textContent = 'خطا در تست سرعت: ' + error.message;
      } finally {
        btn.disabled = false;
        btn.textContent = '🚀 تست سرعت';
      }
    }

    document.addEventListener('DOMContentLoaded', () => {
      updateRefreshInterval();
      document.getElementById('speedtest-btn').addEventListener('click', runSpeedTest);
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
  <title>مدیریت کاربران - Hysteria</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
      min-height: 100vh;
      padding: 20px;
      color: #e5e7eb;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 30px;
      padding: 15px 25px;
      background: rgba(31, 41, 55, 0.95);
      border-radius: 15px;
      border: 1px solid rgba(102, 126, 234, 0.2);
    }
    h1, h2 {
      color: #ffffff;
      text-shadow: 0 0 20px rgba(102, 126, 234, 0.5);
    }
    .btn-back {
      padding: 10px 20px;
      border: none;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      background: linear-gradient(135deg, #667eea, #764ba2);
      color: white;
      text-decoration: none;
      display: inline-block;
    }
    .btn-back:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(102, 126, 234, 0.5);
    }
    .card {
      background: rgba(31, 41, 55, 0.95);
      border-radius: 20px;
      padding: 30px;
      margin-bottom: 25px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1);
      backdrop-filter: blur(10px);
      border: 1px solid rgba(102, 126, 234, 0.2);
    }
    .form-group {
      margin-bottom: 15px;
    }
    label {
      display: block;
      margin-bottom: 8px;
      font-weight: 600;
    }
    input, select {
      width: 100%;
      padding: 10px 15px;
      border-radius: 10px;
      border: 1px solid rgba(102, 126, 234, 0.3);
      background: rgba(17, 24, 39, 0.8);
      color: white;
      font-size: 15px;
    }
    input:focus, select:focus {
      outline: none;
      border-color: rgba(102, 126, 234, 0.8);
    }
    .btn {
      padding: 12px 24px;
      border: none;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.3s;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      background: linear-gradient(135deg, #10b981, #059669);
      color: white;
    }
    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(16, 185, 129, 0.5);
    }
    .btn-danger {
      background: linear-gradient(135deg, #ef4444, #dc2626);
    }
    .btn-danger:hover {
      box-shadow: 0 8px 25px rgba(239, 68, 68, 0.5);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 25px;
    }
    th, td {
      padding: 14px 15px;
      text-align: right;
      border-bottom: 1px solid rgba(102, 126, 234, 0.2);
    }
    th {
      background: rgba(17, 24, 39, 0.9);
      font-weight: 700;
    }
    .tunnel-checkboxes {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
      gap: 10px;
      margin-top: 10px;
    }
    .checkbox-item {
      background: rgba(17, 24, 39, 0.8);
      padding: 10px;
      border-radius: 8px;
      border: 1px solid rgba(102, 126, 234, 0.2);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>👥 مدیریت کاربران</h1>
      <a href="{{ url_for('index') }}" class="btn-back">← بازگشت</a>
    </div>

    <div class="card">
      <h2>ایجاد کاربر جدید</h2>
      <form method="post" action="{{ url_for('create_user') }}">
        <div class="form-group">
          <label for="new_username">نام کاربری</label>
          <input type="text" id="new_username" name="username" required>
        </div>
        <div class="form-group">
          <label for="new_password">رمز عبور</label>
          <input type="password" id="new_password" name="password" required>
        </div>
        <div class="form-group">
          <label for="is_admin">ادمین است؟</label>
          <select id="is_admin" name="is_admin">
            <option value="0">خیر</option>
            <option value="1">بله</option>
          </select>
        </div>
        <div class="form-group">
          <label>تخصیص تانل‌ها (در صورت نیاز):</label>
          <div class="tunnel-checkboxes">
            {% for tunnel in all_tunnels %}
            <label class="checkbox-item">
              <input type="checkbox" name="tunnels" value="{{ tunnel }}">
              {{ tunnel }}
            </label>
            {% endfor %}
          </div>
        </div>
        <button type="submit" class="btn">✨ ایجاد کاربر</button>
      </form>
    </div>

    <div class="card">
      <h2>لیست کاربران</h2>
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
            <td>{{ user.username }}</td>
            <td>{{ 'ادمین' if user.is_admin else 'کاربر' }}</td>
            <td>{{ ', '.join(user.tunnels) if user.tunnels else 'هیچ‌کدام' }}</td>
            <td>
              <form method="post" action="{{ url_for('edit_user', user_id=user.id) }}" style="display:inline-block;">
                <input type="password" name="new_password" placeholder="رمز جدید (اختیاری)" style="width:auto;padding:5px;border-radius:5px;margin-right:5px;">
                <select name="is_admin" style="width:auto;padding:5px;border-radius:5px;margin-right:5px;">
                  <option value="0" {% if not user.is_admin %}selected{% endif %}>کاربر</option>
                  <option value="1" {% if user.is_admin %}selected{% endif %}>ادمین</option>
                </select>
                <div style="margin-top:5px;">
                  <label>تخصیص تانل‌ها:</label>
                  <div class="tunnel-checkboxes">
                    {% for tunnel in all_tunnels %}
                    <label class="checkbox-item">
                      <input type="checkbox" name="tunnels" value="{{ tunnel }}" {% if tunnel in user.tunnels %}checked{% endif %}>
                      {{ tunnel }}
                    </label>
                    {% endfor %}
                  </div>
                </div>
                <button type="submit" class="btn" style="padding:5px 10px;font-size:12px;margin-top:5px;">ویرایش</button>
              </form>
              <form method="post" action="{{ url_for('delete_user', user_id=user.id) }}" style="display:inline-block;">
                <button type="submit" class="btn btn-danger" style="padding:5px 10px;font-size:12px;">حذف</button>
              </form>
            </td>
          </tr>
          {% endfor %}
        </tbody>
      </table>
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
    chain_name = f"HYST{name}"
    result = subprocess.run(
      ["iptables", "-t", "mangle", "-L", chain_name, "-v", "-n", "-x"],
      capture_output=True,
      text=True
    )
    if result.returncode == 0:
      lines = result.stdout.strip().split('\n')
      if len(lines) >= 3:
        parts = lines[2].split()
        if len(parts) >= 2:
          bytes_used = int(parts[1])
          return format_bytes(bytes_used)
  except Exception:
    pass
  return "0 B"

def run_speed_test():
  try:
    # Try to use speedtest-cli if available
    result = subprocess.run(
      ["speedtest-cli", "--simple"],
      capture_output=True,
      text=True,
      timeout=60
    )
    if result.returncode == 0:
      return result.stdout.strip()
    else:
      # Fallback: try a simple download test
      import tempfile
      import time
      test_url = "https://speed.hetzner.de/100MB.bin"
      start_time = time.time()
      with tempfile.NamedTemporaryFile(delete=False) as f:
        subprocess.run(
          ["curl", "-L", "-o", f.name, test_url],
          capture_output=True,
          timeout=60
        )
      download_time = time.time() - start_time
      file_size = 100 * 1024 * 1024  # 100 MB
      speed_bps = (file_size * 8) / download_time
      speed_mbps = speed_bps / (1024 * 1024)
      return f"Download: {speed_mbps:.2f} Mbps"
  except Exception as e:
    return f"Speed test failed: {str(e)}"


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
    chain_name = f"HYST{name}"
    subprocess.run(["iptables", "-t", "mangle", "-Z", chain_name], check=True)
  except Exception:
    pass
  return redirect(url_for('index'))

@app.route('/speedtest')
def speed_test():
  if 'user_id' not in session:
    return redirect(url_for('login'))
  
  # Only admins can run speed tests? Or allow all users? Let's allow all users
  result = run_speed_test()
  return result


if __name__ == '__main__':
  app.run(host='0.0.0.0', port=3388, debug=False)
END_WEB_MGR

  sudo chmod +x /etc/hysteria/web_manager.py

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
  sudo apt-get update -qq
  sudo apt-get install -y python3-flask python3-yaml python3-werkzeug >/dev/null 2>&1

  sudo systemctl daemon-reload
  sudo systemctl enable hysteria-web
  sudo systemctl start hysteria-web

  colorEcho "Web Management Interface installed and started!" green
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
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/server-config.yaml
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=file:/var/log/hysteria.log
StandardError=file:/var/log/hysteria.err

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
ExecStart=/usr/local/bin/hysteria client -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=file:/var/log/hysteria-${TUNNEL_NAME}.log
StandardError=file:/var/log/hysteria-${TUNNEL_NAME}.err

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "hysteria-${TUNNEL_NAME}"
    sudo systemctl reload-or-restart "hysteria-${TUNNEL_NAME}"

    
    # Add cron job for each tunnel

    echo "iran-${TUNNEL_NAME}.yaml|hysteria-${TUNNEL_NAME}|${FORWARDED_PORTS}" \
    | sudo tee -a "$MAPPING_FILE" > /dev/null
    colorEcho "Tunnel '${TUNNEL_NAME}' setup completed." green
  done
# ====== Set up per-config iptables counters ======
while IFS='|' read -r cfg service ports; do
  name="${cfg##*iran-}"
  name="${name%.yaml}"
  chain="HYST${name}"
  sudo iptables -t mangle -N "$chain" 2>/dev/null || sudo iptables -t mangle -F "$chain"
  # Add a rule to count all traffic in this chain
  sudo iptables -t mangle -A "$chain" -j RETURN  # This rule will have the byte counter
  IFS=',' read -ra PARR <<< "$ports"
  for p in "${PARR[@]}"; do
    # Add INPUT and OUTPUT rules for both TCP and UDP, using both --dport and --sport
    sudo iptables -t mangle -A INPUT -p tcp --dport "$p" -j "$chain"
    sudo iptables -t mangle -A INPUT -p tcp --sport "$p" -j "$chain"
    sudo iptables -t mangle -A INPUT -p udp --dport "$p" -j "$chain"
    sudo iptables -t mangle -A INPUT -p udp --sport "$p" -j "$chain"
    sudo iptables -t mangle -A OUTPUT -p tcp --dport "$p" -j "$chain"
    sudo iptables -t mangle -A OUTPUT -p tcp --sport "$p" -j "$chain"
    sudo iptables -t mangle -A OUTPUT -p udp --dport "$p" -j "$chain"
    sudo iptables -t mangle -A OUTPUT -p udp --sport "$p" -j "$chain"
  done
done < "$MAPPING_FILE"

sudo tee /etc/systemd/system/hysteria-monitor.service > /dev/null <<'EOF'
[Unit]
Description=Hysteria Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/hysteria/hysteria-monitor.py
Restart=always
RestartSec=10
StandardOutput=file:/var/log/hysteria/monitor.log
StandardError=file:/var/log/hysteria/monitor.err

[Install]
WantedBy=multi-user.target
EOF

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
sudo systemctl enable hysteria-monitor
sudo systemctl start hysteria-monitor


  colorEcho "All tunnels set up successfully." green
  colorEcho "Web Management Interface is available at http://YOUR_SERVER_IP:3388" green
else
  colorEcho "Invalid server type. Please enter 'Iran' or 'Foreign'." red
  exit 1
fi
