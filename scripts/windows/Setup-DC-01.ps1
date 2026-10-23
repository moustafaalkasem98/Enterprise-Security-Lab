<#
.SYNOPSIS
    Grundkonfiguration av DC-01 innan AD-promotion.

.DESCRIPTION
    Körs DIREKT efter att Windows Server installerats (innan domänen skapas):
      - Döper om datorn till DC-01
      - Sätter statisk IP, gateway och DNS
      - Aktiverar RDP
      - Sätter tidszon + NTP
      - Installerar AD DS, DNS, DHCP + RSAT

.PARAMETER IPAddress
    Statisk IP för DC-01. Default: 192.168.10.10

.PARAMETER Gateway
    Gateway (OPNsense LAN). Default: 192.168.10.1

.PARAMETER InterfaceAlias
    Namn på nätverkskortet. Kör Get-NetAdapter först. Default: Ethernet

.EXAMPLE
    .\Setup-DC-01.ps1
    # Startar sedan automatiskt om. Kör sedan Install-ADDSForest manuellt.
#>

[CmdletBinding()]
param(
    [string]$IPAddress      = "192.168.10.10",
    [string]$Gateway        = "192.168.10.1",
    [string]$InterfaceAlias = "Ethernet",
    [switch]$SkipReboot
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host @"

  ============================================================
    DC-01 - Grundkonfiguration
  ============================================================

"@ -ForegroundColor Cyan

# ------------------------------------------------------------------ 0. Hitta nätverkskort
$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
if (-not $adapter) {
    Write-Host "Hittade inte '$InterfaceAlias'. Tillgängliga nätverkskort:" -ForegroundColor Yellow
    Get-NetAdapter | Where-Object Status -ne 'Disabled' | Format-Table Name, InterfaceDescription, Status -AutoSize
    $InterfaceAlias = (Read-Host "Ange namnet på nätverkskortet").Trim()
    $adapter = Get-NetAdapter -Name $InterfaceAlias
}

# ------------------------------------------------------------------ 1. Döp om
if ($env:COMPUTERNAME -ne "DC-01") {
    Write-Host "[1/6] Döper om datorn till DC-01..." -ForegroundColor Cyan
    Rename-Computer -NewName "DC-01" -Force
    $renamed = $true
} else {
    Write-Host "[1/6] Datorn heter redan DC-01" -ForegroundColor Green
    $renamed = $false
}

# ------------------------------------------------------------------ 2. Nätverk
Write-Host "[2/6] Sätter statisk IP $IPAddress/24, gateway $Gateway..." -ForegroundColor Cyan

# Ta bort befintliga adresser (utom APIPA)
Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" } |
    ForEach-Object {
        Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
Remove-NetRoute -InterfaceAlias $InterfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
Write-Host "      [OK] IP satt" -ForegroundColor Green

# DNS pekar på OPNsense - INTE 127.0.0.1 ännu!
# Det finns ingen DNS-server på 127.0.0.1 förrän AD är installerat. Pekar man dit
# nu dör all namnuppslagning (typiskt symptom: w32tm "no time data available").
# Byt till 127.0.0.1 först EFTER Install-ADDSForest (se avslutningsmeddelandet).
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $Gateway
Write-Host "      [OK] DNS = $Gateway (OPNsense) - byt till 127.0.0.1 EFTER AD-promotion" -ForegroundColor Green

# ------------------------------------------------------------------ 3. RDP
Write-Host "[3/6] Aktiverar Remote Desktop..." -ForegroundColor Cyan
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1  # Kräv NLA
Write-Host "      [OK] RDP aktiverat (NLA påkrävet)" -ForegroundColor Green

# ------------------------------------------------------------------ 4. Tid
Write-Host "[4/6] Konfigurerar tidszon och NTP..." -ForegroundColor Cyan
Set-TimeZone -Id "W. Europe Standard Time"
w32tm /config /syncfromflags:manual /manualpeerlist:"0.se.pool.ntp.org,1.se.pool.ntp.org,2.se.pool.ntp.org" /update | Out-Null
Restart-Service w32time -Force
w32tm /resync | Out-Null
Write-Host "      [OK] $((Get-TimeZone).Id)" -ForegroundColor Green

# ------------------------------------------------------------------ 5. Roller
Write-Host "[5/6] Installerar AD DS, DNS, DHCP och RSAT (tar några minuter)..." -ForegroundColor Cyan

$features = @(
    "AD-Domain-Services",
    "DNS",
    "DHCP",
    "RSAT-ADDS",
    "RSAT-AD-PowerShell",
    "RSAT-ADDS-Tools",
    "RSAT-DNS-Server",
    "RSAT-DHCP",
    "GPMC"
)

foreach ($f in $features) {
    $result = Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction SilentlyContinue
    if ($result.Success) { Write-Host "      [OK] $f" -ForegroundColor Green }
    else                 { Write-Host "      [!] $f : $($result.ExitCode)" -ForegroundColor Yellow }
}

# ------------------------------------------------------------------ 6. Windows Update & säkerhet (valfritt)
Write-Host "[6/6] Grundläggande härdning..." -ForegroundColor Cyan

# Inaktivera IPv6 om du inte använder det (valfritt - vanligt i labb)
# Set-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6 -Enabled $false

# Stäng av SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Write-Host "      [OK] SMBv1 avstängt" -ForegroundColor Green

# Aktivera PowerShell-loggning
$psLogPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell"
New-Item -Path "$psLogPath\ScriptBlockLogging" -Force | Out-Null
Set-ItemProperty -Path "$psLogPath\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1
New-Item -Path "$psLogPath\ModuleLogging" -Force | Out-Null
Set-ItemProperty -Path "$psLogPath\ModuleLogging" -Name "EnableModuleLogging" -Value 1
Set-ItemProperty -Path "$psLogPath\ModuleLogging" -Name "ModuleNames" -Value "*"
New-Item -Path "$psLogPath\Transcription" -Force | Out-Null
Set-ItemProperty -Path "$psLogPath\Transcription" -Name "EnableTranscripting" -Value 1
Set-ItemProperty -Path "$psLogPath\Transcription" -Name "OutputDirectory" -Value "C:\PSLogs"
New-Item -ItemType Directory -Path "C:\PSLogs" -Force | Out-Null
Write-Host "      [OK] PowerShell-loggning aktiverad (C:\PSLogs)" -ForegroundColor Green

# ------------------------------------------------------------------ Klar
Write-Host @"

  ============================================================
    GRUNDINSTALLATION KLAR
  ============================================================

"@ -ForegroundColor Green

Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer

if ($renamed) {
    Write-Host "Datorn har döpts om och måste starta om." -ForegroundColor Yellow
    if (-not $SkipReboot) {
        $svar = Read-Host "Starta om nu? [J/N]"
        if ($svar -eq 'J' -or $svar -eq 'j') { Restart-Computer -Force }
    }
}

Write-Host @"

  EFTER OMBOOT - kör detta för att skapa domänen:

    Install-ADDSForest ``
        -DomainName "soclab.local" ``
        -DomainNetbiosName "SOCLAB" ``
        -DomainMode "WinThreshold" ``
        -ForestMode "WinThreshold" ``
        -DatabasePath "C:\Windows\NTDS" ``
        -LogPath "C:\Windows\NTDS" ``
        -SysvolPath "C:\Windows\SYSVOL" ``
        -InstallDns:`$true ``
        -Force:`$true

  EFTER OMBOOTEN (när du är inloggad som SOCLAB\Administrator) - byt DNS:

    Set-DnsClientServerAddress -InterfaceAlias "$InterfaceAlias" -ServerAddresses 127.0.0.1,$Gateway

  Nu finns det äntligen en AD-integrerad DNS-server lokalt, och OPNsense ligger
  kvar som andrahands-DNS för externa namn.

  Fortsätt sedan med docs/03-windows-server-dc.md

"@ -ForegroundColor Cyan
