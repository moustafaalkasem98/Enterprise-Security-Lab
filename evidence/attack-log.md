# Attack-logg

> **Sammanfattning**
> Förteckning över de tekniker som körs från KALI-01 mot miljön, med förväntad
> detektion och uppmätt utfall. Loggen utgör underlaget för
> detektionsmatrisen — varje rad ska kunna besvaras med "detekterades det, och
> i så fall av vilken regel".
>
> **Tidszon:** Europe/Stockholm (UTC+1 / UTC+2)
> **Status:** inga moment genomförda ännu — planeras till fas 8

---

## 1. Planerade moment

| # | Attack | Kommando | Mål | Förväntat larm | Faktiskt larm (regel-ID) | Detekterad | Status |
|---:|---|---|---|---|---|:---:|:---:|
| 1 | Ping sweep | `nmap -sn 192.168.20.0/24` | DMZ | 100020 | | | ⬜ |
| 2 | SYN scan | `nmap -sS -p- 192.168.20.10` | LNX-WEB01 | 100021 | | | ⬜ |
| 3 | Aggressiv scan | `nmap -A -T4 192.168.20.10` | LNX-WEB01 | 100021, 100051 | | | ⬜ |
| 4 | Scan av LAN (blockat) | `nmap -sS 192.168.10.0/24` | LAN | 100010 | | | ⬜ |
| 5 | Scan av SOC (blockat) | `nmap -sS 192.168.30.0/24` | SOC | 100011 | | | ⬜ |
| 6 | SSH brute force | `hydra -l socadmin -P lista <ip> ssh` | LNX-WEB01 | 5710 → 5712 | | | ⬜ |
| 7 | SMB brute force | `crackmapexec smb 192.168.10.0/24` | LAN | 4625, 60204 | | | ⬜ |
| 8 | RDP brute force | `hydra -t 1 rdp://192.168.10.11` | FS01 | 4625, 4740 | | | ⬜ |
| 9 | Kerberoasting | `impacket-GetUserSPNs -request` | DC-01 | 4769 | | | ⬜ |
| 10 | AS-REP roasting | `impacket-GetNPUsers` | DC-01 | 4768 | | | ⬜ |
| 11 | SMB-enumeration | `enum4linux -a 192.168.10.11` | FS01 | 4624 (typ 3) | | | ⬜ |
| 12 | Webbscanning | `nikto -h http://192.168.20.10/dvwa` | LNX-WEB01 | 31100+ | | | ⬜ |
| 13 | SQL injection | `sqlmap -u "..." --dbs` | DVWA | 31100–31109 | | | ⬜ |
| 14 | Credential dumping | `mimikatz sekurlsa::logonpasswords` | WIN11-01 | 100001 | | | ⬜ |
| 15 | Lateral rörelse | `impacket-psexec ...` | FS01 | 7045 | | | ⬜ |
| 16 | Persistence | `net user ... /add` | WIN11-01 | 4720, 4732 | | | ⬜ |
| 17 | Logrensning | `wevtutil cl Security` | WIN11-01 | 1102 | | | ⬜ |

**Statuskoder:** ⬜ ej körd · 🟡 körd, utfall under analys · ✅ detekterad · ❌ ej detekterad (lucka)

Moment 4 och 5 är kontroller: de ska blockeras av segmenteringen, och utgör
själva beviset för att zonindelningen fungerar.

---

## 2. Mätvärden

| Mätvärde | Resultat |
|---|---:|
| Genomförda moment | 0 / 17 |
| Detekterade (regel triggade) | – |
| Icke detekterade (täckningsluckor) | – |
| Detektionsgrad | – |
| Tid till detektion (medel) | – |
| Falska positiva | – |

Mätvärdena sammanställs efter fas 8 och ligger till grund för uppdateringen av
[`../detections/detection-matrix.md`](../detections/detection-matrix.md).

---

## 3. Observationer

*Fältet fylls i löpande under övningarna: avvikelser från förväntan, regler som
behöver tröskelvärden, samt tekniker som detekterades av annan regel än väntat.*

---

*Senast uppdaterad: 2026-10 · Inga moment genomförda ännu*
