#!/usr/bin/env bash
# ==============================================================================
#  setup-vmware.sh - Bygger SOC Home Lab i VMware Workstation (Linux-värd)
#
#  VMware Workstation har inget PowerShell-API på Linux, så vi gör exakt
#  det VMware själva gör: skriver .vmx-filer (maskinkonfiguration) och
#  skapar diskar med vmware-vdiskmanager.
#
#  Skriptet:
#    1. Letar upp vmrun och vmware-vdiskmanager
#    2. Kontrollerar att vmnet-näten finns (/etc/vmware/networking)
#    3. Skapar en virtuell disk per maskin
#    4. Genererar en .vmx-fil per maskin
#    5. Registrerar maskinerna och (valfritt) startar dem
#
#  ANVÄNDNING:
#    ./setup-vmware.sh --iso ~/ISO --vmpath ~/Lab/VMs
#    sudo ./setup-vmware.sh --configure-host-ip     # sätter 192.168.30.2 på vmnet12
#    ./setup-vmware.sh --start
#
#  OBS: Virtuella nät (VMnet) MÅSTE skapas i förväg med 'vmware-netcfg'.
#       Skriptet skriver ut exakta instruktioner om de saknas.
# ==============================================================================

set -euo pipefail

ISO_PATH="$HOME/ISO"
VM_PATH="$HOME/Lab/VMs"
WAN_NET="vmnet8"
CONFIGURE_HOST_IP=false
START_VM=false
SKIP_NET_CHECK=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info() { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC}   $*"; }
log_err()  { echo -e "${RED}[X]${NC}   $*" >&2; }
log_step() { echo -e "\n${CYAN}=== $* ===${NC}"; }

usage() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)                ISO_PATH="$2"; shift 2 ;;
        --vmpath)             VM_PATH="$2"; shift 2 ;;
        --wan-net)            WAN_NET="$2"; shift 2 ;;
        --configure-host-ip)  CONFIGURE_HOST_IP=true; shift ;;
        --start)              START_VM=true; shift ;;
        --skip-net-check)     SKIP_NET_CHECK=true; shift ;;
        -h|--help)            usage ;;
        *) echo "Okänd flagga: $1"; usage ;;
    esac
done

echo -e "${CYAN}"
cat <<'BANNER'
  ============================================================
    SOC HOME LAB - VMware Workstation Setup (Linux)
  ============================================================
BANNER
echo -e "${NC}"

# ------------------------------------------------------------------ 1. Verktyg
log_step "Letar efter VMware Workstation"

VMRUN=""
VDISKMAN=""

for candidate in /usr/bin/vmrun /usr/local/bin/vmrun "$(command -v vmrun 2>/dev/null)"; do
    [[ -x "$candidate" ]] && { VMRUN="$candidate"; break; }
done
for candidate in /usr/bin/vmware-vdiskmanager /usr/local/bin/vmware-vdiskmanager "$(command -v vmware-vdiskmanager 2>/dev/null)"; do
    [[ -x "$candidate" ]] && { VDISKMAN="$candidate"; break; }
done

if [[ -z "$VMRUN" ]]; then
    log_err "Hittade inte 'vmrun'."
    echo "      VMware Workstation Pro måste vara installerat."
    echo "      https://www.vmware.com/products/desktop-hypervisor.html"
    exit 1
fi

if [[ -z "$VDISKMAN" ]]; then
    log_err "Hittade inte 'vmware-vdiskmanager'."
    exit 1
fi

log_ok "vmrun               : $VMRUN"
log_ok "vmware-vdiskmanager : $VDISKMAN"

# ------------------------------------------------------------------ 2. Nätverk
log_step "Kontrollerar virtuella nätverk (vmnet)"

# Logiskt namn -> vmnet -> subnät -> värd-IP
declare -A NET_VMNET=(
    [WAN]="$WAN_NET"   [LAN]="vmnet10"   [DMZ]="vmnet11"
    [SOC]="vmnet12"    [RED]="vmnet13"
)
declare -A NET_SUBNET=(
    [WAN]="behall standard"   [LAN]="192.168.10.0/24"
    [DMZ]="192.168.20.0/24"   [SOC]="192.168.30.0/24"
    [RED]="192.168.40.0/24"
)
declare -A NET_HOSTIP=(
    [WAN]=""                  [LAN]="192.168.10.2"
    [DMZ]="192.168.20.2"      [SOC]="192.168.30.2"
    [RED]="192.168.40.2"
)

MISSING=()

for net in WAN LAN DMZ SOC RED; do
    vmnet="${NET_VMNET[$net]}"
    # WAN = NAT (vmnet8) har ofta ingen synlig "host-only"-adapter i samma mening
    if ip link show "$vmnet" >/dev/null 2>&1; then
        ipaddr=$(ip -4 addr show "$vmnet" 2>/dev/null | awk '/inet /{print $2}' | tr '\n' ' ')
        log_ok "$(printf '%-4s -> %-8s [%s]' "$net" "$vmnet" "${ipaddr:-ingen IP}")"
    else
        if [[ "$vmnet" == "$WAN_NET" ]]; then
            log_warn "$(printf '%-4s -> %-8s (NAT - kontrollera manuellt)' "$net" "$vmnet")"
        else
            log_err "$(printf '%-4s -> %-8s SAKNAS' "$net" "$vmnet")"
            MISSING+=("$net = $vmnet (${NET_SUBNET[$net]})")
        fi
    fi
done

if [[ ${#MISSING[@]} -gt 0 && "$SKIP_NET_CHECK" == false ]]; then
    cat <<'MISSINGNET'

  ============================================================
    VIRTUELLA NÄTVERK SAKNAS
  ============================================================

  VMware Workstation kan inte skapa vmnet via kommandorad på ett
  tillförlitligt sätt. Gör så här (tar 3 minuter):

    1. Stäng alla VM:er.
    2. Starta nätverksredigeraren som root:
         sudo vmware-netcfg
    3. För varje nät nedan: 'Add Network' -> välj 'Host-only'
       och BOCKA UR 'Use local DHCP service...'
       (annars får VM:erna fel gateway från VMware:s egen DHCP)
    4. Apply -> OK
    5. Starta om VMware-tjänsterna:
         sudo /etc/init.d/vmware restart      (eller)
         sudo systemctl restart vmware
    6. Kör detta skript igen.

     Nät som behövs:
MISSINGNET
    for m in "${MISSING[@]}"; do echo "       - $m"; done
    echo ""
    echo "  Vill du köra ändå?  $0 --skip-net-check"
    echo ""
    exit 1
fi

# ------------------------------------------------------------------ 3. Mappar
log_step "Skapar mappstruktur"
[[ -d "$ISO_PATH" ]] || log_warn "ISO-mappen '$ISO_PATH' finns inte - koppla ISO:er manuellt"
mkdir -p "$VM_PATH"
log_ok "VM-mapp: $VM_PATH"

# ------------------------------------------------------------------ 4. VM-definitioner
# Format: NAMN|GUESTOS|CPU|RAM_MB|DISK_GB|FIRMWARE|TPM|NÄTVERK(kommasep)|ISO-mönster|Beskrivning
VM_LIST=(
"FW-01|freebsd-64|2|2048|40|bios|no|WAN,LAN,DMZ,SOC,RED|*OPNsense*.iso;*opnsense*.iso|Brandvägg - 5 nätverkskort"
"DC-01|windows9-64|2|4096|60|bios|no|LAN|*SERVER_EVAL*.iso;*Windows_Server_2022*.iso;*SW_DVD9_Win_Server*|Domänkontrollant AD DS/DNS/DHCP"
"FS01|windows9-64|2|2048|60|bios|no|LAN|*SERVER_EVAL*.iso;*Windows_Server_2022*.iso|Filserver - AGDLP-demoresurser"
"WIN11-01|windows11-64|2|4096|60|efi|yes|LAN|*Win11*.iso;*windows_11*.iso|Klient - GPO-test och attackmål"
"LNX-WEB01|ubuntu-64|1|2048|25|bios|no|DMZ|*ubuntu-24.04*server*.iso;*ubuntu-24*.iso|Webbserver i DMZ (DVWA)"
"LNX-DB01|ubuntu-64|1|2048|25|bios|no|DMZ|*ubuntu-24.04*server*.iso;*ubuntu-24*.iso|Databas i DMZ"
"SOC-WAZUH|ubuntu-64|4|8192|100|bios|no|SOC|*ubuntu-22.04*server*.iso;*ubuntu-22*.iso|Wazuh all-in-one SIEM"
"KALI-01|debian12-64|2|4096|40|bios|no|RED|*kali-linux*installer*.iso;*kali*.iso|Red Team - attackmaskin"
)

resolve_iso() {
    local patterns="$1"
    local IFS=';'
    read -ra pats <<< "$patterns"
    for p in "${pats[@]}"; do
        local hit
        hit=$(find "$ISO_PATH" -maxdepth 1 -type f -name "$p" 2>/dev/null | head -1)
        [[ -n "$hit" ]] && { echo "$hit"; return 0; }
    done
    echo ""
}

# ------------------------------------------------------------------ 5. Skapa
log_step "Skapar virtuella maskiner"

CREATED=0
SKIPPED=0

for entry in "${VM_LIST[@]}"; do
    IFS='|' read -r name guestos cpu ram disk firmware tpm nics isopats desc <<< "$entry"

    echo ""
    echo -e "  --- ${name}: ${desc}"

    vm_dir="$VM_PATH/$name"
    vmx="$vm_dir/$name.vmx"
    vmdk="$vm_dir/$name.vmdk"

    if [[ -f "$vmx" ]]; then
        read -rp "      $name finns redan. Skriva över? [j/N] " answer
        [[ "$answer" =~ ^[JjYy] ]] || { log_warn "Hoppar över $name"; SKIPPED=$((SKIPPED+1)); continue; }
    fi

    mkdir -p "$vm_dir"

    # --- Disk ---
    if [[ -f "$vmdk" ]]; then
        echo "      Disk finns redan - behåller den"
    else
        printf "      Skapar disk: %s GB..." "$disk"
        if "$VDISKMAN" -c -s "${disk}GB" -a lsilogic -t 0 "$vmdk" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${NC}"
        else
            echo -e " ${RED}FEL${NC}"
            log_err "Kunde inte skapa disk för $name"
            continue
        fi
    fi

    # --- ISO ---
    iso=$(resolve_iso "$isopats")

    # --- .vmx ---
    {
        echo '.encoding = "UTF-8"'
        echo 'config.version = "8"'
        echo 'virtualHW.version = "20"'
        echo "displayName = \"$name\""
        echo "guestOS = \"$guestos\""
        echo "numvcpus = \"$cpu\""
        echo "memsize = \"$ram\""
        echo "firmware = \"$firmware\""
        echo ''
        echo '# --- Undvik frågor vid start ---'
        echo 'msg.autoAnswer = "TRUE"'
        echo 'hints.hideAll = "TRUE"'
        echo ''
        echo '# --- Diskkontroller (LSI SAS) ---'
        echo 'scsi0.present = "TRUE"'
        echo 'scsi0.virtualDev = "lsisas1068"'
        echo 'scsi0:0.present = "TRUE"'
        echo "scsi0:0.fileName = \"$name.vmdk\""
        echo 'scsi0:0.redo = ""'
        echo ''
        echo '# --- CD/DVD ---'
        echo 'ide1:0.present = "TRUE"'
        echo 'ide1:0.deviceType = "cdrom-image"'
        if [[ -n "$iso" ]]; then
            echo "ide1:0.fileName = \"$iso\""
            echo 'ide1:0.startConnected = "TRUE"'
        else
            echo 'ide1:0.fileName = ""'
            echo 'ide1:0.startConnected = "FALSE"'
        fi
        echo 'ide1:0.autodetect = "TRUE"'
        echo ''
        echo '# --- Nätverk ---'
        i=0
        IFS=',' read -ra niclist <<< "$nics"
        for nic in "${niclist[@]}"; do
            vmnet="${NET_VMNET[$nic]}"
            echo "ethernet$i.present = \"TRUE\""
            echo "ethernet$i.connectionType = \"custom\""
            echo "ethernet$i.vnet = \"$vmnet\""
            echo "ethernet$i.virtualDev = \"vmxnet3\""
            echo "ethernet$i.addressType = \"generated\""
            echo "ethernet$i.wakeOnPcktRcv = \"FALSE\""
            echo "ethernet$i.displayName = \"$nic ($vmnet)\""
            echo ""
            i=$((i+1))
        done
        if [[ "$tpm" == "yes" ]]; then
            echo '# --- TPM (krävs för Windows 11) ---'
            echo 'tpm.present = "TRUE"'
            echo ''
        fi
        echo '# --- Övrigt ---'
        echo 'usb.present = "TRUE"'
        echo 'usb_xhci.present = "TRUE"'
        echo 'sound.present = "FALSE"'
        echo 'mks.enable3d = "FALSE"'
        echo 'svga.autodetect = "TRUE"'
        echo 'pciBridge0.present = "TRUE"'
        echo 'pciBridge4.present = "TRUE"'
        echo 'pciBridge4.virtualDev = "pcieRootPort"'
        echo 'pciBridge5.present = "TRUE"'
        echo 'pciBridge5.virtualDev = "pcieRootPort"'
        echo 'pciBridge6.present = "TRUE"'
        echo 'pciBridge6.virtualDev = "pcieRootPort"'
        echo 'pciBridge7.present = "TRUE"'
        echo 'pciBridge7.virtualDev = "pcieRootPort"'
        echo 'vmci0.present = "TRUE"'
        echo 'floppy0.present = "FALSE"'
        echo 'serial0.present = "FALSE"'
        echo 'parallel0.present = "FALSE"'
        echo 'checkpoint.vmState = ""'
        echo 'uuid.action = "create"'
    } > "$vmx"

    log_ok ".vmx skapad: $vmx"
    if [[ -n "$iso" ]]; then
        log_ok "ISO kopplad: $(basename "$iso")"
    else
        log_warn "Ingen ISO hittades för $name - koppla manuellt"
    fi
    CREATED=$((CREATED+1))
done

# ------------------------------------------------------------------ 6. Värd-IP
if [[ "$CONFIGURE_HOST_IP" == true ]]; then
    log_step "Sätter statisk IP på värdens SOC-adapter (vmnet12)"
    if ip link show vmnet12 >/dev/null 2>&1; then
        if ip -4 addr show vmnet12 | grep -q "192.168.30.2"; then
            log_ok "192.168.30.2 redan satt"
        else
            sudo ip addr add 192.168.30.2/24 dev vmnet12 && \
                log_ok "192.168.30.2 satt på vmnet12 (når Wazuh på https://192.168.30.10)"
        fi
    else
        log_err "vmnet12 finns inte"
    fi
fi

# ------------------------------------------------------------------ 7. Registrera
log_step "Registrerar maskinerna i VMware"

for entry in "${VM_LIST[@]}"; do
    IFS='|' read -r name _ <<< "$entry"
    vmx="$VM_PATH/$name/$name.vmx"
    [[ -f "$vmx" ]] || continue

    if "$VMRUN" -T ws start "$vmx" nogui >/dev/null 2>&1; then
        log_ok "$name registrerad"
        sleep 2
        "$VMRUN" -T ws stop "$vmx" soft >/dev/null 2>&1 || true
    else
        log_warn "$name kunde inte registreras (kanske redan registrerad)"
    fi
done

if [[ "$START_VM" == true ]]; then
    log_step "Startar FW-01"
    "$VMRUN" -T ws start "$VM_PATH/FW-01/FW-01.vmx"
fi

# ------------------------------------------------------------------ Sammanfattning
echo ""
echo -e "${GREEN}  ============================================================"
echo "    KLART!"
echo -e "  ============================================================${NC}"
echo ""
echo "  Skapade maskiner : $CREATED"
echo "  Hoppades över    : $SKIPPED"
echo ""
echo "  Nätverkskarta:"
echo "    (WAN/$WAN_NET behåller VMware:s standard - ändra det inte i onödan)"
for net in WAN LAN DMZ SOC RED; do
    printf "    %-4s -> %-8s %s\n" "$net" "${NET_VMNET[$net]}" "${NET_SUBNET[$net]}"
done

cat <<EOF

  ============================================================
    NÄSTA STEG
  ============================================================

  1. Öppna VMware Workstation - alla 8 maskiner ligger i biblioteket.

  2. Starta FW-01 och installera OPNsense (docs/02-opnsense-brandvagg.md)

  3. MAC-adresser (nyckeln till att veta vilket kort som blir hn0..hn4):
       Högerklicka VM -> Settings -> Network Adapter -> Advanced

  4. ANVÄNDBARA KOMMANDON:

       # Lista körande maskiner
       vmrun list

       # Starta / stänga
       vmrun -T ws start "$VM_PATH/DC-01/DC-01.vmx"
       vmrun -T ws stop  "$VM_PATH/DC-01/DC-01.vmx" soft

       # SNAPSHOTS (VMware motsvarar Hyper-V "checkpoints")
       vmrun -T ws snapshot "$VM_PATH/DC-01/DC-01.vmx" "Fas3-innan-AD"
       vmrun -T ws listSnapshots "$VM_PATH/DC-01/DC-01.vmx"
       vmrun -T ws revertToSnapshot "$VM_PATH/DC-01/DC-01.vmx" "Fas3-innan-AD"
       vmrun -T ws deleteSnapshot "$VM_PATH/DC-01/DC-01.vmx" "Fas3-innan-AD"

  5. Installationsordning:
       FW-01 -> DC-01 -> WIN11-01/FS01 -> LNX-* -> SOC-WAZUH -> KALI-01

EOF
