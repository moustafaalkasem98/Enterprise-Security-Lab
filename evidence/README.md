# Evidens

> **Sammanfattning**
> Denna katalog utgör projektets bevismaterial: etiska ramar, planerade och
> genomförda övningar, incidentrapporter samt visuell verifiering. Syftet är att
> varje påstående i projektet ska kunna härledas till ett verifierbart underlag.
>
> **Status:** fas 0–2 verifierade · fas 3 pågår · attacksimulering planerad till fas 8

---

## 1. Innehåll

| Fil | Syfte | Status |
|---|---|---|
| [`rules-of-engagement.md`](rules-of-engagement.md) | Etiskt och juridiskt ramverk för de offensiva momenten | ✅ Fastställd |
| [`attack-log.md`](attack-log.md) | Tekniker med förväntad och uppmätt detektion | 🔄 Pågår (fas 8) |
| `screenshots/` | Visuell verifiering per fas | 🔄 Löpande |
| `raw/` | Exporter från Wazuh (JSON) och nmap-resultat | ⬜ Från fas 8 |
| `incident-reports/` | Fördjupad incidentanalys | ⬜ Från fas 9 |

```
evidence/
├── rules-of-engagement.md
├── attack-log.md
├── incident-reports/    (från fas 9)
├── screenshots/
└── raw/
```

---

## 2. Skärmbilder

Skärmbilder lagras i `screenshots/` med namngivningen `<fasnummer>-<moment>.png`.
Registret nedan omfattar enbart material som är publicerat.

| Fas | Fil | Vad den verifierar |
|---:|---|---|
| 2 | `02-opnsense-interfaces.png` | Interface-tilldelning och adressering per zon |
| 2 | `02-opnsense-rules.png` | Regelverk med loggning aktiverad |
| 2 | `02-opnsense-syslog.png` | Fjärrloggning mot `192.168.30.10` |

Registret utökas i takt med att faserna publiceras.

---

## 3. Hantering

Bevismaterial som publiceras ska vara fritt från information som inte hör
hemma i ett öppet repo. Följande kategorier maskeras eller avlägsnas:

| Kategori | Exempel |
|---|---|
| Publika adresser | Externa IP-adresser, WAN-adress |
| Identiteter | Användarnamn, e-postadresser |
| Kryptografiskt material | Hashar, nycklar, certifikat |
| Licensinformation | Serienummer, licensnycklar |
| Personuppgifter | Namn, telefonnummer |

Maskering sker med valfritt bildredigeringsverktyg före incheckning.

---

## 4. Incidentrapporter

Rapporterna följer en gemensam mall och publiceras från och med fas 9.

| ID | Scenario | Analysfokus |
|---|---|---|
| **IR-001** | SSH brute force mot LNX-WEB01 | Tröskelvärden, fail2ban och aktiv respons |
| **IR-002** | Kontolåsning i Active Directory (Event 4740) | Korrelation 4625 → 4740, särskiljning av helpdesk |
| **IR-003** | Kerberoasting mot tjänstekonto | Detektion av RC4-ticket via Event 4769 |

---

*Senast uppdaterad: 2026-10*
