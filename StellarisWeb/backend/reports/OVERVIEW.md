# Gefechtsübersicht und Detailabonnement

Gemessen: 2026-09-05T17:19:02.080Z. SpacetimeDB 2.10.0, lokal unter Windows, Gzip. Frische Galaxie mit 1.000 Systemen, 75.000 Schiffen und 25 unabhängigen Spieleridentitäten. Ein Gefecht mit 3.000 Teilnehmern. 24 Clients bleiben in der Galaxie; ein beteiligter Spieler wechselt die Ansicht. Je Phase zwölf Sekunden, nach kurzer Aufwärmzeit. Initiale Snapshots und Ansichtswechsel sind aus den laufenden Raten ausgeschlossen. Keine WAN-, FPS- oder Skalierungszusage.

| Ansicht des beteiligten Spielers | Empfang KiB/s | Alle 25 Clients KiB/s | Übersichtsupdates | Bewegungsupdates | Taktische Schiffe im Cache |
|---|---:|---:|---:|---:|---:|
| overview-before | 0.64 | 12.80 | 10 | 0 | 0 |
| battle | 334.67 | 343.13 | 10 | 180000 | 3000 |
| overview-after | 0.47 | 7.08 | 10 | 0 | 0 |

Nach Verlassen des Gefechts: **99.86 % weniger Empfang** für diesen Client als während der Detailansicht. Die Übersichtsrate enthält auch Spieluhr, Wirtschaft und berechtigte Flottenänderungen. Es werden weder Schiffsdaten noch die laufende Gefechtsuhr abonniert; HP-Zusammenfassungen werden ungefähr einmal je Echtzeitsekunde veröffentlicht.

Erstes Öffnen einschließlich Snapshot: 28.8 ms und 77.5 KiB. Beim Wiederöffnen ist der Gefechtsstand von Schritt 127 auf 190 fortgeschritten. Simulation und Schaden laufen weiter, während niemand die Details betrachtet.

Prüfungen im Skript: null Detailzeilen und null Bewegungsereignisse in beiden Übersichtsphasen, 3.000 Teilnehmer in der Gefechtsansicht, etwa 1 Hz Zusammenfassungen, fortgeschrittener Snapshot beim Wiederöffnen. Rohdaten und Quellstand-Fingerprint: [overview.json](overview.json). Reproduzieren: `npm run backend:bench:overview` nach `npm run backend:build`. Jede Ausführung legt eine neue Testdatenbank an und pausiert sie abschließend.
