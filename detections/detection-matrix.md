# Detektionsmatris

> **Sammanfattning**
> Matrisen redovisar vilka MITRE ATT&CK-tekniker miljön är konstruerad att
> detektera, vilken datakälla och regel varje detektion bygger på — och var
> täckningen saknas. Den är både ett designunderlag och ett mätinstrument.
>
> **Miljö:** soclab.local · **SIEM:** Wazuh 4.x
> **Tekniker i matrisen:** 22 · **Status:** designstadium — verifiering sker i fas 8–9

---

## 1. Status

| Status | Antal | Andel |
|---|---:|---:|
| ✅ Detekterad | 12 | 55 % |
| ⚠️ Delvis / kräver tuning | 5 | 23 % |
| ❌ Täckningslucka | 5 | 23 % |
| **Totalt** | **22** | **100 %** |

Siffrorna avser **planerad** täckning baserat på implementerade regler och
aktiverade loggkällor. Efter genomförd attacksimulering (fas 8) uppdateras
matrisen med uppmätta värden: faktiskt utfall, tid till detektion och antal
falska positiva.

**Målsättning efter fas 9:** minst 80 % verifierat detekterade tekniker.

### Legend

| Symbol | Betydelse |
|:---:|---|
| ✅ | Regel finns och förväntas trigga vid övning |
| ⚠️ | Loggkälla finns men regel saknas, är ofullständig eller genererar falska positiva |
| ❌ | Ingen täckning — åtgärd krävs |

Maskinläsbar version: [`attack-mapping.csv`](attack-mapping.csv)

---

## 2. Matris

| MITRE | Taktik | Teknik | Anfallsteknik | Mål | Loggkälla | Event ID | Regel-ID | Status | Åtgärd vid lucka |
|---|---|---|---|---|---|---|:---:|:---:|---|
| T1046 | Discovery | Network Service Discovery | `nmap -sS / -A` | DMZ/LAN | OPNsense filterlog | – | 100020, 100021 | ✅ | – |
| T1046 | Discovery | Port sweep | `nmap -p- <host>` | DMZ | OPNsense filterlog | – | 100022 | ✅ | – |
| T1595 | Reconnaissance | Active scanning | `nikto`, `nmap -sV` | DMZ | Apache access.log | – | 31100+ | ⚠️ | Aktivera Apache-loggar i agenten |
| T1110.001 | Credential Access | Password guessing | `hydra ... ssh` | LNX-WEB01 | auth.log | – | 5710 → 5712 | ✅ | – |
| T1110.001 | Credential Access | Password guessing | `crackmapexec smb` | DC-01 | Windows Security | 4625 | 60204 | ✅ | – |
| T1110.003 | Credential Access | Password spraying | `crackmapexec -u lista -p 1lösen` | DC-01 | Windows Security | 4625 | 60204 | ⚠️ | Särskilj helpdesk-IP från angripare |
| T1110 | Credential Access | Brute force → lyckad inloggning | hydra lyckas | Valfri | Korrelation | 4625 → 4624 | 100102 | ✅ | – |
| **T1558.003** | Credential Access | **Kerberoasting** | `GetUserSPNs -request` | DC-01 | Windows Security | **4769** | **100111** | ⚠️ | **Egen regel för RC4-krypterade ticket** |
| **T1558.004** | Credential Access | **AS-REP roasting** | `GetNPUsers` | DC-01 | Windows Security | **4768** | **100115** | ⚠️ | **Egen regel för PreAuthType=0** |
| T1087.002 | Discovery | Domain account discovery | `enum4linux`, `Get-ADUser` | DC-01 | Windows Security | 4776 | 60122 | ⚠️ | Särskilj administrativ aktivitet |
| **T1021.002** | Lateral Movement | **SMB / admin shares** | `impacket-psexec` | FS01 | Windows Security | **7045** | – | ❌ | **Regel för tjänsteskapande saknas** |
| T1021.001 | Lateral Movement | Remote Desktop | RDP-inloggning | FS01 | Windows Security | 4624 (typ 10) | – | ⚠️ | Filtrera på LogonType 10 |
| T1003.001 | Credential Access | LSASS memory | `mimikatz sekurlsa` | WIN11-01 | Sysmon + Security | 10 / 4688 | 100001 | ✅ | – |
| T1003 | Credential Access | OS credential dumping | `procdump lsass` | WIN11-01 | Sysmon | 10 | 100130 | ✅ | – |
| T1136.001 | Persistence | Create account | `net user /add` | WIN11-01 | Windows Security | 4720 | 60109 | ✅ | – |
| T1098.001 | Persistence | Group membership | `net localgroup /add` | WIN11-01 | Windows Security | 4732 | 60112 | ✅ | – |
| **T1562.001** | Defense Evasion | **Log clearing** | `wevtutil cl Security` | WIN11-01 | Windows Security | **1102** | – | ❌ | **Regel för logrensning saknas** |
| T1562.004 | Defense Evasion | Impair defenses | Blockad av segmentering | OPNsense | filterlog | – | 100003 | ✅ | – |
| T1562.006 | Defense Evasion | Indicator blocking | Attack mot SIEM | OPNsense | filterlog | – | 100011 | ✅ | – |
| T1190 | Initial Access | Exploit public-facing app | `sqlmap`, DVWA | DMZ | Apache / Suricata | – | 31100+ | ⚠️ | Aktivera Suricata på OPNsense |
| **T1071.001** | Command and Control | Web protocols | Reverse shell | DMZ | Sysmon | 3 / 1 | – | ❌ | **Kräver beteendebaserad regel** |
| T1499 | Impact | Endpoint DoS | `hping3 --flood` | DMZ | OPNsense / Suricata | – | 100021 | ⚠️ | Suricata ET-regler |

---

## 3. Prioriterade åtgärder

| # | Lucka | Åtgärd | Prioritet |
|---:|---|---|:---:|
| 1 | T1558.003 Kerberoasting | Regel 100111 — RC4-ticket (0x17) begärt för tjänstekonto | 🔴 Hög |
| 2 | T1562.001 Logrensning | Regel för Event 1102 (säkerhetsloggen rensad) | 🔴 Hög |
| 3 | T1021.002 Lateral rörelse | Regel för Event 7045 (ny tjänst installerad) | 🟡 Medel |
| 4 | T1558.004 AS-REP roasting | Regel 100115 — PreAuthType=0 | 🟡 Medel |
| 5 | Apache-loggar | Aktivera `<localfile>` för access.log och error.log | 🟡 Medel |
| 6 | T1071.001 C2 | Implementera Suricata på OPNsense för nätverkstelemetri | 🟢 Låg |

### Motivering till prioriteringen

Kerberoasting (åtgärd 1) och logrensning (åtgärd 2) prioriteras högst av två skäl:
de representerar var sitt kritiskt steg i en attackkedja — åtkomst till
tjänstekonton respektive undanröjande av bevis — och båda lämnar entydiga
händelser i säkerhetsloggen (4769 respektive 1102). Detektion är därför möjlig
med en enda regel vardera, till låg kostnad i form av falska positiva.

---

## 4. Metod

Matrisen hålls aktuell genom mätning, inte uppskattning. Efter varje genomförd
övning antecknas exakt start- och stopptid, SIEM:et filtreras på motsvarande
tidsfönster och källadress, och de regel-ID:n som triggade noteras. Saknas larm
helt klassas tekniken som täckningslucka, varpå en egen regel tas fram och
verifieras med `wazuh-logtest` innan matrisen uppdateras.

Uppdateringar sker i `attack-mapping.csv` och i denna fil, och committas med ett
meddelande som anger tekniken, till exempel
`detections: add kerberoasting rule (T1558.003)`.

---

*Senast uppdaterad: 2026-10 · Status: designstadium*
