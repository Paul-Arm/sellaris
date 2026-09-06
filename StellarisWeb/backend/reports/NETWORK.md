# Gefechtstransport: kompakte Ansichten und Gzip

**85,5 % weniger empfangene Daten je Gefechtsansicht im lokalen Vergleich:** von **2.308,3 auf 334,1 KiB/s** bei 3.000 gleichzeitig simulierten Kampfteilnehmern. Die Simulationsgenauigkeit und Taktung wurden nicht reduziert.

## Was geändert wurde

- Drei berechtigte Views trennen Zugehörigkeit, Bewegung und Kampfstatus. Unveränderte Zugehörigkeit wird nicht bei jedem Bewegungsschritt erneut gesendet. Der vollständige dauerhafte Kampfzustand bleibt erhalten.
- Gzip komprimiert SpacetimeDB-Nachrichten. Der Client entpackt alle Nachrichten strikt in Empfangsreihenfolge, auch wenn komprimierte Initialsnapshots und kleine unkomprimierte Folgeupdates abwechseln.
- Der Renderer hält die Zugehörigkeit in einer Map aktuell. SDK 2.10 durchsucht bei **index.find()** derzeit den lokalen Cache; eine solche Suche für jedes Schiff in jedem Frame wäre quadratisch. Auch die Snapshot-Prüfung des Lastclients verwendet jetzt Maps.
- Die neuen Views sind additiv. Die vorhandenen Labordatenbanken wurden ohne Löschung oder erneutes Seeden aktualisiert; der spielbare Alpha-Server bleibt getrennt.

## Vergleich unter gleichen Szenariobedingungen

12th Gen Intel(R) Core(TM) i7-12700K, 20 logische CPUs, 31,8 GiB RAM, Windows 10.0.26200, Node v24.18.0, SpacetimeDB 2.10.0. Loopback: Server und Lastclients teilen denselben Rechner. Gewöhnliche Desktop-Hintergrundlast ist nicht ausgeschlossen.

Je Lauf: 1.000 Systeme, 25 verschiedene Spieleridentitäten/Autopiloten, 1.250 anfängliche Flotten, 75.000 anfängliche Schiffe, 250 Kolonien, 1.000 Pop-Kohorten und 100.000 Pops. 50 Flotten bilden eine Schlacht mit 3.000 Teilnehmern. Eine Verbindung beobachtet die Schlacht und ihre eigene ausgewählte Flotte, 24 erhalten Galaxiedaten. Drei Sekunden Aufwärmphase; je 60,3 / 60,2 / 60,1 Sekunden Messzeit. Wiederverbindungen alle 2,5 Sekunden.

| Messwert | Vollansicht, unkomprimiert | Kompakte Views, unkomprimiert | Kompakte Views, Gzip |
|---|---:|---:|---:|
| Empfang je Gefechtsclient, KiB/s | 2.308,3 | 782,5 | 334,1 |
| Alle 25 Clients, KiB/s | 2.348,9 | 823,1 | 356,3 |
| Initialer Gefechtsbeitritt, ms | 50,0 | 59,2 | 53,6 |
| Gefechts-Reconnect, ms (ein Messpunkt) | 19,1 | 20,5 | 27,0 |
| Reconnect p95 über alle 24 Wiederverbindungen, ms | 63,2 | 60,3 | 47,3 |
| Maximaler Reconnect über alle Verbindungen, ms | 64,7 | 64,6 | 63,4 |
| Kampf-Reducer inkl. Subscription-Auswertung, Mittel ms | 15,97 | 17,57 | 17,32 |
| Kampf-Reducer p95, Histogrammobergrenze ms | ≤50 | ≤50 | ≤50 |
| Kampfrückstand p95, ms | 11,4 | 12,3 | 11,7 |
| Maximal abgetasteter Kampfrückstand, ms | 17,4 | 28,4 | 25,4 |
| Konsistente Beitritts-/Reconnect-Snapshots | 49 | 49 | 49 |

Die Aufteilung allein spart **66,1 %**; Gzip spart gegenüber dem bereits kompakten Format weitere **57,3 %**. Es handelt sich um fünf 200-ms-Kampfschritte je Spielsekunde und weiterhin f32-Positionen/Geschwindigkeiten. Aufrufe des Kampf-Reducers erfolgen alle 100 ms und können ohne fälligen Schritt enden; deren Zeitmittel sind deshalb keine reinen Kosten eines vollständigen Kampfschritts.

Gemessen werden tatsächliche binäre WebSocket-Nachrichtenbytes **vor** dem Entpacken, einschließlich der Reconnect-Snapshots, ohne HTTP-Authentifizierung und TCP/TLS/WebSocket-Framing. Die Gzip-Gefechtsverbindung verarbeitete 321 komprimierte Nachrichten; ihr Spitzenwert an noch nicht fertig verarbeiteten Nachrichtenbytes betrug 118,5 KiB. Die Summe der Entpack-Wandzeiten lag bei 327,2 ms über den Messlauf; das ist keine isolierte CPU-Zeit. Native Reducer-Histogramme ersetzen keine separate Messung des Kompressions-/Netzwerkdienstes.

## Mehrere gleichzeitige Empfänger

| Last | Zehn Ansichten derselben großen Schlacht | Fünf verschiedene Gefechte |
|---|---:|---:|
| Spieleridentitäten / Verbindungen | 25 / 34 | 25 / 25 |
| Gefechte × Teilnehmer beim Start | 1 × 3.000 | 5 × 600 |
| Verbindungen mit Gefechtsdetails | 10 | 5 |
| Empfang je Gefechtsclient, Mittel KiB/s | 332,5 | 69,2 |
| Empfang aller Clients, KiB/s | 3.346,8 | 368,0 |
| Kampf-Reducer inkl. Subscriptions, Mittel ms | 17,93 | 18,69 |
| Kampfrückstand p95 / maximal, ms | 12,5 / 31,7 | 11,4 / 17,1 |
| Reconnect p95 / maximal, ms | 63,9 / 66,9 | 48,4 / 67,0 |
| Geprüfte Snapshots | 58 | 49 |
| Dauer, Sekunden | 60,1 | 60,1 |

Die zusätzlichen neun Verbindungen zur großen Schlacht verwenden dieselbe berechtigte Spieleridentität wie der erste Gefechtsclient. Sie testen Übertragungsvervielfachung und Wiederverwendung der View, **nicht zehn unabhängige Zuschaueridentitäten**. Es wird keine Sichtbarkeitsregel umgangen oder erweitert. Unterschiedliche Zuschaueridentitäten, Allianzen und eine produktive Zuschauerregel brauchen einen weiteren Test. Bei den fünf getrennten Gefechten hat jeder Beobachter eine eigene Spieleridentität.

## Integrität und Browserprüfung

Über die fünf abschließenden Lastläufe: **254 konsistente Initial-/Reconnect-Snapshots**, davon **120 Wiederverbindungen**, keine gemeldeten Integritätsfehler oder unerwarteten Verbindungsabbrüche.

**27 Spiel-/Domänen-/Transporttests und 12 native SpacetimeDB-Testfälle bestanden; TypeScript und Produktionsbuild erfolgreich.** Neue Prüfungen vergleichen die kompakten Views mit dem vollständigen Teilnehmerzustand, auch innerhalb von Transaktionscallbacks. Sie prüfen leere SQL-/Subscription-Ergebnisse für unberechtigte Identitäten, Fokuswechsel, unveränderte Zugehörigkeit bei Bewegung, atomaren Rückzug und Kampfabschluss sowie Rekonstruktion nach erzwungenem Serverneustart. Transporttests prüfen Nachrichtenreihenfolge, beschädigte Gzip-Daten, Verbindungsabbruch und Empfangsüberlast.

Im integrierten Browser wurden 1.000 Sterne/75.000 ursprüngliche Schiffe, eine Live-Ansicht mit 3.000 Kampfteilnehmern, Fokuswechsel, Wiederverbindung mit demselben Imperium und die Rückkehr zum normalen Spiel geprüft. Keine Browserwarnungen/-fehler wurden dabei erfasst. Die Datenanzeige verwendet KiB/s und den komprimierten Empfang. Das war eine Funktionsprüfung in einem anderen Browserkontext als der frühere FPS-Test; **kein neuer vergleichbarer FPS-Benchmark**. Die frühere Angabe von 165 FPS bleibt als vom Nutzer bestätigter Refresh-Cap dokumentiert und erlaubt keine Aussage über Leistungsreserven.

## Grenzen und nächste Schritte

Das Format spart Netzwerkvolumen, aber die simulierten Bewegungen werden weiterhin als einzelne persistente Zeilen geschrieben. Log-Wachstum und Server-Dauerlast wurden mit diesen kurzen Läufen nicht abschließend bewertet. WAN-Latenz/Paketverlust, längere Last- und Ausfalltests, Uhrabgleich, Wiederherstellung nach langen Ausfällen und komplexere Kampfregeln bleiben vor der Spielmigration offen.

Rohdaten: [Vollansicht](network-heavy-legacy-none-1x.json), [kompakt](network-heavy-compact-none-1x.json), [kompakt + Gzip](network-heavy-compact-gzip-1x.json), [zehn Empfänger](network-heavy-compact-gzip-10x.json), [fünf Gefechte](large-compact-gzip-1x.json). Alle fünf Reports enthalten denselben Simulations- und Client-Fingerprint. Frühere Diagnoseläufe mit quadratischer Clientprüfung sind separat unter [diagnostic-pre-index](diagnostic-pre-index/README.md) erhalten und nicht Grundlage der obigen Vergleichswerte.

Reproduktion nach Backendbuild und Start: **node backend/compare-network.mjs 60**, anschließend **node backend/report-network.mjs**. Alle fünf Läufe werden nacheinander ausgeführt; währenddessen keine Builds oder weiteren Lasttests starten. Details zum Start und zu Einzeloptionen: [Backend-Anleitung](../README.md). Die aktuellen Views unterstützen weiterhin **--detail=legacy --compression=none** für Vergleiche.
