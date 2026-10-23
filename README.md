# Multi-Tier Enterprise & Security Lab

> En isolerad företagsmiljö byggd från grunden för att öva både anfall och försvar:
> ett segmenterat nätverk bakom OPNsense, en Windows Server-domän med AGDLP-baserad
> behörighetsmodell, härdade Linux-servrar och ett Wazuh-SIEM som korrelerar loggar
> från samtliga lager. Kontrollerade attacker körs från ett avgränsat RED-segment
> och avtrycken analyseras därefter i SIEM:et.

[![Platform](https://img.shields.io/badge/platform-VMware%20Workstation-blue)](docs/01-arkitektur-och-topologi.md)
[![Firewall](https://img.shields.io/badge/firewall-OPNsense%2024.x-orange)](config/opnsense/rules-export.md)
[![SIEM](https://img.shields.io/badge/SIEM-Wazuh%204.x-green)](detections/detection-matrix.md)
[![MITRE](https://img.shields.io/badge/MITRE-ATT%26CK%20mappad-red)](detections/attack-mapping.csv)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Syfte

Miljön är konstruerad för att praktiskt demonstrera förmåga inom fyra områden:

| Område | Vad som är implementerat |
|---|---|
| **Nätverkssegmentering** | Fyra zoner (LAN / DMZ / SOC / RED) bakom OPNsense med default-deny och loggning på samtliga regler |
| **Identitet och behörighet** | AD DS med tiering, AGDLP-baserad RBAC, GPO-härdning och avancerad granskning |
| **Systemhärdning** | CIS-inspirerad Linux-baseline: nyckelbaserad SSH, fail2ban, UFW, auditd, AIDE |
| **Detektion och respons** | Wazuh med egna decoders och regler, ATT&CK-mappning och incidentrapportering |

---

## Arkitektur

```
        ┌────────────────────────────────────────────────────────┐
        │        HYPERVISOR: VMware Workstation Pro 17           │
        └────────────────────────────────────────────────────────┘
                                   │
                 ┌─────────────────┴─────────────────┐
                 │   VMnet8  (NAT)  ·  valfritt nät   │  ← internet
                 └─────────────────┬─────────────────┘
                                   │
                        ╔══════════▼══════════╗
                        ║    OPNsense FW-01   ║ ──── syslog :514 ──┐
                        ║  5x vmxnet3 (vmx0-4)║                    │
                        ╚══╤════╤════╤════╤═══╝                    │
        ┌──────────────────┘    │    │    └──────────────┐         │
        │                       │    │                   │         │
   VMnet10 · LAN           VMnet11  │              VMnet13 · RED   │
  192.168.10.0/24      · DMZ  │     │              192.168.40.0/24 │
        │           192.168.20.0/24 │                    │         │
        │                  │   VMnet12 · SOC             │         │
        │                  │  192.168.30.0/24            │         │
        │                  │        │                    │         │
 ┌──────┴───────┐   ┌──────┴─────┐  │            ┌───────┴──────┐  │
 │ DC-01   .10   │   │ LNX-WEB01  │  │            │  KALI-01 .50 │  │
 │  AD/DNS/DHCP │   │   .10      │  │            │ nmap · hydra │  │
 │ FS01   .11   │   │ LNX-DB01   │  │            │ impacket     │  │
 │ WIN11-01 DHCP│   │   .11      │  │            └──────────────┘  │
 └──────┬───────┘   └──────┬─────┘  │                             │
        │                  │   ┌────▼─────────┐                   │
        │                  │   │ SOC-WAZUH .10│◄──────────────────┘
        │                  │   │ Wazuh AIO    │
        │                  │   │ :1514 :1515  │
        │                  │   └──────▲───────┘
        └──────────────────┴──────────┘
              Wazuh-agenter → TCP 1514/1515

  Domän: soclab.local   ·   All loggning → SOC-WAZUH (192.168.30.10)
  Brandväggsprincip: default-deny + explicita allows + logg på alla regler
```

Fullständigt diagram: [`docs/diagrams/topologi.svg`](docs/diagrams/topologi.svg)

---

## Dokumentation

Projektet är dokumenterat som ett tekniskt projekt: designbeslut med motivering,
implementerad konfiguration, detektioner och incidentrapporter.

| Dokument | Innehåll |
|---|---|
| [Arkitektur & designbeslut](docs/01-arkitektur-och-topologi.md) | Syfte, designprinciper, plattform, nätverksdesign, adressplan, brandväggspolicy, identitetsdesign |
| [Nätverksdiagram](docs/diagrams/topologi.svg) | Helhetsbild: WAN / LAN / DMZ / SOC / RED |
| [Brandväggsregelverk](config/opnsense/rules-export.md) | Implementerat regelverk per zon med verifiering |
| [Loggflöde](config/opnsense/syslog-setup.md) | OPNsense → rsyslog → Wazuh, med designval och begränsningar |
| [Detektionsmatris](detections/detection-matrix.md) | Täckning per ATT&CK-teknik, luckor och prioriterade åtgärder |
| [ATT&CK-mappning](detections/attack-mapping.csv) | Maskinläsbar: teknik → datakälla → regel → status |
| [Rules of Engagement](evidence/rules-of-engagement.md) | Etiskt och juridiskt ramverk för de offensiva momenten |
| [Attack-logg](evidence/attack-log.md) | Planerade moment med förväntad och uppmätt detektion |

### Runbooks

Körbar kod som bygger och konfigurerar miljön. Runbooks publiceras i takt med
att respektive fas blir klar — tabellen växer allteftersom.

| Runbook | Fas | Funktion |
|---|:---:|---|
| [`scripts/host/setup-vmware.ps1`](scripts/host/setup-vmware.ps1) | 1 | Skapar samtliga virtuella maskiner med rätt nätverkstilldelning |
| [`scripts/host/setup-vmware.sh`](scripts/host/setup-vmware.sh) | 1 | Motsvarande för Linux- och macOS-värdar |
| [`scripts/host/Set-LabHostAccess.ps1`](scripts/host/Set-LabHostAccess.ps1) | 1 | Löser adresskonflikten mellan VMware-värden och brandväggen |
| [`scripts/windows/Setup-DC-01.ps1`](scripts/windows/Setup-DC-01.ps1) | 3 | Grundkonfiguration av domänkontrollanten |

---

## Arbetssätt

Varje del av miljön har tagits fram i tre steg:

1. **Design** — beslut dokumenteras med motivering innan implementation, se
   [designprinciperna](docs/01-arkitektur-och-topologi.md#2-designprinciper)
2. **Implementation** — konfiguration och skript versionshanteras och går att återskapa
3. **Verifiering** — varje påstående kontrolleras mätbart; resultat förs in i
   [detektionsmatrisen](detections/detection-matrix.md) och [attack-loggen](evidence/attack-log.md)

Riktlinjer som designen baseras på: CIS Benchmarks, Microsoft Security Baselines,
MITRE ATT&CK samt leverantörsdokumentation för OPNsense och Wazuh.

---

## Komma igång

```bash
git clone git@github.com:moustafaalkasem98/Enterprise-Security-Lab.git
cd Enterprise-Security-Lab
```

Rekommenderad läsordning för den som vill förstå miljön:

```
docs/01-arkitektur-och-topologi.md   Design, nätverk och brandväggspolicy
config/opnsense/rules-export.md      Implementerat regelverk
config/opnsense/syslog-setup.md      Loggflöde till SIEM
detections/detection-matrix.md       Vad som detekteras – och vad som inte gör det
evidence/rules-of-engagement.md      Ramarna för de offensiva momenten
```

---

## Repostruktur

```
Enterprise-Security-Lab/
├── README.md                    Portfolio-ingång
├── LICENSE                      MIT
├── .gitignore                   Publiceringskö + skydd mot lösenord, ISO:er och VM-diskar
├── docs/                        Arkitektur och diagram
│   ├── 01-arkitektur-och-topologi.md
│   └── diagrams/topologi.svg
├── scripts/
│   ├── host/                    setup-vmware.ps1/.sh, Set-LabHostAccess.ps1
│   ├── windows/                 Setup-DC-01.ps1 (övriga tillkommer i fas 4-5)
│   └── linux/                   tillkommer i fas 6-7
├── config/
│   └── opnsense/                Regelyerk och loggflöde
│                                (wazuh/, ssh/ och sysmon/ tillkommer i fas 5-7)
├── detections/                  detection-matrix.md, attack-mapping.csv
├── evidence/                    rules-of-engagement, attack-log,
│                                incident-reports/ (fas 9), screenshots/, raw/
└── .github/workflows/           lint.yml (shellcheck och hemlighetsskanning)
```

---

## Bevis

Verifiering sker löpande och samlas i [`evidence/`](evidence/README.md).

Tabellen växer i takt med att faserna blir klara.

| Fas | Moment | Skärmbild |
|:---:|---|---|
| 2 | OPNsense-regelverk med loggning | `evidence/screenshots/02-opnsense-rules.png` |

Samtligt material rensas på publika adresser, användarnamn och nycklar före publicering.

---

## Etik och laglighet

Samtliga moment i detta repo körs i en isolerad labbmiljö på hårdvara som ägs av
projektets upphovsman. Att köra scanning, brute force eller exploits mot nätverk
och system utan uttryckligt tillstånd är olagligt.

De offensiva momenten regleras av
[Rules of Engagement](evidence/rules-of-engagement.md).

---

## Status

| Fas | Moment | Status |
|---:|---|---|
| 0 | Arkitektur, adressplan, brandväggspolicy | ✅ Klar |
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

## Upphovsman

**Moustafa Alkasem** — [GitHub](https://github.com/moustafaalkasem98) [LinkedIn](https://www.linkedin.com/in/moustafa-alkasem)

*En del av min portfolio för roller inom IT-säkerhet, systemadministration och SOC.*
