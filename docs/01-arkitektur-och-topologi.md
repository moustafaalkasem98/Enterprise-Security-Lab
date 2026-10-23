# Arkitektur & designbeslut

> **Sammanfattning**
> En isolerad företagsmiljö byggd för att öva både anfall och försvar: ett segmenterat
> nätverk bakom en OPNsense-brandvägg, en Windows Server-domän med AGDLP-baserad
> behörighetsmodell, härdade Linux-servrar och ett Wazuh-SIEM som korrelerar loggar
> från samtliga lager. Miljön används för att köra kontrollerade attacker från ett
> avgränsat RED-segment och därefter analysera avtrycken i SIEM:et.
>
> **Status:** fas 0–2 genomförda (hypervisor, brandvägg, segmentering). Fas 3 pågår.

---

## 1. Syfte och omfattning

### Syfte

Syftet är att demonstrera praktisk förmåga inom fyra områden:

| Område | Vad miljön ska bevisa |
|---|---|
| **Nätverkssegmentering** | Att designa och verifiera zonindelning med default-deny |
| **Identitet & behörighet** | Att bygga en skalbar RBAC-modell enligt AGDLP |
| **Härdning** | Att tillämpa kända riktlinjer (CIS, Microsoft Security Baselines) |
| **Detektion & respons** | Att samla loggar, bygga egna regler och tolka larm |

### Omfattning

**Ingår**

- Fyra interna segment (LAN, DMZ, SOC, RED) samt simulerat WAN via NAT
- Active Directory med tiering, AGDLP och GPO-härdning
- Linux-servrar med nyckelbaserad SSH, fail2ban, auditd och AIDE
- Centraliserad loggning till Wazuh med egna decoders och regler
- Kontrollerad attacksimulering med efterföljande detektionsanalys

**Ingår inte**

- Exponering mot internet eller molntjänster
- Produktionsdata — samtliga data är syntetisk testdata
- Hög tillgänglighet (klustring, failover)
- EDR/SOAR (identifierat som nästa steg, se nedan)

---

## 2. Designprinciper

Samtliga principer nedan är styrande för varje tekniskt val i miljön.

| # | Princip | Motivering |
|---|---|---|
| 1 | **Default-deny** | All trafik blockeras implicit; varje tillåten flöde måste vara explicit motiverat. En tillåtande baseline gör brandväggen verkningslös. |
| 2 | **Segmentering efter tillit, inte efter plats** | Varje zon tilldelas en tillitsnivå och får endast nå zoner med lägre eller lika tillit efter explicit regel. |
| 3 | **Loggning på samtliga regler** | En regel utan loggning är osynlig för SIEM:et. Blockeringar är ofta mer intressanta än tillåtna flöden. |
| 4 | **Minsta behörighet via grupper** | Behörighet ges aldrig direkt till användare utan via roller (AGDLP). Det gör behörigheten granskbar och återkallelsebar. |
| 5 | **Centraliserad tid** | Kerberos tolererar maximalt fem minuters avvikelse. Alla system synkroniserar mot brandväggen, som i sin tur synkroniserar mot externa NTP-källor. |
| 6 | **Isolering från produktionsnät** | Miljön körs helt på host-only-nät bakom NAT. Ingen del av labbet är nåbar utifrån. |
| 7 | **Återställningsbarhet** | Snapshots tas före varje destruktivt moment, särskilt före GPO-ändringar och attackövningar. |

---

## 3. Plattform

### Val av hypervisor

**Vald plattform: VMware Workstation Pro.**

| Kriterium | Bedömning |
|---|---|
| Nätverksmodell | Virtual Network Editor ger full kontroll över host-only-nät (VMnet10–13) — avgörande för segmenteringen |
| Snapshots | `vmrun` möjliggör skriptstyrda snapshots, vilket används för återställning mellan övningar |
| Resurskontroll | Per-VM allokering av vCPU/RAM gör det möjligt att köra miljön på 16 GB värd-RAM |
| Alternativ | Hyper-V saknar motsvarande flexibilitet för rena host-only-nät utan extern vSwitch |

### Resursallokering

| Virtuell maskin | vCPU | RAM | Disk | Segment |
|---|---:|---:|---:|---|
| FW-01 (OPNsense) | 1 | 1 GB | 20 GB | WAN + samtliga |
| DC-01 (Windows Server 2022) | 2 | 2 GB | 60 GB | LAN |
| FS01 (Windows Server 2022) | 2 | 2 GB | 40 GB | LAN |
| WIN11-01 (Windows 11) | 2 | 4 GB | 60 GB | LAN |
| LNX-WEB01 (Ubuntu 24.04) | 1 | 1 GB | 25 GB | DMZ |
| LNX-DB01 (Ubuntu 24.04) | 1 | 1 GB | 25 GB | DMZ |
| SOC-WAZUH (Ubuntu 22.04) | 2 | 4 GB | 80 GB | SOC |
| KALI-01 (Kali Linux) | 2 | 2 GB | 40 GB | RED |
| **Totalt** | **13** | **17 GB** | **350 GB** | |

Värdkrav: 32 GB RAM rekommenderas (16 GB fungerar med färre samtidigt körda maskiner),
6–8 kärnor med VT-x/AMD-V aktiverat, samt SSD/NVMe för VM-diskarna.

---

## 4. Nätverksdesign

### Segment och tillitsnivåer

| Segment | Subnät | Gateway | Tillit | Syfte |
|---|---|---|---:|---|
| **WAN** | tilldelas av VMware NAT | VMnet8-gateway | – | Simulerat internet |
| **LAN** (Corporate) | `192.168.10.0/24` | `192.168.10.1` | Hög | AD, klienter, filserver |
| **DMZ** (Servers) | `192.168.20.0/24` | `192.168.20.1` | Låg | Publika tjänster |
| **SOC** (Management) | `192.168.30.0/24` | `192.168.30.1` | Kritisk | SIEM, loggning, administration |
| **RED** (Attack) | `192.168.40.0/24` | `192.168.40.1` | Ingen | Attackplattform |

Segmenteringen är dimensionerad så att en kompromettering av DMZ (den mest exponerade
zonen) inte ger direkt åtkomst till LAN eller SOC. För att nå LAN från RED krävs
pivoting via DMZ — vilket är avsiktligt, eftersom det skapar detektionsmöjligheter
i flera lager.

### Mappning mot hypervisorns nät

| Segment | VMware-nät | Typ | Värdens adress |
|---|---|---|---|
| WAN | VMnet8 | NAT | – |
| LAN | VMnet10 | Host-only | `192.168.10.2` |
| DMZ | VMnet11 | Host-only | – (avsiktligt, för segmentering) |
| SOC | VMnet12 | Host-only | `192.168.30.2` |
| RED | VMnet13 | Host-only | – (avsiktligt) |

VMware tilldelar normalt värdadaptern `.1` i varje host-only-subnät, vilket kolliderar
med brandväggens gateway-adress. Konflikten hanteras av
[`scripts/host/Set-LabHostAccess.ps1`](../scripts/host/Set-LabHostAccess.ps1), som
flyttar värden till `.2` på LAN och SOC och lämnar DMZ och RED utan värdadress.

---

## 5. Adressplan

| Värd | Adress | Operativsystem | Roll |
|---|---|---|---|
| FW-01 | `10.x.x.x` (NAT) + `.10.1` `.20.1` `.30.1` `.40.1` | OPNsense 24.x | Brandvägg, router, DHCP, DNS, NTP |
| DC-01 | `192.168.10.10` | Windows Server 2022 | AD DS, DNS, DHCP (LAN) |
| FS01 | `192.168.10.11` | Windows Server 2022 | Filserver, AGDLP-demoresurs |
| WIN11-01 | DHCP (`192.168.10.100+`) | Windows 11 | Klient, GPO-verifiering |
| LNX-WEB01 | `192.168.20.10` | Ubuntu Server 24.04 LTS | Nginx, sårbar webbapplikation |
| LNX-DB01 | `192.168.20.11` | Ubuntu Server 24.04 LTS | MySQL/MariaDB |
| SOC-WAZUH | `192.168.30.10` | Ubuntu Server 22.04 LTS | Wazuh all-in-one |
| KALI-01 | DHCP (`192.168.40.100+`) | Kali Linux | Attackplattform |

### Domän

```
Skog / domän (AD DS):   soclab.local
NetBIOS-namn:           SOCLAB
Domänadministratör:     SOCLAB\Administrator
```

Samtliga konton delar ett labblösenord som förvaras i en krypterad lösenordsdatabas
utanför repot. Lösenord förekommer aldrig i versionshanterade filer.

---

## 6. Brandväggspolicy

Policyn är skriven före implementationen och följer princip 1 och 3 (default-deny,
loggning på samtliga regler).

| # | Källa | Destination | Tjänst | Åtgärd | Logg | Motivering |
|---:|---|---|---|---|:---:|---|
| 1 | LAN net | any | any | Allow | Ja | Användare behöver utgående åtkomst; loggas för avvikelseanalys |
| 2 | RED net | DMZ net | any | Allow | Ja | Attackövningens huvudscenario |
| 3 | RED net | LAN net | any | **Block** | Ja | Tvingar pivoting via DMZ; ger fler detektionspunkter |
| 4 | RED net | SOC net | 1514, 1515 | Allow | Ja | Agentkommunikation från Kali |
| 5 | RED net | SOC net | övrigt | **Block** | Ja | SIEM:et ska inte vara nåbart från attackzonen |
| 6 | DMZ net | LAN net | any | **Block** | Ja | Hindrar lateral rörelse från komprometterad webbserver |
| 7 | any | SOC net | 514, 1514, 1515, 55000 | Allow | Ja | Syslog och agenttrafik |
| 8 | SOC net | any | 22, 443, 3389, 5985 | Allow | Ja | Administration och fjärrstyrning |
| 9 | any | any | any | **Block** | Ja | Default-deny |

Regel 3 och 6 är de säkerhetsmässigt mest betydelsefulla: de bryter den direkta vägen
från en exponerad zon till identitetsinfrastrukturen.

---

## 7. Identitetsdesign

### Namnkonventioner

```
Användare:        <förnamn>.<efternamn>          t.ex. anna.berg
Administrativt:   adm-<förnamn>.<efternamn>      t.ex. adm-anna.berg
Tjänstkonto:      svc-<tjänst>                   t.ex. svc-backup
Dator:            <TYP>-<NR>                     t.ex. WIN11-01, LNX-WEB01
```

### Gruppkonventioner (AGDLP)

```
Global (roll):            GG_<Roll>                  t.ex. GG_Finance_RW
Domänlokal (resurs):      DL_<Resurs>_<Behörighet>   t.ex. DL_FileShare_Finance_RW
Universal (övergripande): UG_<Syfte>                 t.ex. UG_AllEmployees
```

Modellen innebär att behörighet till en resurs alltid uttrycks som en domänlokal
grupp som innehåller globala rollgrupper. Konsekvensen blir att behörighetsändringar
sker på ett ställe och att behörighetskedjan går att räkna ut maskinellt.

---

## 8. Loggning och detektionsflöde

| Källa | Transport | Destination | Format |
|---|---|---|---|
| OPNsense | UDP 514 | `192.168.30.10` | Syslog (BSD) |
| Windows (DC-01, FS01, WIN11-01) | TCP 1514 | `192.168.30.10` | Wazuh-agent + Sysmon |
| Linux (LNX-WEB01, LNX-DB01) | TCP 1514 | `192.168.30.10` | Wazuh-agent |
| KALI-01 | TCP 1514 | `192.168.30.10` | Wazuh-agent |

Syslog från brandväggen kräver egna decoders eftersom OPNsense inte levererar
strukturerade fält. Decoders och tillhörande regler utvecklas i fas 7 och
publiceras då under `config/wazuh/`; konfigurationen av själva loggflödet
beskrivs i [`config/opnsense/syslog-setup.md`](../config/opnsense/syslog-setup.md).

Vilka tekniker som faktiskt detekteras — och vilka som inte gör det — redovisas i
[detektionsmatrisen](../detections/detection-matrix.md).

### Tidssynkronisering

FW-01 synkroniserar mot externa NTP-källor och fungerar som auktoritativ tidsserver
för samtliga segment. DC-01 pekar mot `192.168.10.1`, vilket gör att Kerberos,
GPO-tillämpning och loggkorrelering fungerar även utan egen internetåtkomst.

---

## 9. Etik och avgränsningar

Samtliga offensiva moment genomförs enbart mot den egna, isolerade miljön.
Fullständiga regler finns i [Rules of Engagement](../evidence/rules-of-engagement.md).

I korthet:

- Ingen testning mot nätverk eller system utanför labbet
- Ingen produktionsdata och inga riktiga personuppgifter
- Ingen exponering av labbet mot internet
- Samtliga offensiva moment loggas i [attack-loggen](../evidence/attack-log.md)

---

## 10. Genomförande

| Fas | Moment | Status |
|---:|---|---|
| 0 | Arkitektur, IP-plan, brandväggspolicy | ✅ Klar |
| 1 | Hypervisor och virtuella nät (VMnet10–13) | ✅ Klar |
| 2 | OPNsense: interface, segmentering, syslog | ✅ Klar |
| 3 | Windows Server, AD DS, DNS, DHCP | 🔄 Pågår |
| 4 | OU-struktur, RBAC/AGDLP, delegering | ⬜ Ej påbörjad |
| 5 | GPO-härdning, audit policy, Sysmon | ⬜ Ej påbörjad |
| 6 | Linux-härdning (SSH, auditd, fail2ban) | ⬜ Ej påbörjad |
| 7 | Wazuh SIEM, agenter, egna regler | ⬜ Ej påbörjad |
| 8 | Attacksimulering från RED | ⬜ Ej påbörjad |
| 9 | Detektionsanalys, tuning, incidentrapporter | ⬜ Ej påbörjad |

---

## Bilaga: plattformskomponenter

| Komponent | Version | Roll |
|---|---|---|
| VMware Workstation Pro | 17.x | Hypervisor |
| OPNsense | 24.x | Brandvägg, router, DHCP, DNS, NTP |
| Windows Server | 2022 Standard (Desktop Experience) | AD DS, DNS, DHCP |
| Windows | 11 Enterprise | Klient |
| Ubuntu Server | 24.04 LTS | Webb- och databasserver |
| Ubuntu Server | 22.04 LTS | Wazuh-plattform |
| Kali Linux | 2024.x | Attackplattform |
| Wazuh | 4.x | SIEM (manager, indexer, dashboard) |
| Sysmon (Sysinternals) | 15.x | Telemetri på Windows |

### Referenser

Riktlinjer och dokumentation som designen baseras på:

- CIS Benchmarks (Windows Server 2022, Ubuntu Linux 24.04)
- Microsoft Security Baselines och AD-tiering-modellen
- MITRE ATT&CK — teknikurval för attacksimuleringen
- OPNsense-dokumentation (interface, regelverk, Kea DHCP, Unbound)
- Wazuh-dokumentation (decoders, rules, SCA)

---

*Senast uppdaterad: 2026-10 · Status: fas 3 pågår*
