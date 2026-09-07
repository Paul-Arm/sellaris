# Materiedekompressor

Die zweite Megastruktur erschließt Mineralien an einem ruhigen Schwarzen Loch. Forschung „Megakonstruktion“, vollständige Systemuntersuchung und ein eigenes Schiff vor Ort sind erforderlich. Quasare sind ausgeschlossen. In unbeanspruchten Schwarzen-Loch-Systemen besitzt das errichtende Reich die Anlage; es entsteht keine Kolonie und kein zusätzlicher Punkt für das Siegziel.

| Etappe | Energie | Mineralien | Spieltage | Mineralien je 4 Spieltage |
| --- | ---: | ---: | ---: | ---: |
| Gravitationsanker | 500 | 400 | 60 | 0 |
| Extraktionsring | 1.400 | 900 | 100 | 25 |
| Vollständiger Materiedekompressor | 2.800 | 1.800 | 160 | 75 |

Die Erträge sind Gesamtwerte der erreichten Stufe. Während eines Ausbaus produziert die bisherige Stufe weiter. Die Resonanzkrise beeinflusst auch diese Produktion.

Rechtsklick auf das Schwarze Loch → „Materiedekompressor verwalten“ öffnet Bauetappen und Voraussetzungen. Bau und Ausbau sind Schiffsaufträge mit tatsächlichem Anflug, Nähenprüfung und Kostenbuchung bei Baustart. Eine Forschungsstation am zentralen Körper kann parallel betrieben werden.

Die Anlage besitzt eine eigene dauerhafte Objekt-ID und einen Elternverweis auf das Schwarze Loch. Je Zentralkörper ist eine Megastruktur erlaubt, unabhängig vom errichtenden Reich. Fremde Anlagen können nicht ausgebaut oder abgebrochen werden. Ein Abbruch erstattet einmalig 50 % der aktuellen Baukosten; ein abgebrochener erster Anker wird entfernt. Spätere Abbrüche behalten die bestehende Anlage, ihre ID und Produktion. Fertigstellung prüft Bauziel und Gebietsberechtigung erneut.

Die Szene verwendet Baugerüst, Extraktionsstation und wachsenden Ring oberhalb des Ereignishorizonts. Polare Strukturen kennzeichnen den Materiedekompressor gegenüber einem Dyson-Schwarm. Kosten, Etappennamen, Produktionsart und Bauträger sind im gemeinsamen Megastrukturkatalog definiert; der Sternkollaps bleibt an die Dyson-Anlage gebunden.

## Prüfung

- Regeltests: geeignete Bauträger, Quasarausschluss, Gebietsprüfung, Anlagenplatz, Mineralienproduktion, Krisenfaktor und unterschiedliche Etappenmodelle.
- `backend/tests/decompressor.test.ts`: separate Datenbank und zwei Reiche, verzögerter Anflug, Pause, alle Bauetappen, parallele Forschungsstation, Revierkonkurrenz, Besitzschutz, Abbruch, Erstattung, stabile IDs, Wiederverbindung und tatsächliche Mineralienauszahlung.
- Der bestehende native Dyson-/Sternkollaps-Test prüft die gemeinsam weiterentwickelten Bauregeln weiter.
- Browserprüfung der neuen Projektansicht am Schwarzen Loch im separaten Testsektor `82AD0D`. Der Nutzersektor `5C69F4` wird dafür nicht bespielt.

Weitere Megastrukturen und natürliche Sternereignisse bleiben nachfolgende Schritte.
