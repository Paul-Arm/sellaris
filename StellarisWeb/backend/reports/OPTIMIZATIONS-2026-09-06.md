# Tagesbasierte Simulation und Client-Optimierungen

Umsetzung des [Performance-Reviews](PERFORMANCE-REVIEW-2026-09-06.md) auf dem vorhandenen Arbeitsstand. Modell-Detailstufen wurden auf Nutzerwunsch ausgelassen. Die parallel bearbeiteten Schiffsmodelle behalten ihre Geometrie, Materialien und Animationen.

## Zeitvertrag

- Autoritative Bewegung, Ankünfte, Wirtschaft, KI, Bau, Forschung und Gefechtsstände verwenden **ganze Spieltage**. Bei 1× verstreicht ein Tag je Echtzeitsekunde. Neue Fristen werden auf Tagesgrenzen aufgerundet.
- Die Uhr erhält einen kontinuierlichen Tagesanker, damit Pause und Tempowechsel keinen angebrochenen Tag verlieren. Echtzeit dient dem Scheduler und der Synchronisierung, nicht als zusätzliche Spielzeiteinheit.
- Gefechte integrieren intern fünf kleinere Schritte je Tag; Ziele, Waffenzyklen und Schaden behalten dadurch ihre bisherige Berechnung. Persistiert und veröffentlicht wird ein kompletter Tagesstand. Pro Scheduler-Aufruf werden höchstens vier Tage nachgeholt.
- Bestehende Bruchteilsstände werden am nächsten ganzen Tag fortgesetzt. Die bisherige Millitag-Kodierung der Datenbankindizes bleibt kompatibel; neue Werte liegen auf ganzen Tagen. Kein Spielstandreset.
- `sampleClock` ist eine nur lesende Serverprozedur. Der Client bestimmt aus RTT-Proben einen Zeitversatz und läuft danach mit `performance.now()`. Kleine Korrekturen werden angeglichen, Pause und Tempowechsel unmittelbar übernommen. Bei Verbindungsverlust friert die Anzeigeuhr ein.

## Umgesetzte Optimierungen

| Bereich | Ergebnis |
| --- | --- |
| System- und Galaxiereisen | Start-/Zielposition, Abfahrt und Ankunft werden bis zum Renderer weitergereicht. Jede Frameposition stammt aus derselben synchronisierten Spieluhr. Umleitung, Ankunft und Pause verwenden die jeweils verbindliche Route. |
| Gefechtsbewegung | Bis zu acht vollständige Tagesstände werden nach Ende einer SDK-Transaktion aufgenommen. Interpolation mit adaptiver Verzögerung von 80–1.600 ms Echtzeit; höchstens 150 ms Extrapolation, passend zum Spieltempo umgerechnet. Tod, Pause, Ende und neue Verbindung werden ausdrücklich behandelt. |
| GPU-Instancing | Ein gemeinsamer Schiffsmatrix-Puffer pro Modellbatch, Teiltransform und Normalenmatrix als Shader-Uniforms. Keine CPU-Multiplikation jedes Schiffes mit jedem Modellteil. Picking berücksichtigt die vollständige animierte Teiltransformation. |
| Uploads und Sichtbarkeit | Nur veränderte, belegte Matrix-/Farbbereiche werden aktualisiert. Unveränderte Formationen laden nichts hoch; leere Batches überspringen Animation und Rendering. Die Laboransicht filtert Schiffe außerhalb des Frustums vor dem Batchaufbau. |
| Clientprojektion | Normalisierte Tabellen werden durch SDK-Ereignisse gepflegt und einmal pro Transaktion veröffentlicht. Statische/unveränderte Objekte, JSON-Projektionen und Indizes bleiben stabil. Der bisherige vollständige 4-Hz-Neuaufbau entfällt. Kalender/UI können weiterhin einmal je Spieltag reagieren. |
| Galaxiekamera | Kamera, gezeichnete Marker und DOM-Klickflächen werden im selben Displayframe positioniert. React-Kameraanzeigen werden separat gedrosselt. Unveränderte Klickflächen schreiben keine neuen DOM-Positionen. |
| Kartenarbeit | Besitz-/System-/Spielerindizes, Labelplatzierungen und UI-Ausschlussflächen werden zwischengespeichert; ResizeObserver beobachtet nur neu hinzugekommene Panels. Hyperlanes werden je Stil gebündelt und außerhalb des Bildausschnitts ausgespart. |
| GPU-Effekte | Nicht blockierende GPU-Timer pro Szene/Bloom/SMAA/Output/Black-Hole-Pass. Bei vollständig außerhalb des Sichtbereichs liegendem Black-Hole-Einfluss entfällt der zusätzliche Hintergrund-/Lensing-Pass. Gravitationsquellen ohne Stärke werden im Shader übersprungen. |

Die Raumzeitfläche behält vorerst ihre 400×400 Segmente; lokal adaptive Tessellierung und reduzierte Lensing-Auflösung sind **nicht implementiert**. Die erste Messung rechtfertigt kein pauschales Senken von AA, Bloom oder Konturenqualität. Diese qualitativen Änderungen bleiben eine gezielt nachzumessende weitere Ausbaustufe. Ebenso wurde kein Modell-LOD eingebaut.

## Messungen

[Reproduzierbare CPU-Messwerte und Quellfingerprints](client-rendering-optimized-2026-09-06.json), erzeugt mit:

```powershell
node --import tsx backend/reports/measure-client-rendering.mjs
```

| Modell | Bewegte Instanzen | CPU Median / p95, ms | Veränderte Schiffsmatrizen je Frame |
| --- | ---: | ---: | ---: |
| NEXUS | 100 | 0,010 / 0,034 | 6.400 B |
| NEXUS | 1.000 | 0,031 / 0,097 | 64.000 B |
| NEXUS | 3.000 | 0,096 / 0,192 | 192.000 B |
| PRISMA | 100 | 0,009 / 0,019 | 6.400 B |
| PRISMA | 1.000 | 0,046 / 0,098 | 64.000 B |
| PRISMA | 3.000 | 0,095 / 0,204 | 192.000 B |

Dies misst ausschließlich `begin/add/end` und einfache bewegte Formationsmatrizen in Node auf dem lokalen i7-12700K, keine kompletten Frames oder GPU-Busleistung. Die Geometrie wurde parallel geändert; deshalb keine pauschale FPS-Verbesserung gegenüber dem historischen Review ableiten. Bei 3.000 Instanzen bleibt ein 262.144-Byte-Puffer reserviert, aber nur der belegte veränderte Bereich wird markiert.

Browserbeobachtungen über `canvas[data-render-metrics]`:

- 3.000 PRISMA-Kampfteilnehmer: **13 Draw Calls**, 13.152.000 Dreiecke einschließlich Teammarkierungen. Pausiert: **0 Matrix-Uploadbytes**. Bewegend: **384.000 B** insgesamt, davon je 192.000 B Schiffe und Teamringe. Eine 1×-Probe meldete rund 1.064 ms Interpolationsverzögerung.
- GPU-Pass-Stichprobe Sol: Szene 0,27 ms, Bloom 0,37 ms, SMAA 0,21 ms, Ausgabe 0,01 ms.
- GPU-Pass-Stichprobe Erebus: Szene 1,32 ms, Lensing 2,01 ms, Bloom 0,19 ms, SMAA 0,14 ms, Ausgabe 0,01 ms.
- Diese GPU-Stichproben sind geglättete Einzelbeobachtungen, keine kontrollierten Vorher-/Nachher-Benchmarks. Hintergrund-Tab-Drosselung und der 165-Hz-Displaycap erlauben hier keine belastbare FPS-Zusage. Die Passmessung liefert bei fehlender/disjunkter Timer-Unterstützung ausdrücklich keine GPU-Zeit.

## Prüfung und Betriebsgrenzen

- `npm run build` und `npm run backend:check`: bestanden.
- Vollständige Backend-Suite: **28/28 bestanden**, einschließlich Migration, Berechtigungen, Hot Join, persistiertem Gefecht, Diplomatie, Produktion und isoliertem Serverneustart.
- Gezielte finale Unit-Suite für Zeit, Interpolation, Instanzpuffer, Picking, Projektionen und Reichsänderungen: **25/25 bestanden**. Tests decken ±30 Sekunden lokale Uhrabweichung, RTT-Ausreißer, 1×/4×, Pause, Ankunft, Richtungswechsel, Tod, Reconnect und unveränderte Uploads ab.
- Der letzte vollständige Unit-Lauf enthielt 118 Tests. Zwei Erwartungen auf den alten Begriff „Spielsekunden“ wurden anschließend korrigiert und gezielt erfolgreich nachgeprüft. Ein unabhängig hinzugekommener Modellbudget-Test meldete `/models/bastion/02_fregatte.glb`: 8.572 Dreiecke gegenüber Budget 6.000. Deshalb ist der gesamte gleichzeitig bearbeitete Modellstand nicht pauschal als grün ausgewiesen.
- Im Browser wurden Sol, Erebus, Pause und das laufende 3.000-Schiffe-Gefecht geöffnet; bei den ausgelesenen Szenen keine Shader-/WebGL-Fehler. Der längere 4×-Browserlauf wurde durch einen Datenträgerfehler unterbrochen und gilt **nicht als erfolgreich abgenommen**.
- Alle **zehn registrierten Galaxien** wurden mit `--delete-data=never` aktualisiert; die Spielstände blieben erhalten.
- Laufwerk **O:** lief während der Browserprüfung voll. SpacetimeDB beendete sich beim Commitlog-Schreiben mit Windows-Fehler 112. Die beiden in diesem Durchlauf erzeugten, abgeschlossenen Neustart-Testverzeichnisse wurden entfernt; ältere isolierte Neustart-Testdaten wurden verlustfrei per NTFS komprimiert. Normale Galaxiedaten wurden weder gelöscht noch komprimiert. Der Server wurde mit demselben Datenverzeichnis wieder gestartet, beide Renderlabore sind pausiert. Rund 200 MB freier Platz reichen nicht für weitere längere Lasttests; zusätzliche Kapazität ist erforderlich.

Quellen: lokaler Code, automatisierte Prüfungen, native GPU-Timer und isolierte Testdatenbanken. Kein neuer WAN-Lasttest und keine neue Messung mit 25 gleichzeitigen Browserclients.
