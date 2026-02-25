#!/bin/bash
# ============================================================
#  Virtual DSM – Interaktives Setup-Script (ARM64)
#  https://github.com/vdsm/virtual-dsm
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Virtual DSM Setup  –  ARM64                   ║"
echo "║        Basierend auf: github.com/vdsm/virtual-dsm    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Hilfsfunktionen ──────────────────────────────────────────

ask() {
  # ask <variable> <frage> <default>
  local __var=$1 __prompt=$2 __default=$3
  echo -e "${YELLOW}${__prompt}${NC} [${__default}]: "
  read -r __input
  __input="${__input:-$__default}"
  eval "$__var=\"$__input\""
}

ask_yn() {
  local __var=$1 __prompt=$2 __default=$3
  echo -e "${YELLOW}${__prompt}${NC} (j/n) [${__default}]: "
  read -r __input
  __input="${__input:-$__default}"
  [[ "$__input" =~ ^[jJyY]$ ]] && eval "$__var=Y" || eval "$__var=N"
}

# ── Docker installieren ───────────────────────────────────────

install_docker() {
  echo -e "  ${YELLOW}➜${NC}  Docker wird installiert (offizielle Methode) …"

  # Alte Pakete entfernen
  for pkg in docker docker-engine docker.io containerd runc; do
    sudo apt-get remove -y "$pkg" &>/dev/null || true
  done

  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    ca-certificates curl gnupg lsb-release

  # GPG-Schlüssel
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Repository hinzufügen
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Aktuellen User zur docker-Gruppe hinzufügen (kein sudo nötig)
  sudo usermod -aG docker "$USER" 2>/dev/null || true

  # Dienst starten
  sudo systemctl enable --now docker

  echo -e "  ${GREEN}✔${NC}  Docker installiert: $(docker --version)"
}

# ── Docker Compose (Plugin) installieren ─────────────────────

install_compose() {
  echo -e "  ${YELLOW}➜${NC}  Docker Compose Plugin wird installiert …"
  sudo apt-get install -y -qq docker-compose-plugin
  echo -e "  ${GREEN}✔${NC}  Docker Compose installiert: $(docker compose version)"
}

# ── Voraussetzungen prüfen ────────────────────────────────────

echo -e "${BOLD}[1/6] Voraussetzungen prüfen …${NC}"

# Root / sudo prüfen
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  Sudo-Rechte werden für die Installation benötigt."
  sudo -v || { echo -e "  ${RED}✘${NC}  Sudo fehlgeschlagen. Bitte als root ausführen."; exit 1; }
fi

# ── Docker prüfen / installieren ─────────────────────────────
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version 2>&1)
  echo -e "  ${GREEN}✔${NC}  Docker gefunden: ${DOCKER_VER}"
else
  echo -e "  ${RED}✘${NC}  Docker nicht gefunden."
  ask_yn INSTALL_DOCKER "Docker jetzt automatisch installieren?" "j"
  if [ "$INSTALL_DOCKER" = "Y" ]; then
    install_docker
  else
    echo -e "  ${RED}Abbruch:${NC} Docker wird benötigt. Bitte manuell installieren."
    exit 1
  fi
fi

# ── Docker Compose prüfen / installieren ─────────────────────
# Prüfe zuerst neues Plugin (docker compose), dann altes Binary (docker-compose)
COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  echo -e "  ${GREEN}✔${NC}  Docker Compose Plugin gefunden: $(docker compose version)"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
  echo -e "  ${GREEN}✔${NC}  docker-compose gefunden: $(docker-compose --version)"
else
  echo -e "  ${RED}✘${NC}  Docker Compose nicht gefunden."
  ask_yn INSTALL_COMPOSE "Docker Compose Plugin jetzt installieren?" "j"
  if [ "$INSTALL_COMPOSE" = "Y" ]; then
    install_compose
    COMPOSE_CMD="docker compose"
  else
    echo -e "  ${RED}Abbruch:${NC} Docker Compose wird benötigt."
    exit 1
  fi
fi

# ── Docker-Dienst läuft? ──────────────────────────────────────
if ! docker info &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  Docker-Daemon läuft nicht – versuche zu starten …"
  sudo systemctl start docker || { echo -e "  ${RED}✘${NC}  Docker konnte nicht gestartet werden."; exit 1; }
  echo -e "  ${GREEN}✔${NC}  Docker-Daemon gestartet."
fi

# ── KVM prüfen ────────────────────────────────────────────────
if [ -e /dev/kvm ]; then
  KVM_AVAILABLE=Y
  echo -e "  ${GREEN}✔${NC}  KVM verfügbar"
else
  KVM_AVAILABLE=N
  echo -e "  ${YELLOW}⚠${NC}  /dev/kvm nicht gefunden – Container läuft ohne KVM-Beschleunigung (langsamer)."
fi
echo ""

# ── CPU ──────────────────────────────────────────────────────

echo -e "${BOLD}[2/6] CPU-Konfiguration${NC}"
CORES_MAX=$(nproc)
ask CPU_CORES "Anzahl CPU-Kerne (max. ${CORES_MAX})" "2"
echo ""

# ── RAM ──────────────────────────────────────────────────────

echo -e "${BOLD}[3/6] RAM-Konfiguration${NC}"
RAM_TOTAL=$(awk '/MemTotal/{printf "%dG", $2/1024/1024}' /proc/meminfo)
ask RAM_SIZE "RAM-Größe (verfügbar: ~${RAM_TOTAL}, z.B. 2G, 4G, 8G)" "2G"
echo ""

# ── Festplatten ───────────────────────────────────────────────

echo -e "${BOLD}[4/6] Festplatten-Konfiguration${NC}"
echo -e "  ${CYAN}Hinweis: Die Disk-Images wachsen dynamisch (sparse) und belegen"
echo -e "  nur so viel Platz, wie tatsächlich genutzt wird.${NC}"
echo ""

ask STORAGE_PATH "Speicherort für DSM-Daten (absoluter Pfad)" "$(pwd)/dsm"
ask DISK1_SIZE   "Größe Disk 1 (z.B. 256G)" "256G"

ask_yn ADD_DISK2 "Zweite Disk hinzufügen?" "n"
if [ "$ADD_DISK2" = "Y" ]; then
  ask DISK2_PATH "Speicherort Disk 2" "$(pwd)/dsm2"
  ask DISK2_SIZE "Größe Disk 2"       "256G"
fi

ask_yn ADD_DISK3 "Dritte Disk hinzufügen?" "n"
if [ "$ADD_DISK3" = "Y" ]; then
  ask DISK3_PATH "Speicherort Disk 3" "$(pwd)/dsm3"
  ask DISK3_SIZE "Größe Disk 3"       "256G"
fi
echo ""

# ── GPU ───────────────────────────────────────────────────────

echo -e "${BOLD}[5/6] GPU-Konfiguration${NC}"
if [ -e /dev/dri ]; then
  ask_yn GPU_PASSTHROUGH "Intel GPU durchreichen? (/dev/dri vorhanden)" "n"
else
  GPU_PASSTHROUGH=N
  echo -e "  ${YELLOW}⚠${NC}  /dev/dri nicht gefunden – GPU-Passthrough übersprungen."
fi
echo ""

# ── Netzwerk & Port ───────────────────────────────────────────

echo -e "${BOLD}[6/6] Netzwerk & sonstige Optionen${NC}"
ask WEB_PORT    "Web-UI Port (DSM läuft hier)" "5000"
ask CONTAINER_NAME "Container-Name" "dsm"

ask_yn USE_MACVLAN "Eigene IP via macvlan vergeben?" "n"
if [ "$USE_MACVLAN" = "Y" ]; then
  ask MACVLAN_SUBNET  "Subnet (z.B. 192.168.1.0/24)"    "192.168.1.0/24"
  ask MACVLAN_GATEWAY "Gateway (z.B. 192.168.1.1)"       "192.168.1.1"
  ask MACVLAN_IP      "IP für DSM-Container"              "192.168.1.200"
  ask MACVLAN_PARENT  "Netzwerk-Interface (z.B. eth0)"    "eth0"
fi

ask DSM_URL "DSM-Version (leer = Standard 7.2, sonst .pat-URL)" ""
echo ""

# ── Zusammenfassung ───────────────────────────────────────────

echo -e "${CYAN}${BOLD}════════════════ Zusammenfassung ════════════════${NC}"
echo -e "  Container-Name : ${BOLD}${CONTAINER_NAME}${NC}"
echo -e "  CPU-Kerne      : ${BOLD}${CPU_CORES}${NC}"
echo -e "  RAM            : ${BOLD}${RAM_SIZE}${NC}"
echo -e "  Disk 1         : ${BOLD}${DISK1_SIZE}${NC}  →  ${STORAGE_PATH}"
[ "$ADD_DISK2" = "Y" ] && echo -e "  Disk 2         : ${BOLD}${DISK2_SIZE}${NC}  →  ${DISK2_PATH}"
[ "$ADD_DISK3" = "Y" ] && echo -e "  Disk 3         : ${BOLD}${DISK3_SIZE}${NC}  →  ${DISK3_PATH}"
echo -e "  GPU            : ${BOLD}${GPU_PASSTHROUGH}${NC}"
echo -e "  Web-Port       : ${BOLD}${WEB_PORT}${NC}"
[ -n "$DSM_URL" ] && echo -e "  DSM URL        : ${BOLD}${DSM_URL}${NC}"
echo ""

read -r -p "$(echo -e "${GREEN}Alles korrekt? Setup starten? (j/n):${NC} ")" CONFIRM
[[ "$CONFIRM" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
echo ""

# ── compose.yml generieren ────────────────────────────────────

echo -e "${BOLD}compose.yml wird erstellt …${NC}"

COMPOSE_FILE="$(pwd)/compose.yml"

{
cat <<EOF
services:
  ${CONTAINER_NAME}:
    container_name: ${CONTAINER_NAME}
    image: vdsm/virtual-dsm
    environment:
      CPU_CORES: "${CPU_CORES}"
      RAM_SIZE: "${RAM_SIZE}"
      DISK_SIZE: "${DISK1_SIZE}"
EOF

[ "$ADD_DISK2" = "Y" ] && echo "      DISK2_SIZE: \"${DISK2_SIZE}\""
[ "$ADD_DISK3" = "Y" ] && echo "      DISK3_SIZE: \"${DISK3_SIZE}\""
[ "$GPU_PASSTHROUGH" = "Y" ] && echo "      GPU: \"Y\""
[ -n "$DSM_URL" ] && echo "      URL: \"${DSM_URL}\""

if [ "$KVM_AVAILABLE" = "Y" ] || [ "$GPU_PASSTHROUGH" = "Y" ]; then
  echo "    devices:"
  [ "$KVM_AVAILABLE" = "Y" ]   && echo "      - /dev/kvm"
  [ "$KVM_AVAILABLE" = "Y" ]   && echo "      - /dev/net/tun"
  [ "$GPU_PASSTHROUGH" = "Y" ] && echo "      - /dev/dri"
fi

if [ "$KVM_AVAILABLE" = "Y" ]; then
  echo "    cap_add:"
  echo "      - NET_ADMIN"
fi

cat <<EOF
    ports:
      - ${WEB_PORT}:5000
    volumes:
      - ${STORAGE_PATH}:/storage
EOF

[ "$ADD_DISK2" = "Y" ] && echo "      - ${DISK2_PATH}:/storage2"
[ "$ADD_DISK3" = "Y" ] && echo "      - ${DISK3_PATH}:/storage3"

cat <<EOF
    restart: always
    stop_grace_period: 2m
EOF

if [ "$USE_MACVLAN" = "Y" ]; then
cat <<EOF
    networks:
      vdsm_net:
        ipv4_address: ${MACVLAN_IP}

networks:
  vdsm_net:
    driver: macvlan
    driver_opts:
      parent: ${MACVLAN_PARENT}
    ipam:
      config:
        - subnet: ${MACVLAN_SUBNET}
          gateway: ${MACVLAN_GATEWAY}
EOF
fi

} > "$COMPOSE_FILE"

echo -e "  ${GREEN}✔${NC}  compose.yml erstellt: ${COMPOSE_FILE}"
echo ""

# ── Verzeichnisse anlegen ─────────────────────────────────────

mkdir -p "$STORAGE_PATH"
[ "$ADD_DISK2" = "Y" ] && mkdir -p "$DISK2_PATH"
[ "$ADD_DISK3" = "Y" ] && mkdir -p "$DISK3_PATH"
echo -e "  ${GREEN}✔${NC}  Storage-Verzeichnisse angelegt."
echo ""

# ── Docker Image pullen & starten ─────────────────────────────

echo -e "${BOLD}Docker Image wird geladen …${NC}"
docker pull vdsm/virtual-dsm

echo ""
echo -e "${BOLD}Container wird gestartet …${NC}"
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗"
echo -e "║  ✅  Virtual DSM läuft!                               ║"
echo -e "║                                                       ║"
echo -e "║  👉  http://$(hostname -I | awk '{print $1}'):${WEB_PORT}                         ║"
echo -e "║                                                       ║"
echo -e "║  Warte ca. 5–10 Minuten bis DSM installiert ist.     ║"
echo -e "╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Logs anzeigen  : ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
echo -e "  Stoppen        : ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} down${NC}"
echo -e "  Neu starten    : ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d${NC}"
echo ""

# ── Logs anzeigen? ────────────────────────────────────────────

ask_yn SHOW_LOGS "Installationsfortschritt live mitverfolgen? (Logs anzeigen)" "j"
if [ "$SHOW_LOGS" = "Y" ]; then
  echo ""
  echo -e "${CYAN}${BOLD}══════════════ DSM Installations-Log ══════════════${NC}"
  echo -e "${YELLOW}  Zum Beenden: Strg+C  (Container läuft weiter im Hintergrund)${NC}"
  echo ""
  trap 'echo -e "\n${GREEN}✔  Log geschlossen. Container läuft weiter.${NC}\n"' INT
  docker logs -f "$CONTAINER_NAME"
  trap - INT
fi
echo ""
