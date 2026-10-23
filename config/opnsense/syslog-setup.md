# Loggflöde: OPNsense → Wazuh

> **Sammanfattning**
> Hur brandväggens loggar transporteras till SIEM:et, hur de landar på disk och
> hur Wazuh läser och tolkar dem. Konfigurationen är verifierad på
> OPNsense 24.x mot Wazuh 4.x.
>
> **Flöde:** FW-01 → (UDP 514) → rsyslog på SOC-WAZUH → `/var/log/remote/` → wazuh-manager → egna decoders

---

## 1. Designval

| Val | Alternativ | Motivering |
|---|---|---|
| **UDP 514** | TCP 514, TLS | Brandväggsloggar är inte konfidentiella i denna miljö och UDP har lägre overhead. På ett produktionsnät hade TLS varit krav. |
| **Mottagning via rsyslog** | Wazuh lyssnar direkt | rsyslog ger per-källa filseparering (`/var/log/remote/<ip>/`), vilket förenklar felsökning och retention. |
| **BSD-format** | RFC5424 | De egna decoderna är skrivna mot OPNsenses BSD-filterlog. RFC5424 kräver separata decoders. |
| **Endast `filter` i drift** | Samtliga applikationer | `filter` är brandväggsloggarna och står för i princip hela detektionsvärdet. Övriga applikationer aktiveras vid behov. |

---

## 2. Konfiguration – OPNsense

`System → Settings → Logging / Targets`

| Fält | Värde |
|---|---|
| Enabled | ☑ |
| Transport | UDP (IPv4) |
| Applications | `filter` |
| Level | Informational |
| Hostname | `192.168.30.10` |
| Port | `514` |
| RFC5424 | ☐ (se designval ovan) |
| Description | `Wazuh SOC syslog` |

Övriga applikationer (`dhcpd`, `unbound`, `suricata`, `system`, `configd`) läggs till
när respektive detektionsscenario kräver dem.

---

## 3. Konfiguration – SOC-WAZUH (rsyslog)

`/etc/rsyslog.d/10-opnsense.conf`:

```conf
module(load="imudp")
input(type="imudp" port="514")

$template RemoteLogs,"/var/log/remote/%fromhost-ip%/%fromhost-ip%.log"
$template RemoteFormat,"%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"

if ($fromhost-ip != "127.0.0.1") then {
    action(type="omfile" dynaFile="RemoteLogs" template="RemoteFormat")
    stop
}
```

Filsepareringen per käll-IP gör att varje avsändare får en egen loggfil, vilket
möjliggör separat retention och enklare korrelation vid utredning.

```bash
sudo mkdir -p /var/log/remote
sudo systemctl restart rsyslog
```

---

## 4. Konfiguration – Wazuh-manager

Lägg till i `/var/ossec/etc/ossec.conf`:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/remote/*/*.log</location>
</localfile>
```

Registrera decoders och rules i `<ruleset>`:

```xml
<decoder>etc/decoders/opnsense_decoders.xml</decoder>
<rule>etc/rules/opnsense_rules.xml</rule>
```

Installation:

```bash
sudo cp config/wazuh/custom-decoders/opnsense_decoders.xml /var/ossec/etc/decoders/
sudo cp config/wazuh/custom-rules/opnsense_rules.xml      /var/ossec/etc/rules/
sudo chown wazuh:wazuh /var/ossec/etc/decoders/opnsense_decoders.xml
sudo chown wazuh:wazuh /var/ossec/etc/rules/opnsense_rules.xml
sudo chmod 660 /var/ossec/etc/decoders/opnsense_decoders.xml
sudo chmod 660 /var/ossec/etc/rules/opnsense_rules.xml
sudo systemctl restart wazuh-manager
```

---

## 5. Verifiering

### Transport

```bash
sudo tcpdump -i any udp port 514 -nn -c 5
ls -la /var/log/remote/
tail -5 /var/log/remote/*/*.log
```

### Decodning

```bash
/var/ossec/bin/wazuh-logtest <<'TEST'
<187>Sep 15 14:23:01 FW-01 filterlog[12345]: 4,,,1000000103,hn4,match,block,in,4,0x0,,64,54321,0,none,6,tcp,40,192.168.40.50,192.168.10.10,54321,445,0,SYN,32768:32768,0,,mss; sackOK
TEST
```

Förväntat resultat: `**Phase 2: Completed decoding` med `action: block`,
`srcip: 192.168.40.50`, `dstip: 192.168.10.10` samt träff på regel **100003**
eller **100010**.

---

## 6. Kända begränsningar

| Begränsning | Konsekvens | Möjlig åtgärd |
|---|---|---|
| UDP saknar leveransgaranti | Enstaka loggposter kan falla bort vid hög last | Byt till TCP eller TLS om volymen ökar |
| Endast `filter` samlas in | DHCP- och DNS-loggar saknas | Lägg till applikationer under Logging / Targets |
| Ingen retention-policy | `/var/log/remote/` växer obegränsat | Konfigurera `logrotate` |

---

*Senast verifierat: 2026-10 · OPNsense 24.x → Wazuh 4.x*
