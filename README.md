# 🖥️ Virtual DSM – Automatisches Setup-Script für ARM64

Dieses Shell-Script richtet einen Debian/Ubuntu-Server automatisiert und interaktiv für **Virtual DSM (Synology DSM in Docker)** ein – optimiert für ARM64-Architekturen.

> Basierend auf: [github.com/vdsm/virtual-dsm](https://github.com/vdsm/virtual-dsm)

---

## ⚠️ Voraussetzungen

- Betriebssystem: **Debian / Ubuntu** (ARM64)
- Root-Rechte (`sudo` oder direkt als `root`)
- Aktive Internetverbindung

---

## ✨ Features

- **Docker & Docker Compose** – automatische Erkennung und Installation falls nicht vorhanden
- **Interaktive Konfiguration** von:
  - CPU-Kerne (mit Erkennung des Maximums)
  - RAM-Größe
  - Bis zu 3 Festplatten – **dynamisch wachsend (sparse)**, belegen nur genutzten Speicher
  - GPU-Passthrough (Intel, falls `/dev/dri` vorhanden)
  - Web-UI Port
  - Container-Name
  - Eigene IP via macvlan
  - DSM-Version (Standard 7.2 oder eigene `.pat`-URL)
- **KVM-Erkennung** – compose.yml wird automatisch angepasst (kein `/dev/kvm`-Fehler)
- **Automatische `compose.yml`-Generierung**
- **Live-Log** am Ende optional anzeigbar (Installationsfortschritt von DSM sichtbar)
- Übersichtliche **Zusammenfassung** vor dem Start

---

## 🛠️ Installation

```bash
# Script herunterladen
wget https://raw.githubusercontent.com/ra5on/vdsm/refs/heads/main/setup.sh)

# Ausführbar machen
chmod +x setup.sh

# Starten
sudo ./setup.sh
```

---

## 🧾 Ablauf

Das Script führt dich Schritt für Schritt durch die Einrichtung:

| Schritt | Beschreibung |
|---------|-------------|
| 1 | Docker & Docker Compose prüfen / installieren |
| 2 | KVM-Verfügbarkeit prüfen |
| 3 | CPU-Kerne konfigurieren |
| 4 | RAM-Größe konfigurieren |
| 5 | Festplatten konfigurieren (bis zu 3, sparse/dynamisch) |
| 6 | GPU-Passthrough (optional) |
| 7 | Netzwerk, Port & weitere Optionen |
| 8 | Zusammenfassung & Bestätigung |
| 9 | `compose.yml` generieren & Container starten |
| 10 | Optional: Installations-Log live verfolgen |

---

## 🖥️ Beispielhafte Ausgabe

```
╔══════════════════════════════════════════════════════╗
║        Virtual DSM Setup  –  ARM64                   ║
║        Basierend auf: github.com/vdsm/virtual-dsm    ║
╚══════════════════════════════════════════════════════╝

[1/6] Voraussetzungen prüfen …
  ✔  Docker gefunden: Docker version 27.x.x
  ✔  Docker Compose Plugin gefunden
  ✔  KVM verfügbar

════════════════ Zusammenfassung ════════════════
  Container-Name : dsm
  CPU-Kerne      : 4
  RAM            : 4G
  Disk 1         : 256G  →  /home/user/dsm
  GPU            : N
  Web-Port       : 5000

✅  Virtual DSM läuft!
👉  http://192.168.1.x:5000
```

---

## 💾 Festplatten-Hinweis

Die Disk-Images sind **sparse files** – sie belegen beim Erstellen nur wenige MB und wachsen dynamisch mit den tatsächlich gespeicherten Daten bis zur konfigurierten Maximalgröße.

Ein eingestelltes `DISK_SIZE: "256G"` verbraucht also **nicht sofort 256 GB** auf der Host-Festplatte.

---

## 🔧 Nützliche Befehle nach der Installation

```bash
# DSM-Installationsfortschritt live beobachten
docker logs -f dsm

# Container stoppen
docker compose -f compose.yml down

# Container neu starten
docker compose -f compose.yml up -d

# Container-Status
docker ps
```

---

## ❓ KVM nicht verfügbar?

Falls `/dev/kvm` nicht vorhanden ist, startet das Script trotzdem fehlerfrei. Die `compose.yml` wird automatisch **ohne** die Einträge `devices` und `cap_add: NET_ADMIN` generiert. DSM läuft dann ohne Hardware-Beschleunigung (etwas langsamer bei der Installation).

Um KVM zu aktivieren, prüfe:
- ob Virtualisierung im BIOS aktiviert ist (`Intel VT-x` / `ARM virtualization`)
- ob du in einer VM bist → „Nested Virtualization" aktivieren
- `sudo apt install cpu-checker && sudo kvm-ok`

---

## ⚖️ Haftungsausschluss

Dieses Script wird **ohne jegliche Garantie** bereitgestellt und dient ausschließlich zu Lern-, Test- und Demonstrationszwecken. Die Ausführung erfolgt auf eigene Gefahr.

> **Wichtiger Hinweis zu Virtual DSM:**  
> Die Endbenutzer-Lizenzvereinbarung von Synology **verbietet** den Einsatz auf Nicht-Synology-Hardware.  
> Verwende diesen Container ausschließlich auf offiziellen Synology NAS-Systemen.

Alle Rechte, Marken und Verantwortlichkeiten der eingesetzten Drittsoftware (Docker, Synology DSM usw.) verbleiben bei den jeweiligen Rechteinhabern.
