# Backend-Lasttest · 5. September 2026

**Historische Baseline vor der Transportoptimierung.** Die nachfolgenden Werte bleiben unverändert. Den Vergleich mit kompakten Gefechtsansichten und Gzip enthält [NETWORK.md](NETWORK.md).

**Der SpacetimeDB-Architekturprototyp hat alle drei lokalen Lastszenarien und die Integritätsprüfungen bestanden.** Dies sind erste Messpunkte für die weitere Entwicklung, keine ermittelte Kapazitätsgrenze und keine vollständige Spielmigration.

## Messbedingungen

SpacetimeDB **2.10.0**, TypeScript-Modul, Node **24.18.0**, Windows **10.0.26200**. Rechner: **Intel Core i7-12700K**, 20 logische CPUs, **31,76 GiB RAM**. Server und Lastclients liefen auf demselben Rechner über Loopback, ohne künstliche WAN-Latenz. Andere Testdatenbanken waren pausiert; normale Desktopanwendungen liefen weiter.

Jedes Szenario enthält **1.000 Systeme, 25 Imperien, 1.250 ursprüngliche Flotten**, 250 Kolonien, 1.000 Pop-Kohorten, laufende Produktionszyklen, Forschungs-/Bauaufträge und 25 zeitlich versetzte KI-Planer. 50 Flotten sind in Gefechten gebunden, die übrigen 1.200 starten mit einer strategischen Route. Es sind **25 verschiedene Spieleridentitäten** verbunden, mit jeweils berechtigten Abonnements. Die KI bleibt als Autopilot aktiv.

Nach drei Sekunden Aufwärmphase werden etwa **60 Sekunden** gemessen. Dabei erfolgen **24 Wiederverbindungen** im Abstand von 2,5 Sekunden. Zusätzlich werden die 25 anfänglichen Beitritte in die bereits laufende Welt geprüft. Alle 49 Snapshots je Szenario waren konsistent: eigene Daten, korrekte Mitgliederzahlen, vollständige Gefechte und gültige Zielreferenzen.

## Server und Beitritte

| Messwert | Standard | Große Flotten | Große Einzelschlacht |
|---|---:|---:|---:|
| Gespeicherte Schiffe beim Start | 25.000 | 75.000 | 75.000 |
| Gleichzeitige Gefechte | 5 | 5 | 1 |
| Schiffe je Gefecht | 200 | 600 | 3.000 |
| Gefechtsdetail-Clients | 5 | 5 | 1 |
| Pops in den Kohorten | 25.000 | 100.000 | 100.000 |
| Initialer Beitritt p95 | 35,5 ms | 63,6 ms | 62,2 ms |
| Reconnect p95 | 47,5 ms | 63,2 ms | 32,8 ms |
| Maximaler gemessener Reconnect | 48,3 ms | 64,3 ms | 44,5 ms |
| Kampf-Reducer inkl. Subscriptions, Mittel | 7,19 ms | 19,20 ms | 17,27 ms |
| Kampf-Reducer p95, obere Histogrammgrenze | ≤25 ms | ≤50 ms | ≤50 ms |
| Strategischer Reducer inkl. Subscriptions, Mittel | 3,94 ms | 4,25 ms | 4,09 ms |
| Wirtschafts-Reducer inkl. Subscriptions, Mittel | 4,34 ms | 4,12 ms | 3,98 ms |
| KI-Reducer inkl. Subscriptions, Mittel | 1,20 ms | 1,19 ms | 1,15 ms |
| Kampf-Rückstand p95 | 13,2 ms | 11,1 ms | 12,3 ms |
| Maximal abgetasteter Kampf-Rückstand | 17,4 ms | 33,4 ms | 28,5 ms |

Kampfaufrufe erfolgen alle 100 ms; bei Bedarf verarbeiten sie 200-ms-Spielschritte. Die Laufzeitmittel enthalten also auch Aufrufe ohne fälligen Kampfschritt. Der Rückstand wird zusätzlich zur regulären Schrittweite gemessen. Die p95-Laufzeitwerte stammen aus nativen Histogrammklassen und sind keine punktgenauen Perzentile. Strategische Ankünfte werden mit 250-ms-Granularität verarbeitet; bis etwa diese Größenordnung ist deren Erkennungsverzug erwartbar.

Die Startbefüllung dauerte in diesen Läufen etwa **313 ms**, **736 ms** und **713 ms**, einschließlich der aufeinanderfolgenden Seed-Transaktionen und Aktivierung. Das ist eine lokale Prototyp-Messung mit vorbereitetem Modul.

## Netzwerk: Detailgrad ist der deutliche Kostentreiber

Gemessen wurden tatsächliche binäre WebSocket-Nachrichtenbytes mit **abgeschalteter Kompression**. Reconnect-Snapshots sind enthalten; HTTP-Authentifizierung sowie TCP/TLS/WebSocket-Frame-Overhead sind ausgeschlossen.

| Empfang | Standard | Große Flotten | Große Einzelschlacht |
|---|---:|---:|---:|
| Alle 25 Clients zusammen | 836 KiB/s | 2.413 KiB/s | 2.349 KiB/s |
| Je Galaxie-Client, Mittel | 1,84 KiB/s | 1,84 KiB/s | 1,67 KiB/s |
| Je Gefechtsdetail-Client | ca. 160 KiB/s | ca. 474–477 KiB/s | ca. 2.309 KiB/s |

Die Trennung von Flotten und Schiffen sowie bedarfsgerechte Abonnements sind damit praktisch überprüft. Große detaillierte Gefechte brauchen weitere Arbeit am Übertragungsformat und an der Aktualisierungsrate. **2.309 KiB/s für einen Beobachter entsprechen etwa 2,25 MiB/s** – diese Kosten steigen bei weiteren Beobachtern mit. Als Nächstes sollten kompaktere Bewegungsdaten, getrennte Zustandsänderungen, Kompression und abgestufte Gefechtsansichten gemessen werden. Die Tabelle ist keine Messung dieser noch ausstehenden Optimierungen.

Native belegte Zeilendaten lagen bei etwa **12,1 / 34,0 / 33,9 MiB**, Indexschlüssel bei **0,55 / 1,29 / 1,27 MiB**. Der gemeldete V8-Heap lag bei **15,4 / 36,5 / 43,0 MiB**. Das sind ausgewählte Datenbankmetriken, **nicht** der gesamte Prozess-RAM oder eine Langzeitmessung des Commit-Logs.

## Browser: 165-Hz-Limit, keine Aussage über Reserven

Die separate Three.js-Laborprobe lief auf **NVIDIA GeForce RTX 5080**, Chromium 152 über ANGLE/Direct3D11, bei **1600×1100**, DPR 1. Sie zeigte:

- **Galaxie:** 1.000 Systeme und 76 berechtigte Flotten mit drei Draw Calls; eine zusätzliche Flotte entstand durch Schiffskonstruktion.
- **Gefecht:** 3.000 einzelne Kampfteilnehmer mit zwei Draw Calls.
- Beide Ansichten erreichten **rund 165 FPS**. Der Nutzer hat **165 Hz als Refresh-Rate-/FPS-Cap bestätigt**.
- Gemessene rAF-Frameabstände lagen am Cap bei ungefähr 6,2–6,3 ms p95. Das sind keine isolierten GPU- oder CPU-Ausführungszeiten.

**Daraus lässt sich weder eine freie Leistungsreserve noch eine unlimitierte Framerate ableiten.** Ein Benchmark ohne FPS-Begrenzung bzw. mit GPU-/CPU-Timing wurde nicht durchgeführt. Die Laborszene enthält einfache instanzierte Geometrie und ein vorberechnetes Gravitationsfeld; zukünftige Kampfeffekte und die vollständige Spieloberfläche gehören nicht zu dieser Messung. Der Browserlauf hatte eine Verbindung und fand getrennt vom 25-Client-Lasttest statt.

## Integrität und Wiederherstellung

**24 bestehende/ergänzte Spiel- und Domänentests sowie 10 SpacetimeDB-Testfälle sind grün.** Der Produktionsbuild und die TypeScript-Prüfung sind erfolgreich.

Die tatsächlichen SpacetimeDB-Tests prüfen unter anderem private SQL-Zugriffe, fremde Fokus-/Bewegungsbefehle, Schutz geplanter Reducer, gemeinsame Uhr, Rollback einer fehlerhaften Aufteilung, Soloflotte und Zusammenführung, Rückzug, unveränderte Schiffsdaten bei Kursänderung, Jobabschluss/-abbruch und Forschungsmultiplikatoren.

Für den Neustarttest wurde ein **separater Serverprozess erzwungen beendet** und mit demselben Datenverzeichnis neu gestartet. Die Uhr wurde unmittelbar davor pausiert, um exakte Zustände vergleichen zu können. Schiffsausrüstung und Hülle, Gefecht, Positionen, Ziele, Waffenzyklen, Aufträge, Wirtschaft, Verträge, Entscheidungen und Krisenphase wurden identisch rekonstruiert. Die Spieleridentität blieb erhalten; nach Fortsetzen arbeitete der gespeicherte Scheduler weiter. Live-Reconnects ohne Pause werden durch die anderen Tests und die Lastläufe abgedeckt.

## Reichweite der Aussage

Die Messungen stützen den gewählten Ansatz für den nächsten Ausbauschritt. Sie testen eine vereinfachte Zwei-Seiten-Kampfsimulation, aggregierte Pop-Wirtschaft und eine einfache Patrouillen-KI. Sie beantworten noch nicht, wie viele komplexe Flottenkämpfe, taktische Pfadsuchen, individuelle Pop-Entscheidungen oder gleichzeitig beobachtete große Schlachten das spätere Spiel auf der Zielinfrastruktur tragen wird.

Längere Belastungs- und Ausfalltests, WAN-Bedingungen, Uhrabgleich, Wiederherstellung nach langen ungeplanten Ausfällen, Backup-/Schema-Migration sowie die eigentlichen 4X-Spielregeln folgen vor der vollständigen Umstellung. Die bisherigen Spielstände bleiben beim bisherigen Server.

Rohdaten und Reproduktion: [Standard](standard.json), [große Flotten](large.json), [große Einzelschlacht](battle-heavy.json), [Browser](browser.json), [Neustart](restart.json), [Start-/Testanleitung](../README.md). Die Lastreports enthalten Zeitstempel und einen SHA-256-Fingerprint des getesteten Simulationscodes.
