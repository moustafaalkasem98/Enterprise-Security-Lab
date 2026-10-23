<#
.SYNOPSIS
    Gör labbet nåbart från värddatorn - och varnar om WiFi/Ethernet krockar.

.DESCRIPTION
    Detta skript löser det vanligaste problemet när man bygger labbet på en
    bärbar dator som är kopplad via WiFi:

      1. Kontrollerar om ditt FYSISKA nät (WiFi/Ethernet) ligger i samma subnät
         som något av labbnäten. Krockar de, blir routningen på värden
         oberäknelig - och adresser som 192.168.10.1 kan peka på din
         hemmarouter istället för OPNsense.
      2. Sätter statisk IP på värdens VMnet-adaptrar (SOC + LAN).
      3. Verifierar att OPNsense och övriga labbmaskiner svarar.

    Skriptet ÄNDRAR INGET på ditt WiFi - det rapporterar bara problem.

.PARAMETER SetIPs
    Sätt statiska IP-adresser på värdens VMnet-adaptrar. Kräver administratör.

.PARAMETER LabOctet
    Tredje oktetten i labbnäten. Standard 10/20/30/40 (192.168.10.0/24 ...).
    Använd t.ex. 110 (192.168.110.0/24) om ditt WiFi krockar.

.PARAMETER Test
    Ping-testa OPNsense och labbmaskinerna efter konfiguration.

.EXAMPLE
    # 1. Kör först UTAN parametrar - kollar WiFi-krock OCH .1-konflikt
    .\Set-LabHostAccess.ps1

    # 2. Åtgärda allt: ta bort .1, sätt .2 på LAN+SOC, testa
    .\Set-LabHostAccess.ps1 -SetIPs -Test

.EXAMPLE
    # Om ditt WiFi ligger på 192.168.10.x - flytta labbet till 192.168.110.x
    .\Set-LabHostAccess.ps1 -LabOctet 110 -SetIPs -Test

.NOTES
    Kräver: VMware Workstation med VMnet10-13 skapade (se docs/01)
            Administratörsrättigheter för -SetIPs
#>

[CmdletBinding()]
param(
    [switch]$SetIPs,
    [int[]]$LabOctet  = @(10, 20, 30, 40),

    # Vilka labbnät värddatorn ska ha en adress i.
    # Standard: LAN (10) för OPNsense GUI + SOC (30) för Wazuh.
    # Värddatorn behöver INTE vara med i DMZ och RED.
    [int[]]$HostNets  = @(10, 30),

    [switch]$AllNets,   # ge värden adress i alla fyra labbnäten istället
    [switch]$Test
)

$ErrorActionPreference = "Continue"

if ($AllNets) { $HostNets = $LabOctet }

function Write-Step { param($m) Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-OK    { param($m) Write-Host "    [OK]  $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "    [!]   $m" -ForegroundColor Yellow }
function Write-Bad   { param($m) Write-Host "    [X]   $m" -ForegroundColor Red }

# ------------------------------------------------------------------ Hjälpfunktioner
function Get-NetworkAddress {
    param([string]$IPAddress, [int]$PrefixLength)
    try {
        $ipBytes   = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
        if ($ipBytes.Length -ne 4) { return $null }
        [Array]::Reverse($ipBytes)
        $ipInt = [System.BitConverter]::ToUInt32($ipBytes, 0)
        $mask  = if ($PrefixLength -eq 0) { 0 } else { [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $PrefixLength)) }
        $netInt = $ipInt -band $mask
        $netBytes = [System.BitConverter]::GetBytes($netInt)
        [Array]::Reverse($netBytes)
        return ($netBytes -join '.')
    } catch { return $null }
}

if ($SetIPs) {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "-SetIPs kräver att PowerShell körs som administratör."
    }
}

Write-Host @"

  ============================================================
    SOC HOME LAB - Åtkomst från värddatorn
  ============================================================

"@ -ForegroundColor Magenta

# ------------------------------------------------------------------ 1. Fysiskt nät
Write-Step "Kontrollerar ditt fysiska nät (WiFi / Ethernet)"

$physical = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike "*VMware*" }

$physicalNets = @()

if (-not $physical) {
    Write-Warn "Hittade inga aktiva fysiska nätverkskort."
} else {
    foreach ($a in $physical) {
        $ipv4 = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" }

        foreach ($ip in $ipv4) {
            $net = Get-NetworkAddress -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength
            $type = if ($a.PhysicalMediaType -like "*Wireless*" -or $a.InterfaceDescription -like "*Wi-Fi*" -or $a.InterfaceDescription -like "*Wireless*") { "WiFi" } else { "Ethernet" }

            Write-Host "    $type  $($a.Name.PadRight(20)) $($ip.IPAddress.PadRight(16))/$($ip.PrefixLength)  nät: $net" -ForegroundColor Gray
            $physicalNets += [PSCustomObject]@{
                Adapter = $a.Name
                Type    = $type
                IP      = $ip.IPAddress
                Network = $net
                Prefix  = $ip.PrefixLength
            }
        }
    }
}

# ------------------------------------------------------------------ 2. Krocktest
Write-Step "Krocktest: fysiskt nät vs labbnät"

$labNets = foreach ($o in $LabOctet) { "192.168.$o.0" }
$collisions = @()

foreach ($p in $physicalNets) {
    foreach ($l in $labNets) {
        if ($p.Network -eq $l) {
            $collisions += [PSCustomObject]@{ Physical = "$($p.Type) $($p.Adapter) ($($p.Network)/$($p.Prefix))"; Lab = $l }
        }
    }
}

if ($collisions.Count -eq 0) {
    Write-OK "Ingen krock - ditt fysiska nät ligger inte i något labbnät."
} else {
    Write-Bad "KROCK UPPTÄCKT! Detta MÅSTE åtgärdas."
    Write-Host ""
    foreach ($c in $collisions) {
        Write-Host "         Fysiskt nät : $($c.Physical)"
        Write-Host "         Labbnät     : $($c.Lab)/24"
        Write-Host ""
    }
    Write-Host @"
    Vad händer om du kör ändå?
      Din värddator får TVÅ nätverkskort i samma subnät. Windows vet inte
      vilket den ska använda, så adresser som 192.168.10.1 kan hamna på din
      hemmarouter istället för OPNsense. Resultatet blir att vissa anslutningar
      fungerar och andra inte - utan någon logisk förklaring.

    Lösning: flytta labbnäten till en oktett som inte används.
      Föreslaget: 110 / 120 / 130 / 140  (nästan aldrig använt av hemmaroutrar)

      Kör sedan:
        .\Set-LabHostAccess.ps1 -LabOctet 110 -SetIPs -Test

      Och uppdatera IP-planen i:
        docs/00-planering-och-topologi.md
        docs/02-opnsense-brandvagg.md
        config/wazuh/custom-rules/opnsense_rules.xml   (192.168.10/20/30/40)
        scripts/host/setup-vmware.ps1                  (-LabNetworks)

"@ -ForegroundColor Yellow
}

# ------------------------------------------------------------------ 3. VMware-adaptrar + .1-konflikt
Write-Step "Letar efter VMware-nätverkskort på värden"

$vmAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
              Where-Object { $_.InterfaceDescription -like "*VMware*" } |
              Sort-Object Name

if (-not $vmAdapters) {
    Write-Bad "Hittade inga VMware-nätverkskort."
    Write-Host "      Skapa VMnet10-13 i Virtual Network Editor först (docs/01 steg 1.3)."
    exit 1
}

# VMware ger automatiskt värddatorns host-only-adapter adressen .1 i subnätet.
# Men .1 är OPNsense gateway-adress i vårt labb -> garanterad IP-konflikt.
$gatewayConflicts = @()

foreach ($a in $vmAdapters) {
    $ips = @(Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -notlike "169.254.*" })

    $vmnetNum = if ($a.Name -match 'VMnet(\d+)') { $Matches[1] } else { "" }
    $isLabNet = ($LabOctet -contains [int]$vmnetNum)

    foreach ($ip in $ips) {
        $last = ($ip.IPAddress -split '\.')[-1]
        $flag = ""
        if ($isLabNet -and $last -eq "1") {
            $flag = "  <-- KONFLIKT! Denna adress ska OPNsense ha"
            $gatewayConflicts += [PSCustomObject]@{ Adapter = $a.Name; IP = $ip.IPAddress }
        }
        $color = if ($flag) { "Red" } else { "Gray" }
        Write-Host ("    " + $a.Name.PadRight(40) + $ip.IPAddress.PadRight(18) + $flag) -ForegroundColor $color
    }
    if ($ips.Count -eq 0) {
        Write-Host ("    " + $a.Name.PadRight(40) + "ingen IP") -ForegroundColor DarkGray
    }
}

if ($gatewayConflicts.Count -gt 0) {
    Write-Host ""
    Write-Bad "Värddatorn har tagit gateway-adressen (.1) i $($gatewayConflicts.Count) labbnät."
    Write-Host @"

    Detta är VMware:s standardbeteende: host-only-adaptern får alltid .1.
    Men i vårt labb är .1 OPNsense gränssnittsadress - så de krockar.

    Symptom:  - https://192.168.10.1 öppnar INTE OPNsense (träffar värden istället)
              - Windows visar "IP-adresskonflikt"
              - OPNsense loggar "duplicate address"

    Lösning:  kör skriptet med -SetIPs så tas .1 bort och .2 sätts istället.

"@ -ForegroundColor Yellow
}

# ------------------------------------------------------------------ 4. Sätt IP
if ($SetIPs) {

    Write-Step "Städar gateway-adresser (.1) från värdens labbadaptrar"

    # STEG A: ta ALLTID bort .1 från samtliga labbnät - det är OPNsenses adress.
    foreach ($o in $LabOctet) {
        $adapter = $vmAdapters | Where-Object { $_.Name -like "*VMnet$o*" } | Select-Object -First 1
        if (-not $adapter) { continue }

        $gw = "192.168.$o.1"
        $existing = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq $gw }
        if ($existing) {
            try {
                Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                                    -IPAddress $gw -Confirm:$false -ErrorAction Stop
                Write-OK "Tog bort $gw från $($adapter.Name) (OPNsenses adress)"
            } catch {
                Write-Bad "Kunde inte ta bort $gw : $($_.Exception.Message)"
                Write-Host "      Gör det manuellt: Nätverksanslutningar -> adaptern -> IPv4-egenskaper"
            }
        } else {
            Write-Host "    $($adapter.Name): ingen .1 att ta bort" -ForegroundColor DarkGray
        }
    }

    Write-Step "Sätter värdens adresser (.2)"

    # STEG B: sätt .2 på de nät värden faktiskt ska nå.
    foreach ($o in $HostNets) {
        $adapter = $vmAdapters | Where-Object { $_.Name -like "*VMnet$o*" } | Select-Object -First 1

        if (-not $adapter) {
            Write-Warn "Ingen VMnet$o-adapter - hoppar över (skapa nätet i Virtual Network Editor)"
            continue
        }

        $desiredIP = "192.168.$o.2"

        if (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $desiredIP }) {
            Write-OK "$($adapter.Name): $desiredIP redan satt"
            continue
        }

        try {
            New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                             -IPAddress $desiredIP -PrefixLength 24 -ErrorAction Stop | Out-Null
            Write-OK "$($adapter.Name): $desiredIP satt"
        } catch {
            Write-Bad "$($adapter.Name): $($_.Exception.Message)"
        }
    }

    # STEG C: nät där värden INTE ska ha adress - ta bort .2 om det fanns
    foreach ($o in ($LabOctet | Where-Object { $HostNets -notcontains $_ })) {
        $adapter = $vmAdapters | Where-Object { $_.Name -like "*VMnet$o*" } | Select-Object -First 1
        if (-not $adapter) { continue }
        $extra = "192.168.$o.2"
        $hit = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.IPAddress -eq $extra }
        if ($hit) {
            Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $extra -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "    $($adapter.Name): tog bort $extra (värden behöver inte vara i detta nät)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "    Värden har nu bara adress i: $(($HostNets | ForEach-Object { "192.168.$_.0/24" }) -join ', ')" -ForegroundColor Cyan
    Write-Host "    (Windows har IP-forwarding avstängt som standard, så värden routar inte mellan näten)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------ 5. Test
if ($Test) {

    Write-Step "Testar anslutning till labbet"

    $targets = @(
        @{ IP = "192.168.$($LabOctet[0]).1";  Name = "OPNsense LAN-gateway" }
        @{ IP = "192.168.$($LabOctet[0]).10"; Name = "DC-01" }
        @{ IP = "192.168.$($LabOctet[2]).10"; Name = "SOC-WAZUH" }
    )

    foreach ($t in $targets) {
        $result = Test-NetConnection -ComputerName $t.IP -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Write-OK "$($t.Name.PadRight(24)) $($t.IP)  svarar"
        } else {
            Write-Warn "$($t.Name.PadRight(24)) $($t.IP)  svarar INTE (kanske inte installerad ännu)"
        }
    }
}

# ------------------------------------------------------------------ Sammanfattning
Write-Host @"

  ============================================================
    SÅ HÄR NÅR DU LABBET
  ============================================================

  Från webbläsaren på DENNA dator (värden):

    OPNsense GUI   https://192.168.$($LabOctet[0]).1
    Wazuh SIEM     https://192.168.$($LabOctet[2]).10

  DHCP-adress i labbnätet (från DC-01) behövs INTE - värdens
  VMnet-adapter är direkt ansluten till labbnätet.

  Det spelar INGEN roll att du är på WiFi:
    - VMnet10-13 är host-only och finns bara inne i denna dator
    - VMnet8 (NAT) ger internet till VM:erna oavsett WiFi eller kabel
    - Det är bara BRIDGED (VMnet0) som är opålitligt över WiFi - och
      det använder vi inte i detta labb.

  Når du inte GUI:t? Kolla i tur och ordning:
    1. Är FW-01 igång?
    2. Har värdens VMnet-adapter rätt IP? (kör detta skript)
    3. Krockar WiFi med labbnätet? (kör detta skript utan -SetIPs)
    4. Windows-brandväggen på värden blockerar? Prova att stänga av tillfälligt.
    5. Har du satt IP på OPNsense LAN-interfacet? Se docs/02 steg 2.3.1

"@ -ForegroundColor Cyan

if ($collisions.Count -gt 0) {
    Write-Host "  ⚠️  Åtgärda krocken ovan innan du fortsätter!`n" -ForegroundColor Red
}
