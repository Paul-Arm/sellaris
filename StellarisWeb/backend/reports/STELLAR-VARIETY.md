# Sternmaterialien und Sternvielfalt

06.09.2026.

## Licht und Gestaltung

Der bisherige Sternshader erzeugte RGB-Werte um 3,5 und damit eine ausgedehnte weiße Bloom-Fläche. Sterne besitzen jetzt eigene Materialien mit begrenzter Emission, Randabdunklung, langsam wandernden Plasmazellen und einer feinen Korona. Sol bleibt warmweiß; sein rosa Licht auf der Raumzeitfläche bleibt erhalten. Globale Belichtung, Punktlichtleistung und allgemeine Bloom-Stärke wurden für diese Änderung nicht gesenkt. Das bestehende MSAA/SMAA bleibt aktiv.

Die Darstellung folgt einer gemeinsamen, deterministischen Klassifikation in `shared/stellar.ts`:

- O/B-Sterne: blau bis blauweiß, O-Sterne mit größerem Kern und kräftigerer, begrenzter Korona.
- F/G-Sterne: warmweiß; K/M-Sterne: orange bis rot. Riesensterne haben größere sichtbare Oberflächen.
- Neutronensterne: kompakte blauweiße Körper mit räumlichen Magnetfeldbögen.
- Pulsare: Neutronensterne mit geneigten, rotierenden Strahlungskegeln. Die Bewegung folgt der Spielzeit und hält bei Pause an.
- Schwarze Löcher: dunkler Horizont, schmaler Photonenring, geneigte, differenziell animierte Akkretionsscheibe und dezente zusätzliche Lichtbögen.
- Quasare: aktive Schwarze Löcher mit heller Scheibe und zwei langen polaren Jets. Sie werden als aktive galaktische Kerne beschrieben; die Darstellung komprimiert ihre Maßstäbe für die Spielkarte.

Die zunächst stilisierte Lichtabbildung am Schwarzen Loch wurde inzwischen durch einen [numerischen Schwarzschild-Shader](BLACK-HOLE-SHADER.md) ersetzt; der verlinkte Bericht beschreibt das aktuelle Modell und seine Grenzen. Die Beleuchtung verwendet weiterhin Shader, direkte Lichter und Bloom, keine Radiance Cascades. Primäre gestalterische Referenzen: [NASA Sternklassen und Sternreste](https://science.nasa.gov/exoplanets/stars/), [NASA Schwarze Löcher](https://science.nasa.gov/universe/black-holes/anatomy/), [NASA Quasare](https://science.nasa.gov/mission/hubble/science/science-behind-the-discoveries/hubble-quasars/).

## Bestehende und neue Galaxien

Die ursprünglichen benannten Sterne behalten ihre Spektralklasse. Prozedurale Sterne ab `s30` mit den ursprünglichen vier Standardklassen erhalten anhand ihrer dauerhaften ID seltene O-, NS- und PSR-Varianten sowie zusätzliche Spektralfarben. Diese Anzeigezuordnung gilt auch für bestehende Galaxien und ist nach erneuter Projektion unverändert. Systemart, Besitz, Bahnen, Bauplatz-IDs und erlaubte Anlagen bleiben dabei erhalten; es ist kein Modulupdate bestehender Partien erforderlich.

Der Generator neuer Galaxien speichert die erweiterten Klassen unmittelbar und erzeugt zusätzlich seltene Schwarze Löcher beziehungsweise Quasare. Quasare haben die bestehende autoritative Systemart `blackhole` und erhalten keine kolonisierbare Hauptwelt. Die Zahl der Systeme bleibt 1.000; das Navigationsnetz bleibt verbunden. Das native Modul wurde neu gebaut, sodass der Gateway die Erweiterung bei neuen Galaxien verwendet. Bestehende Partien wurden nicht neu veröffentlicht oder umgeschrieben.

Systeminspektor und Körperleiste zeigen die jeweilige Klasse. Die Galaxiesuche findet neben Namen auch Klassen und Begriffe wie `O-Klasse`, `Neutronenstern`, `Pulsar` und `Quasar`.

## Prüfung

- 69 Root-Tests erfolgreich, einschließlich neuer Prüfungen für deterministische Vielfalt, unveränderte Bauadressen, verbundene Navigation und nicht kolonisierbare Quasare.
- Sechs native Integrationstests aus `game.test.ts` und `sites.test.ts` erfolgreich: Gründung mit 1.000 Systemen/25 Imperien, Rechte, bestehende Welten, KI, Gefechte und Bauanlagen.
- TypeScript, Produktionsbuild und nativer Modulbuild erfolgreich. Der bekannte Vite-Hinweis zu großen Haupt-/Three-Chunks bleibt bestehen.
- Bestehende Vorschau `3F962F`: Sol in Übersicht/Nahansicht, Pulsar Lyra 066 mit aktiver Spielzeit, Erebus mit vollständiger Scheibe in Nahansicht, Klassifikation und Navigation geprüft. Abschließend wieder Sol geöffnet.
- Separate, pausierte Testgalaxie `90AFDA` auf Port 52306: O-Stern Vesper 064, Neutronenstern Talos 065 und Quasar Vesper 194; Klassensuche und Quasar-Kameradrehung/Nahansicht geprüft.
- In der Browserprüfung gefundene Shaderfehler korrigiert: Eingaben von Potenzen werden begrenzt, damit Rundungsfehler keine NaN-Werte im Bloom-Puffer verbreiten. Ein reservierter GLSL-Bezeichner wurde ersetzt. Anschließende Prüfungen ohne neue Shaderfehler; das Browserprotokoll der bestehenden Vorschau enthält noch den früheren, zeitlich zugeordneten Fehler.

Die Testgalaxie bleibt pausiert. In der bestehenden Partie wurden keine neuen Spieler, Bauaufträge oder Reisebefehle für diese Prüfung angelegt. Keine neue FPS-Zusage oder Großlastmessung.
