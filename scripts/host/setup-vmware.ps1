<#
.SYNOPSIS
    Skapar alla virtuella nätverk och virtuella maskiner för SOC Home Lab
    i VMware Workstation Pro / Fusion.

.DESCRIPTION
    Detta skript bygger hela labb-infrastrukturen genom att generera .vmx-filer
    (VMware:s maskinkonfiguration) och skapa virtuella diskar med
    vmware-vdiskmanager. Till skillnad från Hyper-V har VMware inget fullständigt
    PowerShell-API, så vi skriver konfigurationsfilerna direkt - vilket är
    exakt så VMware själva gör det "under huven".

    Skriptet gör:
      1. Letar upp vmrun.exe och vmware-vdiskmanager.exe
      2. Kontrollerar att de virtuella nätverken (VMnet) finns på värden
      3. Skapar en virtuell disk per maskin
      4. Genererar en .vmx-fil per maskin med rätt CPU/RAM/disk/nätverk/ISO
      5. Registrerar maskinerna (valfritt) och kan starta dem

    VIKTIGT OM NÄTVERK:
      VMware Workstation kan inte skapa VMnet via kommandorad. Skriptet
      KONTROLLERAR att näten finns och skriver annars ut exakta instruktioner.
      Se -SkipNetworkCheck om du vill köra ändå.

.PARAMETER ISOPath
    Mapp där ISO-filerna ligger. Default: C:\ISO

.PARAMETER VMPath
    Mapp där VM:er och VMDK:er sparas. Default: D:\Lab\VMs

.PARAMETER VMwarePath
    Sökväg till VMware Workstation-installationen.
    Default: "C:\Program Files (x86)\VMware\VMware Workstation"

.PARAMETER WanNetwork
    Vilket VMnet som ska användas som WAN. Default: VMnet8 (NAT - finns alltid)

.PARAMETER ConfigureHostIP
    Sätter statisk IP på värdens SOC-adapter (VMnet12) så du når Wazuh-dashboarden.

.PARAMETER Start
    Startar maskinerna automatiskt efter skapandet (startar med FW-01).

.PARAMETER SkipNetworkCheck
    Fortsätt även om VMnet-näten saknas.

.EXAMPLE
    .\setup-vmware.ps1 -ISOPath "C:\ISO" -VMPath "D:\Lab\VMs" -ConfigureHostIP

.EXAMPLE
    .\setup-vmware.ps1 -Start -Verbose

.NOTES
    Författare: SOC Home Lab
    Kräver:    VMware Workstation Pro 16+ (gratis för personligt bruk)
               Administratörsrättigheter (endast för -ConfigureHostIP)
#>

[CmdletBinding()]
param(
    [string]$ISOPath          = "C:\ISO",
    [string]$VMPath           = "D:\Lab\VMs",
    [string]$VMwarePath       = "C:\Program Files (x86)\VMware\VMware Workstation",
    [string]$WanNetwork       = "VMnet8",
    [switch]$ConfigureHostIP,
    [switch]$Start,
    [switch]$SkipNetworkCheck
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------ Hjälpfunktioner
function Write-Step  { param($m) Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-OK    { param($m) Write-Host "    [OK]  $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "    [!]   $m" -ForegroundColor Yellow }
function Write-Fail  { param($m) Write-Host "    [X]   $m" -ForegroundColor Red }
function Write-Banner {
    param($m)
    Write-Host "`n  ============================================================" -ForegroundColor Magenta
    Write-Host "    $m" -ForegroundColor Magenta
    Write-Host "  ============================================================" -ForegroundColor Magenta
}

Write-Banner "SOC HOME LAB - VMware Workstation Setup"

if ($ConfigureHostIP) {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "-ConfigureHostIP kräver att PowerShell körs som administratör."
    }
}

# ------------------------------------------------------------------ 1. Hitta VMware
Write-Step "Letar efter VMware Workstation"

if (-not (Test-Path $VMwarePath)) {
    $alt = @(
        "C:\Program Files\VMware\VMware Workstation",
        "C:\Program Files (x86)\VMware\VMware Workstation",
        "C:\Program Files\VMware\VMware Player"
    )
    $found = $alt | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { $VMwarePath = $found }
}

if (-not (Test-Path $VMwarePath)) {
    Write-Fail "Hittade inte VMware-installationen."
    Write-Host "      Ange sökvägen manuellt:  .\setup-vmware.ps1 -VMwarePath '<sökväg>'"
    Write-Host "      Eller ladda ner gratis:   https://www.vmware.com/products/desktop-hypervisor.html"
    exit 1
}
Write-OK "VMware hittat: $VMwarePath"

$vmrun = Join-Path $VMwarePath "vmrun.exe"
$vdisk = Join-Path $VMwarePath "vmware-vdiskmanager.exe"

foreach ($tool in @($vmrun, $vdisk)) {
    if (-not (Test-Path $tool)) {
        Write-Fail "Saknar $(Split-Path $tool -Leaf) i $VMwarePath"
        Write-Host "      Kontrollera att du har Workstation PRO (Player saknar vmrun)."
        exit 1
    }
}
Write-OK "vmrun.exe           : funnen"
Write-OK "vmware-vdiskmanager : funnen"

# ------------------------------------------------------------------ 2. Virtuella nät
Write-Step "Kontrollerar virtuella nätverk (VMnet)"

# Mapping: logiskt namn -> VMnet -> subnät -> värd-IP
$Networks = [ordered]@{
    WAN  = @{ Vmnet = $WanNetwork; Subnet = "behall standard"; HostIP = "" }
    LAN  = @{ Vmnet = "VMnet10";   Subnet = "192.168.10.0/24"; HostIP = "192.168.10.2" }
    DMZ  = @{ Vmnet = "VMnet11";   Subnet = "192.168.20.0/24"; HostIP = "192.168.20.2" }
    SOC  = @{ Vmnet = "VMnet12";   Subnet = "192.168.30.0/24"; HostIP = "192.168.30.2" }
    RED  = @{ Vmnet = "VMnet13";   Subnet = "192.168.40.0/24"; HostIP = "192.168.40.2" }
}

# VMware skapar ett nätverkskort på värden för varje host-only VMnet.
# Vi letar efter "VMware Network Adapter VMnet10" osv.
$hostAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceDescription -like "*VMware*" -or $_.Name -like "*VMnet*" }

$missingNetworks = @()

foreach ($net in $Networks.GetEnumerator()) {
    $vmnetName = $net.Value.Vmnet
    $num       = $vmnetName -replace 'VMnet', ''

    # WAN = NAT (VMnet8) skapar normalt INTE ett synligt kort i Windows
    if ($vmnetName -eq $WanNetwork) {
        Write-OK "$($net.Key.PadRight(4)) -> $vmnetName (NAT/bridged - standardnät)"
        continue
    }

    $adapter = $hostAdapters | Where-Object { $_.Name -like "*VMnet$num*" } | Select-Object -First 1

    if ($adapter) {
        $ip = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $ipText = if ($ip) { ($ip.IPAddress -join ', ') } else { "ingen IP satt" }
        Write-OK "$($net.Key.PadRight(4)) -> $vmnetName  ($($adapter.Name))  [$ipText]"
    } else {
        Write-Fail "$($net.Key.PadRight(4)) -> $vmnetName SAKNAS"
        $missingNetworks += "$($net.Key) = $vmnetName ($($net.Value.Subnet))"
    }
}

if ($missingNetworks.Count -gt 0 -and -not $SkipNetworkCheck) {
    Write-Host @"

  ============================================================
    VIRTUELLA NÄTVERK SAKNAS
  ============================================================

  VMware Workstation kan tyvärr inte skapa VMnet via kommandorad.
  Gör så här (tar 3 minuter):

    1. Stäng alla VM:er.
    2. Starta 'Virtual Network Editor' som ADMINISTRATÖR:
         Startmenyn -> sök 'Virtual Network Editor' -> högerklicka -> Kör som administratör
       (finns även i VMware-mappen som 'vmnetcfg.exe' i vissa versioner)
    3. Klicka 'Change Settings' (uppe till höger) om knappen finns.
    4. För VART och ett av dessa nät: klicka 'Add Network' och välj:
"@ -ForegroundColor Yellow

    foreach ($m in $missingNetworks) { Write-Host "         - $m" -ForegroundColor Yellow }

    Write-Host @"
       Typ: 'Host-only'
       Bocka UR: 'Use local DHCP service to distribute IP addresses'
                 (viktigt! annars får VM:erna fel gateway)

    5. OK -> Apply -> OK.  Starta om VMware-tjänsterna eller datorn.
    6. Kör detta skript igen.

  Alternativ (snabbare): låt alla labbnät vara på SAMMA VMnet om du
  vill komma igång snabbt - men då försvinner hela poängen med
  segmenteringen, så gör det inte i det färdiga labbet.

  Vill du köra ändå?  .\setup-vmware.ps1 -SkipNetworkCheck

"@ -ForegroundColor Yellow
    exit 1
}

if ($missingNetworks.Count -gt 0) {
    Write-Warn "$($missingNetworks.Count) nät saknas - fortsätter ändå (-SkipNetworkCheck)"
}

# ------------------------------------------------------------------ 3. Skapa mappar
Write-Step "Skapar mappstruktur"

if (-not (Test-Path $ISOPath)) {
    Write-Warn "ISO-mappen '$ISOPath' finns inte. Koppla ISO:er manuellt senare."
}
New-Item -ItemType Directory -Path $VMPath -Force | Out-Null
Write-OK "VM-mapp: $VMPath"

# ------------------------------------------------------------------ 4. VM-definitioner
# guestOS-värden som fungerar i Workstation 16/17
$vms = @(
    @{
        Name     = "FW-01"
        GuestOS  = "freebsd-64"
        CPU      = 2;  RAM = 2048; Disk = 40
        Firmware = "bios"
        NICs     = @(
            @{ Net = "WAN";  Dev = "vmxnet3" }
            @{ Net = "LAN";  Dev = "vmxnet3" }
            @{ Net = "DMZ";  Dev = "vmxnet3" }
            @{ Net = "SOC";  Dev = "vmxnet3" }
            @{ Net = "RED";  Dev = "vmxnet3" }
        )
        ISO      = @("*OPNsense*.iso", "*opnsense*.iso")
        Note     = "Brandvägg - 5 nätverkskort"
    }
    @{
        Name     = "DC-01"
        GuestOS  = "windows9-64"
        CPU      = 2;  RAM = 4096; Disk = 60
        Firmware = "bios"; TPM = $false
        NICs     = @( @{ Net = "LAN"; Dev = "vmxnet3" } )
        ISO      = @("*SERVER_EVAL*.iso", "*Windows_Server_2022*.iso", "*SW_DVD9_Win_Server*")
        Note     = "Domänkontrollant (AD DS, DNS, DHCP)"
    }
    @{
        Name     = "FS01"
        GuestOS  = "windows9-64"
        CPU      = 2;  RAM = 2048; Disk = 60
        Firmware = "bios"; TPM = $false
        NICs     = @( @{ Net = "LAN"; Dev = "vmxnet3" } )
        ISO      = @("*SERVER_EVAL*.iso", "*Windows_Server_2022*.iso")
        Note     = "Filserver - AGDLP-demoresurser"
    }
    @{
        Name     = "WIN11-01"
        GuestOS  = "windows11-64"
        CPU      = 2;  RAM = 4096; Disk = 60
        Firmware = "efi";  TPM = $true
        NICs     = @( @{ Net = "LAN"; Dev = "vmxnet3" } )
        ISO      = @("*Win11*.iso", "*windows_11*.iso")
        Note     = "Klient - GPO-test och attackmål"
    }
    @{
        Name     = "LNX-WEB01"
        GuestOS  = "ubuntu-64"
        CPU      = 1;  RAM = 2048; Disk = 25
        Firmware = "bios"
        NICs     = @( @{ Net = "DMZ"; Dev = "vmxnet3" } )
        ISO      = @("*ubuntu-24.04*server*.iso", "*ubuntu-24*.iso")
        Note     = "Webbserver i DMZ (DVWA)"
    }
    @{
        Name     = "LNX-DB01"
        GuestOS  = "ubuntu-64"
        CPU      = 1;  RAM = 2048; Disk = 25
        Firmware = "bios"
        NICs     = @( @{ Net = "DMZ"; Dev = "vmxnet3" } )
        ISO      = @("*ubuntu-24.04*server*.iso", "*ubuntu-24*.iso")
        Note     = "Databas i DMZ"
    }
    @{
        Name     = "SOC-WAZUH"
        GuestOS  = "ubuntu-64"
        CPU      = 4;  RAM = 8192; Disk = 100
        Firmware = "bios"
        NICs     = @( @{ Net = "SOC"; Dev = "vmxnet3" } )
        ISO      = @("*ubuntu-22.04*server*.iso", "*ubuntu-22*.iso")
        Note     = "Wazuh all-in-one SIEM"
    }
    @{
        Name     = "KALI-01"
        GuestOS  = "debian12-64"
        CPU      = 2;  RAM = 4096; Disk = 40
        Firmware = "bios"
        NICs     = @( @{ Net = "RED"; Dev = "vmxnet3" } )
        ISO      = @("*kali-linux*installer*.iso", "*kali*.iso")
        Note     = "Red Team - attackmaskin"
    }
)

# ------------------------------------------------------------------ 5. Hjälp: hitta ISO
function Resolve-ISOFile {
    param([string[]]$Patterns)
    foreach ($p in $Patterns) {
        $hit = Get-ChildItem -Path $ISOPath -Filter $p -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ------------------------------------------------------------------ 6. Skapa VM:er
Write-Step "Skapar virtuella maskiner"

$created = 0; $skipped = 0

foreach ($vm in $vms) {
    Write-Host "`n  --- $($vm.Name): $($vm.Note)" -ForegroundColor White

    $vmDir = Join-Path $VMPath $vm.Name
    $vmx   = Join-Path $vmDir "$($vm.Name).vmx"
    $vmdk  = Join-Path $vmDir "$($vm.Name).vmdk"

    if ((Test-Path $vmx)) {
        $overwrite = Read-Host "      $($vm.Name) finns redan. Skriva över? [j/N]"
        if ($overwrite -notmatch '^[JjYy]') {
            Write-Warn "Hoppar över $($vm.Name)"
            $skipped++
            continue
        }
    }

    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

    # --- Disk ---
    if (Test-Path $vmdk) {
        Write-Host "      Disk finns redan - behåller den" -ForegroundColor DarkGray
    } else {
        Write-Host "      Skapar disk: $($vm.Disk) GB..." -NoNewline
        $out = & $vdisk -c -s "$($vm.Disk)GB" -a lsilogic -t 0 $vmdk 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host " FEL" -ForegroundColor Red
            Write-Fail $out
            continue
        }
    }

    # --- ISO ---
    $iso = Resolve-ISOFile -Patterns $vm.ISO

    # --- .vmx-innehåll ---
    $lines = New-Object System.Collections.ArrayList

    [void]$lines.Add('.encoding = "UTF-8"')
    [void]$lines.Add('config.version = "8"')
    [void]$lines.Add('virtualHW.version = "20"')
    [void]$lines.Add("displayName = `"$($vm.Name)`"")
    [void]$lines.Add("guestOS = `"$($vm.GuestOS)`"")
    [void]$lines.Add("numvcpus = `"$($vm.CPU)`"")
    [void]$lines.Add("memsize = `"$($vm.RAM)`"")
    [void]$lines.Add("firmware = `"$($vm.Firmware)`"")
    [void]$lines.Add('')
    [void]$lines.Add('# --- Undvik frågor vid start ---')
    [void]$lines.Add('msg.autoAnswer = "TRUE"')
    [void]$lines.Add('hints.hideAll = "TRUE"')
    [void]$lines.Add('isolation.tools.autoInstall.disable = "FALSE"')
    [void]$lines.Add('')
    [void]$lines.Add('# --- Diskkontroller (LSI SAS) ---')
    [void]$lines.Add('scsi0.present = "TRUE"')
    [void]$lines.Add('scsi0.virtualDev = "lsisas1068"')
    [void]$lines.Add('scsi0:0.present = "TRUE"')
    [void]$lines.Add("scsi0:0.fileName = `"$($vm.Name).vmdk`"")
    [void]$lines.Add('scsi0:0.redo = ""')
    [void]$lines.Add('')

    # --- CD/DVD ---
    [void]$lines.Add('# --- CD/DVD ---')
    [void]$lines.Add('ide1:0.present = "TRUE"')
    [void]$lines.Add('ide1:0.deviceType = "cdrom-image"')
    if ($iso) {
        [void]$lines.Add("ide1:0.fileName = `"$iso`"")
        [void]$lines.Add('ide1:0.startConnected = "TRUE"')
    } else {
        [void]$lines.Add('ide1:0.fileName = ""')
        [void]$lines.Add('ide1:0.startConnected = "FALSE"')
    }
    [void]$lines.Add('ide1:0.autodetect = "TRUE"')
    [void]$lines.Add('')

    # --- Nätverk ---
    [void]$lines.Add('# --- Nätverk ---')
    for ($i = 0; $i -lt $vm.NICs.Count; $i++) {
        $nic = $vm.NICs[$i]
        $logicalNet = $nic.Net
        $vmnetName  = $Networks[$logicalNet].Vmnet

        [void]$lines.Add("ethernet$i.present = `"TRUE`"")
        [void]$lines.Add("ethernet$i.connectionType = `"custom`"")
        [void]$lines.Add("ethernet$i.vnet = `"$vmnetName`"")
        [void]$lines.Add("ethernet$i.virtualDev = `"$($nic.Dev)`"")
        [void]$lines.Add("ethernet$i.addressType = `"generated`"")
        [void]$lines.Add("ethernet$i.wakeOnPcktRcv = `"FALSE`"")
        [void]$lines.Add("ethernet$i.displayName = `"$logicalNet ($vmnetName)`"")
        [void]$lines.Add("")
    }

    # --- TPM för Windows 11 ---
    if ($vm.TPM) {
        [void]$lines.Add('# --- TPM (krävs för Windows 11) ---')
        [void]$lines.Add('tpm.present = "TRUE"')
        [void]$lines.Add('')
    }

    # --- Övrigt ---
    [void]$lines.Add('# --- Övrigt ---')
    [void]$lines.Add('usb.present = "TRUE"')
    [void]$lines.Add('usb_xhci.present = "TRUE"')
    [void]$lines.Add('sound.present = "FALSE"')
    [void]$lines.Add('sound.autoDetect = "FALSE"')
    [void]$lines.Add('mks.enable3d = "FALSE"')
    [void]$lines.Add('svga.autodetect = "TRUE"')
    [void]$lines.Add('pciBridge0.present = "TRUE"')
    [void]$lines.Add('pciBridge4.present = "TRUE"')
    [void]$lines.Add('pciBridge4.virtualDev = "pcieRootPort"')
    [void]$lines.Add('pciBridge5.present = "TRUE"')
    [void]$lines.Add('pciBridge5.virtualDev = "pcieRootPort"')
    [void]$lines.Add('pciBridge6.present = "TRUE"')
    [void]$lines.Add('pciBridge6.virtualDev = "pcieRootPort"')
    [void]$lines.Add('pciBridge7.present = "TRUE"')
    [void]$lines.Add('pciBridge7.virtualDev = "pcieRootPort"')
    [void]$lines.Add('vmci0.present = "TRUE"')
    [void]$lines.Add('tools.upgrade.policy = "manual"')
    [void]$lines.Add('floppy0.present = "FALSE"')
    [void]$lines.Add('serial0.present = "FALSE"')
    [void]$lines.Add('parallel0.present = "FALSE"')
    [void]$lines.Add('nvme0.present = "FALSE"')
    [void]$lines.Add('checkpoint.vmState = ""')
    [void]$lines.Add('powerType.powerOff = "default"')
    [void]$lines.Add('powerType.powerOn = "default"')
    [void]$lines.Add('powerType.suspend = "default"')
    [void]$lines.Add('powerType.reset = "default"')
    [void]$lines.Add('uuid.action = "create"')

    $lines | Set-Content -Path $vmx -Encoding ASCII
    Write-OK ".vmx skapad: $vmx"
    if ($iso) {
        Write-OK "ISO kopplad: $(Split-Path $iso -Leaf)"
    } else {
        Write-Warn "Ingen ISO hittades (sökte: $($vm.ISO -join ', ')) - koppla manuellt"
    }
    $created++
}

# ------------------------------------------------------------------ 7. IP på värden
if ($ConfigureHostIP) {
    Write-Step "Sätter statisk IP på värdens SOC-adapter"

    $socAdapter = $hostAdapters | Where-Object { $_.Name -like "*VMnet12*" } | Select-Object -First 1

    if (-not $socAdapter) {
        Write-Fail "Hittade ingen VMnet12-adapter på värden. Skapa nätet först."
    } else {
        $existing = Get-NetIPAddress -InterfaceIndex $socAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq "192.168.30.2" }
        if ($existing) {
            Write-OK "192.168.30.2 redan satt på $($socAdapter.Name)"
        } else {
            try {
                New-NetIPAddress -InterfaceIndex $socAdapter.InterfaceIndex `
                                 -IPAddress 192.168.30.2 -PrefixLength 24 -ErrorAction Stop | Out-Null
                Write-OK "192.168.30.2 satt på $($socAdapter.Name)"
                Write-Host "      -> Du kan nu nå Wazuh på https://192.168.30.10 direkt från värden" -ForegroundColor Green
            } catch {
                Write-Warn "Kunde inte sätta IP: $($_.Exception.Message)"
            }
        }
    }
}

# ------------------------------------------------------------------ 8. Registrera
Write-Step "Registrerar maskinerna i VMware"

$registered = 0
foreach ($vm in $vms) {
    $vmx = Join-Path $VMPath "$($vm.Name)\$($vm.Name).vmx"
    if (-not (Test-Path $vmx)) { continue }

    # vmrun start registrerar automatiskt i Workstation-biblioteket
    $out = & $vmrun -T ws start "$vmx" nogui 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "$($vm.Name) registrerad och startad"
        $registered++
        Start-Sleep -Seconds 2
        # Stäng direkt - vi vill installera i kontrollerad ordning
        & $vmrun -T ws stop "$vmx" soft 2>&1 | Out-Null
    } else {
        Write-Warn "$($vm.Name): $out"
    }
}

# ------------------------------------------------------------------ Starta
if ($Start) {
    Write-Step "Startar FW-01"
    $vmx = Join-Path $VMPath "FW-01\FW-01.vmx"
    & $vmrun -T ws start "$vmx"
}

# ------------------------------------------------------------------ Sammanfattning
Write-Banner "KLART!"

Write-Host "  Skapade:   $created maskiner" -ForegroundColor Green
Write-Host "  Hoppade:   $skipped"          -ForegroundColor Gray
Write-Host "  Registrerade: $registered"    -ForegroundColor Green

Write-Host "`n  Natverkskarta:" -ForegroundColor Cyan
Write-Host "    (WAN/VMnet$($WanNetwork -replace 'VMnet','') behaller VMware:s standard - andra det inte)" -ForegroundColor DarkGray
foreach ($net in $Networks.GetEnumerator()) {
    Write-Host ("    {0,-5} -> {1,-8} {2}" -f $net.Key, $net.Value.Vmnet, $net.Value.Subnet)
}

Write-Host @"

  ============================================================
    NÄSTA STEG
  ============================================================

  1. Öppna VMware Workstation. Alla 8 maskiner ligger nu i biblioteket.

  2. Starta FW-01 och installera OPNsense.
     VIKTIGT: välj "Other/FreeBSD 64-bit" som gäst-OS om du skapar om manuellt.
     Se docs/02-opnsense-brandvagg.md

  3. Lägg märke till MAC-adresserna - de är nyckeln till att veta vilket
     nätverkskort som blir hn0/hn1/hn2/hn3 i OPNsense:
       Högerklicka VM -> Settings -> Network Adapter -> Advanced -> MAC Address

  4. ANVÄNDBARA KOMMANDON (från PowerShell):

       `$vmrun = "$vmrun"

       # Lista alla körande maskiner
       & `$vmrun list

       # Starta / stänga
       & `$vmrun -T ws start "D:\Lab\VMs\DC-01\DC-01.vmx"
       & `$vmrun -T ws stop  "D:\Lab\VMs\DC-01\DC-01.vmx" soft

       # SNAPSHOTS (VMware motsvarighet till Hyper-V checkpoints)
       & `$vmrun -T ws snapshot "D:\Lab\VMs\DC-01\DC-01.vmx" "Fas3-innan-AD"
       & `$vmrun -T ws listSnapshots "D:\Lab\VMs\DC-01\DC-01.vmx"
       & `$vmrun -T ws revertToSnapshot "D:\Lab\VMs\DC-01\DC-01.vmx" "Fas3-innan-AD"
       & `$vmrun -T ws deleteSnapshot "D:\Lab\VMs\DC-01\DC-01.vmx" "Fas3-innan-AD"

  5. Installationsordning:
       FW-01 -> DC-01 -> WIN11-01/FS01 -> LNX-WEB01/LNX-DB01 -> SOC-WAZUH -> KALI-01

  6. Fortsätt med: docs/01-hypervisor-och-vswitch.md (klar-checklistan)

"@ -ForegroundColor Yellow
