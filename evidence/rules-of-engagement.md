# Rules of Engagement (RoE)

> **Sammanfattning**
> Detta dokument definierar de etiska och juridiska ramarna för de offensiva
> momenten i projektet. Det fastställer vilka system som omfattas, på vilken
> juridisk grund, samt vilka aktiviteter som är uteslutna.
>
> **Giltighetstid:** tillsvidare · **Omfattning:** samtliga system i `soclab.local`

---

## 1. Syfte

Dokumentet syftar till att säkerställa att all offensiv verksamhet inom projektet
bedrivs inom ramen för gällande lagstiftning och etablerad praxis för
säkerhetstestning, samt att varje moment kan granskas i efterhand.

---

## 2. Omfattning och tillstånd

All testning sker uteslutande mot följande system:

| System | Adress | Ägare |
|---|---|---|
| FW-01 (OPNsense) | `192.168.10.1` / `.20.1` / `.30.1` / `.40.1` | Moustafa Alkasem |
| DC-01 | `192.168.10.10` | Moustafa Alkasem |
| FS01 | `192.168.10.11` | Moustafa Alkasem |
| WIN11-01 | DHCP `192.168.10.100–200` | Moustafa Alkasem |
| LNX-WEB01 | `192.168.20.10` | Moustafa Alkasem |
| LNX-DB01 | `192.168.20.11` | Moustafa Alkasem |
| SOC-WAZUH | `192.168.30.10` | Moustafa Alkasem |
| KALI-01 | DHCP `192.168.40.100–200` | Moustafa Alkasem |

Samtliga system körs som virtuella maskiner på hårdvara som ägs av undertecknad.
**Ingen tredje part är involverad och inget externt tillstånd erfordras.**

---

## 3. Juridisk grund

- Verksamheten omfattas inte av bestämmelserna om dataintrång, eftersom samtliga
  målsystem ägs av den som utför testningen.
- Ingen trafik riktas mot system utanför det isolerade labbnätverket.
- Ingen skadlig kod förs ut ur labbmiljön.
- Inga personuppgifter i lagens mening behandlas; samtliga konton och data är
  syntetiska.

---

## 4. Regler under testning

| # | Regel |
|---:|---|
| 1 | Målets adress verifieras före varje kommando |
| 2 | Riktiga lösenord och personuppgifter används aldrig |
| 3 | Varje moment dokumenteras med tidpunkt, kommando, syfte och utfall |
| 4 | Snapshots återställs efter destruktiva moment |
| 5 | Tillfälliga brandväggsregler tas bort efter avslutad övning |
| 6 | Verktyg och filer som skapats under testningen tas bort |
| 7 | Motsvarande kommandon körs aldrig mot nätverk utanför labbet |

---

## 5. Förbjudna aktiviteter

Följande får inte utföras under några omständigheter:

- Testning mot system utanför labbmiljön
- Testning mot skolans, arbetsgivarens eller annan parts nätverk
- Spridning av skadlig kod
- Användning av riktiga personuppgifter
- Överbelastningsattacker riktade mot externa system
- Försök att kringgå fysisk säkerhet eller åtkomstkontroll i fastighet

---

## 6. Rapportering

Samtliga genomförda moment dokumenteras i:

- [`attack-log.md`](attack-log.md) — teknik, kommando, förväntad och faktisk detektion
- `incident-reports/` — fördjupad analys av utvalda incidenter (från fas 9)

---

## 7. Fastställande

Jag bekräftar härmed att jag har läst, förstått och accepterar ovanstående regler,
samt att samtliga offensiva moment i projektet genomförs i enlighet med dem.

| Fält | Värde |
|---|---|
| **Namn** | Moustafa Alkasem |
| **Datum** | 2026-10-21 |
| **Roll** | Projektägare och utövare |

---

*Dokumentet fastställt: 2026-10-21 · Gäller tillsvidare*
