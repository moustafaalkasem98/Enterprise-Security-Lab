# Brandväggsregelverk – implementerat läge

> **Sammanfattning**
> Det faktiska regelverket såsom det är implementerat på FW-01 (OPNsense 24.x).
> Syftet med dokumentet är att göra regelverket granskningsbart utan åtkomst till
> brandväggen — varje regel ska kunna härledas till en motivering.
>
> **Plattform:** OPNsense 24.x · **Regelordning:** top-down, första matchande regel vinner
> **Status:** implementerat och verifierat för LAN, DMZ, SOC och RED

---

## 1. Princip

Regelverket bygger på default-deny: all trafik blockeras implicit och varje tillåtet
flöde uttrycks av en explicit regel. Samtliga regler — inklusive blockeringar — har
loggning aktiverad, eftersom en ologgad regel är osynlig för SIEM:et.

Evaluering sker uppifrån och ned; den första matchande regeln avgör. Ordningen i
tabellerna nedan är därför den faktiska ordningen i OPNsense.

---

## 2. LAN – `192.168.10.0/24`

| # | Action | Proto | Källa | Destination | Port | Logg | Motivering |
|---:|---|---|---|---|---|:---:|---|
| 1 | Pass | TCP/UDP | LAN net | `192.168.10.10` | 53, 123 | Ja | DNS och NTP från domänkontrollanten |
| 2 | Pass | TCP | LAN net | SOC net | 1514, 1515 | Ja | Wazuh-agent mot manager |
| 3 | Pass | TCP/UDP | LAN net | SOC net | 514 | Ja | Utgående syslog |
| 4 | Block | any | LAN net | RED net | any | Ja | LAN ska inte nå attackzonen |
| 5 | Pass | any | LAN net | any | any | Ja | Övrig utgående trafik |

---

## 3. DMZ – `192.168.20.0/24`

| # | Action | Proto | Källa | Destination | Port | Logg | Motivering |
|---:|---|---|---|---|---|:---:|---|
| 1 | Pass | TCP/UDP | DMZ net | `192.168.10.10` | 53, 123 | Ja | DNS och NTP |
| 2 | Pass | TCP | DMZ net | `192.168.30.10` | 1514, 1515 | Ja | Wazuh-agent mot manager |
| 3 | Pass | TCP/UDP | DMZ net | `192.168.30.10` | 514 | Ja | Utgående syslog |
| 4 | Block | any | DMZ net | LAN net | any | Ja | **Bryter lateral rörelse från exponerad zon till identitetsinfrastrukturen** |
| 5 | Block | any | DMZ net | RED net | any | Ja | Komprometterad server ska inte kunna initiera trafik mot attackzonen |
| 6 | Pass | any | DMZ net | any | any | Ja | Utgående tjänsteåtkomst |

Regel 4 är den enskilt viktigaste i regelverket: den innebär att en kompromettering
av webbservern i DMZ inte ger nätverksmässig väg till Active Directory.

---

## 4. SOC – `192.168.30.0/24`

| # | Action | Proto | Källa | Destination | Port | Logg | Motivering |
|---:|---|---|---|---|---|:---:|---|
| 1 | Pass | TCP | SOC net | LAN net | 445, 3389, 5985 | Ja | Administration av Windows (SMB, RDP, WinRM) |
| 2 | Pass | TCP | SOC net | DMZ net | 22 | Ja | Administration av Linux |
| 3 | Block | any | SOC net | RED net | any | Ja | SIEM-zonen ska inte vara nåbar från attackzonen |
| 4 | Pass | any | SOC net | any | any | Ja | Övrig trafik från managementzonen |

---

## 5. RED – `192.168.40.0/24`

| # | Action | Proto | Källa | Destination | Port | Logg | Motivering |
|---:|---|---|---|---|---|:---:|---|
| 1 | Pass | TCP | RED net | `192.168.30.10` | 1514, 1515 | Ja | Agentkommunikation från KALI-01 |
| 2 | Block | any | RED net | LAN net | any | Ja | **Tvingar pivoting via DMZ; ger detektionspunkter i flera lager** |
| 3 | Block | any | RED net | SOC net | any | Ja | Skyddar SIEM:et (undantag: regel 1) |
| 4 | Pass | any | RED net | DMZ net | any | Ja | Attackövningens huvudscenario |
| 5 | Block | any | RED net | any | any | Ja | Default-deny |

Regel 2 är avsiktligt utformad för att inte helt stoppa en angripare, utan för att
tvinga fram en omväg via DMZ. Det ger två detektionsmöjligheter i stället för en.

---

## 6. Verifiering

Segmenteringen verifieras genom att mäta faktisk nåbarhet mellan zonerna.

| Test | Från | Till | Förväntat resultat | Observed | Regel-ID |
|---|---|---|---|---|---|
| DMZ nåbar | RED | `192.168.20.10` | Svarar | ✅ Svarar | 4 (RED) |
| LAN blockat | RED | `192.168.10.10` | Timeout | ✅ Timeout | 100010 |
| SOC blockat | RED | `192.168.30.10` | Timeout | ✅ Timeout | 100011 |
| LAN blockat | DMZ | `192.168.10.10` | Timeout | ✅ Timeout | 100003 |

Samtliga blockeringar genererar loggposter i OPNsense filterlog och vidarebefordras
till Wazuh enligt [`syslog-setup.md`](syslog-setup.md). Detektionsreglerna som
matchar dessa poster publiceras i fas 7.

---

## 7. Avvikelser från design

| Avvikelse | Orsak | Konsekvens |
|---|---|---|
| DHCP-server Kea används i stället för ISC DHCPv4 | ISC DHCPv4 är borttaget i OPNsense 24.7+ | Router- och DNS-optioner måste skapas separat under Kea → Options och sedan väljas i subnätet |
| Värdens adress på LAN är `.2`, inte `.1` | VMware tilldelar värden `.1` i varje host-only-nät, vilket kolliderar med brandväggens gateway | Hanteras av [`scripts/host/Set-LabHostAccess.ps1`](../../scripts/host/Set-LabHostAccess.ps1) |

---

*Senast verifierat: 2026-10 · Gäller FW-01 (OPNsense 24.x)*
