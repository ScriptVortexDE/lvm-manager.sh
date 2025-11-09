#!/bin/bash

# LVM Volume Management Script
set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variablen
ACTION=""
DEVICE=""
VG_NAME=""
LV_NAME=""
LV_SIZE=""
MOUNT_POINT=""
FSTYPE="ext4"
TRACKING_FILE="/var/lib/lvm-manage/.vg-tracking"

# Log Funktionen
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[SCHRITT]${NC} $1"; }

# Hilfe
show_help() {
    cat << 'EOF'
LVM Volume Management Script

Befehle:
  ./lvm-manage.sh create-vg -d /dev/sdc -vg backup-pool
  ./lvm-manage.sh create-lv -vg backup-pool -lv kunde1 -s 1000G -m /backup/kunde1
  ./lvm-manage.sh resize-lv -vg backup-pool -lv kunde1 -s 1500G
  ./lvm-manage.sh shrink-lv -vg backup-pool -lv kunde1 -s 500G
  ./lvm-manage.sh delete-lv -vg backup-pool -lv kunde1
  ./lvm-manage.sh delete-vg -vg backup-pool
  ./lvm-manage.sh expand-vg -d /dev/sdc -vg backup-pool
  ./lvm-manage.sh stats [-vg backup-pool]
  ./lvm-manage.sh status
  ./lvm-manage.sh status --all
  ./lvm-manage.sh status --vgn backup-pool

Optionen:
  -d    Device (/dev/sdc)
  -vg   Volume Group Name
  -lv   Logical Volume Name
  -s    Größe (100G, 1T, etc.)
  -m    Mountpoint (/backup/kunde1)
  -t    Dateisystem (default: ext4)
EOF
}

# Utility Funktionen
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Root erforderlich!"
        exit 1
    fi
}

track_vg() {
    mkdir -p "$(dirname "$TRACKING_FILE")"
    if ! grep -q "^$1$" "$TRACKING_FILE" 2>/dev/null; then
        echo "$1" >> "$TRACKING_FILE"
    fi
}

get_tracked_vgs() {
    [[ -f "$TRACKING_FILE" ]] && cat "$TRACKING_FILE"
}

untrack_vg() {
    [[ -f "$TRACKING_FILE" ]] && sed -i "/^$1$/d" "$TRACKING_FILE"
}

# Main Functions
create_vg() {
    log_step "Erstelle VG '$VG_NAME' auf $DEVICE..."
    pvcreate -y "$DEVICE" 2>/dev/null || log_warn "PV existiert bereits"
    sleep 1
    
    if vgdisplay "$VG_NAME" > /dev/null 2>&1; then
        vgextend "$VG_NAME" "$DEVICE" || log_warn "Device bereits Teil der VG"
    else
        vgcreate "$VG_NAME" "$DEVICE" || { log_error "VG Erstellung fehlgeschlagen!"; exit 1; }
    fi
    
    track_vg "$VG_NAME"
    log_info "VG erfolgreich erstellt!"
}

create_lv() {
    log_step "Erstelle LV '$LV_NAME' mit $LV_SIZE..."
    lvcreate -L "$LV_SIZE" -n "$LV_NAME" "$VG_NAME" || { log_error "LV Erstellung fehlgeschlagen!"; exit 1; }
    sleep 1
    
    log_step "Formatiere mit $FSTYPE..."
    mkfs -t "$FSTYPE" -F "/dev/$VG_NAME/$LV_NAME"
    
    mkdir -p "$MOUNT_POINT"
    mount "/dev/$VG_NAME/$LV_NAME" "$MOUNT_POINT"
    
    local uuid
    uuid=$(blkid -s UUID -o value "/dev/$VG_NAME/$LV_NAME")
    if ! grep -q "UUID=$uuid" /etc/fstab; then
        echo "UUID=$uuid $MOUNT_POINT $FSTYPE defaults,nofail 0 2" >> /etc/fstab
    fi
    
    log_info "LV erfolgreich erstellt und gemountet!"
}

resize_lv() {
    log_step "Vergrößere LV auf $LV_SIZE..."
    local mount_point
    mount_point=$(mount | grep "/dev/$VG_NAME/$LV_NAME" | awk '{print $3}')
    
    [[ -z "$mount_point" ]] && { log_error "LV nicht gemountet!"; exit 1; }
    
    lvresize -L "$LV_SIZE" -r "/dev/$VG_NAME/$LV_NAME" || { log_error "Vergrößerung fehlgeschlagen!"; exit 1; }
    log_info "LV vergrößert!"
}

shrink_lv() {
    log_step "Verkleinere LV auf $LV_SIZE..."
    local mount_point
    mount_point=$(mount | grep "/dev/$VG_NAME/$LV_NAME" | awk '{print $3}')
    
    [[ -z "$mount_point" ]] && { log_error "LV nicht gemountet!"; exit 1; }
    
    log_warn "Verkleinern ist riskant! Stelle sicher, dass weniger Daten vorhanden sind."
    read -p "Wirklich verkleinern? (JA/nein): " confirm
    [[ "$confirm" != "JA" ]] && { log_info "Abgebrochen."; exit 0; }
    
    umount "$mount_point"
    fsck -f "/dev/$VG_NAME/$LV_NAME" || true
    resize2fs "/dev/$VG_NAME/$LV_NAME" "$LV_SIZE"
    lvresize -L "$LV_SIZE" "/dev/$VG_NAME/$LV_NAME"
    mount "/dev/$VG_NAME/$LV_NAME" "$mount_point"
    
    log_info "LV verkleinert!"
}

delete_lv() {
    log_step "Lösche LV '$LV_NAME'..."
    local mount_point
    mount_point=$(mount | grep "/dev/$VG_NAME/$LV_NAME" | awk '{print $3}')
    
    if [[ ! -z "$mount_point" ]]; then
        umount "$mount_point" || umount -l "$mount_point"
    fi
    
    read -p "Wirklich löschen? (ja/nein): " confirm
    [[ "$confirm" != "ja" ]] && { log_info "Abgebrochen."; exit 0; }
    
    lvremove -f "/dev/$VG_NAME/$LV_NAME"
    log_info "LV gelöscht!"
}

delete_vg() {
    log_step "Lösche VG '$VG_NAME' mit ALLEN LVs..."
    log_warn "ALLE Daten werden gelöscht!"
    
    read -p "Wirklich löschen? (ja/nein): " confirm1
    [[ "$confirm1" != "ja" ]] && { log_info "Abgebrochen."; exit 0; }
    
    read -p "Bist du WIRKLICH sicher? (JA/nein): " confirm2
    [[ "$confirm2" != "JA" ]] && { log_info "Abgebrochen."; exit 0; }
    
    # Unmounte alle
    mount | grep "/dev/$VG_NAME" | awk '{print $3}' | while read -r mp; do
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done
    
    # Lösche alle LVs
    lvdisplay /dev/"$VG_NAME" 2>/dev/null | grep "LV Path" | awk '{print $NF}' | while read -r lv; do
        lvremove -f "$lv" 2>/dev/null || true
    done
    
    sleep 1
    vgremove -f "$VG_NAME"
    sed -i "/\/dev\/mapper\/$VG_NAME/d" /etc/fstab
    untrack_vg "$VG_NAME"
    
    log_info "VG und alle LVs gelöscht!"
}

expand_vg() {
    log_step "Vergrößere VG '$VG_NAME'..."
    pvresize "$DEVICE"
    log_info "VG vergrößert!"
}

show_stats() {
    echo ""
    log_info "=== LVM Statistiken ==="
    echo ""
    log_info "Analysiere Volume Group '$VG_NAME'..."
    
    if [[ ! -z "$VG_NAME" ]]; then
        vgdisplay "$VG_NAME" 2>/dev/null || { log_error "VG nicht gefunden!"; return; }
        echo ""
        
        echo "⏳ Sammle Daten (dies kann ein paar Sekunden dauern)..."
        echo ""
        
        printf "%-25s %-15s %-15s %-10s\n" "Name" "Größe" "Genutzt" "%"
        echo "────────────────────────────────────────────────────────"
        
        # Hole alle LVs und ihre Mountpoints direkt aus /etc/fstab
        grep "UUID=" /etc/fstab 2>/dev/null | grep -E "$VG_NAME|/backup" | while read -r line; do
            # Extrahiere Mountpoint und UUID
            mount_point=$(echo "$line" | awk '{print $2}')
            uuid=$(echo "$line" | awk '{print $1}' | sed 's/UUID=//')
            
            # Finde LV Name
            lv_path=$(blkid | grep "$uuid" | awk '{print $1}' | sed 's/:.*$//')
            
            if [[ ! -z "$lv_path" ]] && [[ -e "$mount_point" ]]; then
                name=$(basename "$lv_path")
                size=$(lvdisplay "$lv_path" 2>/dev/null | grep "LV Size" | awk '{print $3" "$4}')
                
                # Nutze df direkt vom Mountpoint
                total=$(df "$mount_point" 2>/dev/null | tail -1 | awk '{print $2}')
                used=$(df "$mount_point" 2>/dev/null | tail -1 | awk '{print $3}')
                used_human=$(df -h "$mount_point" 2>/dev/null | tail -1 | awk '{print $3}')
                
                if [[ -z "$total" ]] || [[ "$total" -eq 0 ]]; then
                    percent="0"
                else
                    percent=$((used * 100 / total))
                fi
                
                printf "%-25s %-15s %-15s %3d%%\n" "$name" "$size" "$used_human" "$percent"
            fi
        done
        echo ""
    else
        log_info "Alle Volume Groups:"
        vgdisplay 2>/dev/null | grep "VG Name" || log_warn "Keine VGs"
    fi
    echo ""
}

show_status_tracked() {
    echo ""
    log_info "=== LVM Status (Tracked VGs) ==="
    echo ""
    
    local tracked=$(get_tracked_vgs)
    [[ -z "$tracked" ]] && { log_warn "Keine getrackten VGs!"; return; }
    
    echo "$tracked" | while read -r vg; do
        if vgdisplay "$vg" > /dev/null 2>&1; then
            log_info "VG: $vg"
            vgdisplay "$vg"
            echo ""
        fi
    done
}

show_status_all() {
    echo ""
    log_info "=== LVM Status (Alle VGs) ==="
    echo ""
    
    log_info "Physical Volumes:"
    pvdisplay || log_warn "Keine PVs"
    echo ""
    
    log_info "Volume Groups:"
    vgdisplay || log_warn "Keine VGs"
    echo ""
    
    log_info "Logical Volumes:"
    lvdisplay || log_warn "Keine LVs"
    echo ""
}

show_status_vg() {
    echo ""
    log_info "=== LVM Status für VG: $VG_NAME ==="
    echo ""
    vgdisplay "$VG_NAME" 2>/dev/null || { log_error "VG nicht gefunden!"; exit 1; }
    echo ""
    lvdisplay /dev/"$VG_NAME" 2>/dev/null || log_warn "Keine LVs"
}

# Main
main() {
    [[ $# -eq 0 ]] && { show_help; exit 0; }
    
    ACTION="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) DEVICE="$2"; shift 2 ;;
            -vg) VG_NAME="$2"; shift 2 ;;
            -lv) LV_NAME="$2"; shift 2 ;;
            -s) LV_SIZE="$2"; shift 2 ;;
            -m) MOUNT_POINT="$2"; shift 2 ;;
            -t) FSTYPE="$2"; shift 2 ;;
            --all|--ALL) VG_NAME="__ALL__"; shift ;;
            --vgn) VG_NAME="$2"; shift 2 ;;
            -h) show_help; exit 0 ;;
            *) log_error "Unbekannte Option: $1"; exit 1 ;;
        esac
    done
    
    check_root
    
    case "$ACTION" in
        create-vg) create_vg ;;
        create-lv) create_lv ;;
        resize-lv) resize_lv ;;
        shrink-lv) shrink_lv ;;
        delete-lv) delete_lv ;;
        delete-vg) delete_vg ;;
        expand-vg) expand_vg ;;
        stats) show_stats ;;
        status)
            if [[ "$VG_NAME" == "__ALL__" ]]; then
                show_status_all
            elif [[ ! -z "$VG_NAME" ]] && [[ "$VG_NAME" != "__ALL__" ]]; then
                show_status_vg
            else
                show_status_tracked
            fi
            ;;
        *) log_error "Unbekannter Befehl: $ACTION"; show_help; exit 1 ;;
    esac
}

main "$@"
