# LVM Volume Management Script - README

## 📋 Übersicht

Das **LVM Management Script** ist ein umfassendes Tool zur Verwaltung von Logical Volume Manager (LVM) Partitionen auf Linux-Systemen. Es wurde speziell für PBS (Proxmox Backup Server) Speicher-Verkauf und flexible Partitionsverwaltung entwickelt.

**Hauptzweck:** Flexible Speicherverwaltung für Kunden - jeder Kunde bekommt sein eigenes Logical Volume mit individueller Größe, das jederzeit vergrößert oder verkleinert werden kann.

---

## 🚀 Installation

### 1. Script herunterladen/erstellen
```bash
# Script erstellen
nano lvm-manage.sh
# (Inhalt einfügen)

# Oder direkt von GitHub/Server herunterladen
```

### 2. Ausführbar machen
```bash
chmod +x lvm-manage.sh
```

### 3. Optional: In System-Pfad verschieben
```bash
sudo cp lvm-manage.sh /usr/local/bin/lvm-manage
sudo chmod +x /usr/local/bin/lvm-manage
```

---

## 📖 Schnelleinstieg (5 Minuten)

### Schritt 1: Volume Group erstellen (einmalig)
```bash
sudo ./lvm-manage.sh create-vg -d /dev/sde -vg backup-pool
```
- Initialisiert Disk `/dev/sde` für LVM
- Erstellt Volume Group `backup-pool` mit ~16TB Speicher

### Schritt 2: Logical Volume für Kunde erstellen
```bash
sudo ./lvm-manage.sh create-lv -vg backup-pool -lv kunde1-backup -s 1000G -m /backup/kunde1
```
- Erstellt 1000GB (1TB) Logical Volume
- Formatiert mit ext4
- Mountet zu `/backup/kunde1`
- Fügt automatisch zu `/etc/fstab` hinzu

### Schritt 3: Status überprüfen
```bash
sudo ./lvm-manage.sh status
sudo ./lvm-manage.sh stats -vg backup-pool
```

---

## 🎯 Alle Befehle

### Volume Groups (VG)

#### create-vg - VG erstellen
```bash
sudo ./lvm-manage.sh create-vg -d /dev/sde -vg backup-pool
```
**Parameter:**
- `-d` Device (z.B. /dev/sde)
- `-vg` Volume Group Name

**Was passiert:**
- Initialisiert Disk als Physical Volume
- Erstellt LVM Volume Group
- Registriert VG im Tracking-System

---

#### delete-vg - VG löschen (mit ALLEN LVs!)
```bash
sudo ./lvm-manage.sh delete-vg -vg backup-pool
```
**⚠️ WARNUNG:** Löscht die komplette VG und alle Logical Volumes!

**Was passiert:**
- Fragt zweimal zur Bestätigung
- Unmountet alle LVs
- Löscht alle LVs
- Löscht die VG
- Entfernt fstab Einträge
- Entfernt aus Tracking

---

#### expand-vg - VG vergrößern (nach Disk-Expansion)
```bash
sudo ./lvm-manage.sh expand-vg -d /dev/sde -vg backup-pool
```
**Szenario:** Du hast in Proxmox die Disk von 12TB auf 20TB vergrößert

**Parameter:**
- `-d` Device (das bereits zur VG gehört)
- `-vg` Volume Group Name

**Was passiert:**
- Erkennt neue Disk-Größe
- Vergrößert Physical Volume
- Macht Platz für neue LVs verfügbar

---

### Logical Volumes (LV)

#### create-lv - LV erstellen
```bash
sudo ./lvm-manage.sh create-lv -vg backup-pool -lv kunde1-backup -s 1000G -m /backup/kunde1
```
**Parameter:**
- `-vg` Volume Group Name
- `-lv` Logical Volume Name
- `-s` Größe (100M, 1000G, 1T, etc.)
- `-m` Mountpoint
- `-t` Dateisystem (optional, default: ext4)

**Was passiert:**
- Erstellt LV mit angegebener Größe
- Formatiert mit ext4 (oder gewähltem FS)
- Erstellt Mountpoint
- Mountet automatisch
- Trägt in fstab ein (persistent)

---

#### resize-lv - LV vergrößern
```bash
sudo ./lvm-manage.sh resize-lv -vg backup-pool -lv kunde1-backup -s 1500G
```
**Parameter:**
- `-vg` Volume Group Name
- `-lv` Logical Volume Name
- `-s` Neue Größe (muss GRÖSSER sein als aktuell!)

**Was passiert:**
- Vergrößert das LV
- Passt Dateisystem automatisch an
- Keine Ausfallzeit, läuft online!

**Beispiel-Workflow:**
```bash
# Kunde 1 hatte 1000G, braucht jetzt 1500G
sudo ./lvm-manage.sh resize-lv -vg backup-pool -lv kunde1-backup -s 1500G

# Status überprüfen
df -h /backup/kunde1
```

---

#### shrink-lv - LV verkleinern
```bash
sudo ./lvm-manage.sh shrink-lv -vg backup-pool -lv kunde1-backup -s 500G
```
**⚠️ WARNUNG:** Verkleinern ist riskant! Nur wenn weniger Daten vorhanden sind!

**Parameter:**
- `-vg` Volume Group Name
- `-lv` Logical Volume Name
- `-s` Neue Größe (muss KLEINER sein als aktuell!)

**Was passiert:**
- Fragt zur Bestätigung
- Unmountet das LV
- Überprüft Dateisystem
- Verkleinert Dateisystem
- Verkleinert LV
- Remountet

---

#### delete-lv - LV löschen
```bash
sudo ./lvm-manage.sh delete-lv -vg backup-pool -lv kunde1-backup
```
**⚠️ Löscht das Logical Volume und ALLE Daten!**

**Parameter:**
- `-vg` Volume Group Name
- `-lv` Logical Volume Name

**Was passiert:**
- Fragt zur Bestätigung
- Unmountet wenn noch gemountet
- Löscht das LV
- Daten sind weg!

---

### Status & Monitoring

#### stats - Statistiken anzeigen
```bash
# Für spezifische VG
sudo ./lvm-manage.sh stats -vg backup-pool

# Alle VGs
sudo ./lvm-manage.sh stats
```

**Output Beispiel:**
```
=== LVM Statistiken ===
Analysiere Volume Group 'backup-pool'...

⏳ Sammle Daten (dies kann ein paar Sekunden dauern)...

Name                      Größe           Genutzt         %
────────────────────────────────────────────────────────
test-backup               1000.00 GiB     2.1M            0%
kunde1-backup             1000.00 GiB     150G            15%
kunde2-backup             500.00 GiB      450G            90%
```

---

#### status - Status anzeigen
```bash
# Nur getracked VGs (deine selbst erstellten)
sudo ./lvm-manage.sh status

# ALLE VGs im System
sudo ./lvm-manage.sh status --all

# Spezifische VG
sudo ./lvm-manage.sh status --vgn backup-pool
```

---

## 💼 Praxisbeispiele

### Szenario 1: Neuer Kunde mit 250GB
```bash
# 1. VG erstellen (falls nicht schon vorhanden)
sudo ./lvm-manage.sh create-vg -d /dev/sde -vg backup-pool

# 2. LV für Kunde erstellen
sudo ./lvm-manage.sh create-lv -vg backup-pool -lv kunde5-backup -s 250G -m /backup/kunde5

# 3. Überprüfen
sudo ./lvm-manage.sh stats -vg backup-pool
df -h /backup/kunde5
```

---

### Szenario 2: Kunde upgraded von 500GB auf 1000GB
```bash
# 1. Größe ändern
sudo ./lvm-manage.sh resize-lv -vg backup-pool -lv kunde2-backup -s 1000G

# 2. Überprüfen
df -h /backup/kunde2
sudo ./lvm-manage.sh stats -vg backup-pool
```

---

### Szenario 3: Disk voll - Neue Disk hinzufügen
```bash
# 1. Neue Disk zu VG hinzufügen
sudo ./lvm-manage.sh expand-vg -d /dev/sdf -vg backup-pool

# 2. Neue Customers können jetzt bedient werden
sudo ./lvm-manage.sh create-lv -vg backup-pool -lv kunde10-backup -s 2000G -m /backup/kunde10

# 3. Status überprüfen
sudo ./lvm-manage.sh status --vgn backup-pool
```

---

### Szenario 4: Kunde kündigt - Speicher freigeben
```bash
# 1. LV löschen (mit Bestätigung)
sudo ./lvm-manage.sh delete-lv -vg backup-pool -lv kunde3-backup

# 2. Speicher steht wieder zur Verfügung
sudo ./lvm-manage.sh stats -vg backup-pool
```

---

## 📁 Dateistruktur

```
/var/lib/lvm-manage/
└── .vg-tracking          # Tracking-Datei mit allen selbst erstellten VGs

/etc/fstab                # Automatisch aktualisiert mit UUID Einträgen

/backup/kunde1/           # Mountpoint (erstellbar)
/backup/kunde2/           # Mountpoint (erstellbar)
etc...
```

---

## 🔍 Troubleshooting

### Problem: "command not found"
```bash
# Lösung: Script muss ausführbar sein
chmod +x lvm-manage.sh

# Oder vollständigen Pfad nutzen
./lvm-manage.sh
```

---

### Problem: "Root erforderlich!"
```bash
# Lösung: Immer mit sudo aufrufen
sudo ./lvm-manage.sh create-lv ...
```

---

### Problem: LV erstellen fehlgeschlagen
```bash
# Überprüfe ob VG existiert
sudo lvdisplay /dev/backup-pool

# Oder nutze Script
sudo ./lvm-manage.sh status --vgn backup-pool

# Prüfe freien Platz in VG
sudo vgdisplay backup-pool | grep "Free"
```

---

### Problem: Mounten fehlgeschlagen
```bash
# Überprüfe Mountpoint Existenz
ls -la /backup/kunde1/

# Überprüfe fstab
cat /etc/fstab | grep backup-pool

# Manuelle Überprüfung
sudo mount -a
```

---

### Problem: LV wird in stats nicht angezeigt
```bash
# Überprüfe /etc/fstab
cat /etc/fstab | grep backup-pool

# Sollte UUID Eintrag haben:
# UUID=... /backup/kunde1 ext4 defaults,nofail 0 2

# Wenn nicht: Manuell hinzufügen
sudo blkid /dev/backup-pool/kunde1-backup
# Output nutzen um UUID zu finden, dann zu fstab hinzufügen
```

---

## ⚙️ Konfiguration

### Tracking-Datei Location
```bash
# Tracking-Datei anschauen
cat /var/lib/lvm-manage/.vg-tracking

# Beispiel Inhalt:
backup-pool
storage-pool
archive-pool
```

---

### Mountpoint Convention
**Empfehlte Struktur:**
```
/backup/
├── kunde1/
├── kunde2/
├── kunde3/
└── test/
```

oder

```
/datastore/
├── vip-customer-01/
├── standard-customer-02/
└── ...
```

---

## 🔐 Sicherheit

### Best Practices

1. **Immer Backups vor Änderungen machen:**
   ```bash
   # Z.B. mit tar
   sudo tar -czf /backup-backup-$(date +%Y%m%d).tar.gz /backup/kunde1/
   ```

2. **Regelmäßig Speicher überprüfen:**
   ```bash
   # Tägliche Überprüfung per Cron
   sudo ./lvm-manage.sh stats -vg backup-pool >> /var/log/lvm-stats.log
   ```

3. **Nur root-User sollte Zugriff haben:**
   ```bash
   sudo chown root:root lvm-manage.sh
   sudo chmod 700 lvm-manage.sh
   ```

---

## 📊 Monitoring Setup (optional)

### Tägliche Stats per Cron
```bash
# Als root
sudo crontab -e

# Hinzufügen:
0 2 * * * /root/lvm-manage.sh stats -vg backup-pool >> /var/log/lvm-stats.log

# Log überprüfen
tail -f /var/log/lvm-stats.log
```

---

## 🎓 Tipps & Tricks

### Schnelle Übersicht
```bash
# Alle infos in einem Command
sudo ./lvm-manage.sh status --all && sudo ./lvm-manage.sh stats -vg backup-pool
```

---

### Speicher-Planung
```bash
# Überblick wie viel noch frei ist
sudo vgdisplay backup-pool | grep -E "VG Size|Free"

# Output:
# VG Size               <16.00 TiB
# Free PE / Size       3938303 / 15.02 TiB
```

---

### Automation mit WHMCS
```bash
# Künftige Integration möglich:
# 1. Order kommt in WHMCS
# 2. Webhook ruft auf: lvm-manage.sh create-lv
# 3. LV wird automatisch erstellt
# 4. Zugangsdaten an Kunde

# Beispiel Hook:
curl https://your-server/whmcs-hook.php?action=create_lv&size=500G&customer=12345
```

---

## 📞 Support & Hilfe

### Help-Command
```bash
sudo ./lvm-manage.sh -h
```

---

### Detaillierte Logs
```bash
# Alle LVM Befehle loggen
sudo ./lvm-manage.sh create-lv ... 2>&1 | tee /tmp/lvm-debug.log

# Log ansehen
cat /tmp/lvm-debug.log
```

---

## 📝 Changelog

### Version 1.0
- ✅ VG erstellen/löschen
- ✅ LV erstellen/resize/shrink/löschen
- ✅ VG expandieren
- ✅ Statistiken & Status
- ✅ Automatisches Tracking
- ✅ fstab Integration

---

## 📄 Lizenz

Dieses Script wurde für Darkmatter IT entwickelt.

---

## 🎯 Next Steps

1. **Script testen** mit Test-VG
2. **Dokumentation lesen** (dieses README)
3. **Best Practices implementieren** (Backups, Monitoring)
4. **Automation mit WHMCS planen** (künftig)
5. **Team trainieren** auf Script-Nutzung

---

## 💡 Weitere Features (geplant)

- [ ] Snapshots für LVs
- [ ] Automatische Backups
- [ ] WHMCS Integration
- [ ] Web-Dashboard
- [ ] Alerts bei 80% Auslastung
- [ ] Automatische Defragmentation

---
