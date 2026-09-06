# Review: Clientdarstellung und Skalierung

Stand: 6. September 2026, `main` bei `7465dbf` einschließlich der vorhandenen, noch nicht committeten Modellintegration. Quellstand-Fingerprints und Rohwerte: [Messdaten](client-rendering-review-2026-09-06.json).

## Wichtigste Befunde

### 1. P1 – Detaillierte Schiffsmodelle werden unabhängig von ihrer Bildschirmgröße gezeichnet

`src/model-assets.ts:209–215` erzeugt einen InstancedMesh pro Modellteil und deaktiviert Frustum-Culling. `src/LabScene.tsx:248–263` verwendet diese Modelle für jeden geladenen Kampfteilnehmer, unabhängig von Zoom und Sichtbarkeit. Es gibt keine geometrischen Fernstufen. Die Systemansicht begrenzt zwar die dargestellte Zahl pro Flotte, verwendet aber ebenfalls die vollständigen Modelle.

Direkt aus den aktuellen GLBs ausgelesen:

| Korvette | Modellteile / Zeichenaufrufe pro Batch | Dreiecke je Schiff | Dreiecke bei 3.000 Instanzen |
| --- | ---: | ---: | ---: |
| PRISMA | 11 | 4.352 | 13.056.000 |
| BASTION | 15 | 3.132 | 9.396.000 |
| VEKTOR | 4 | 4.964 | 14.892.000 |
| PARALLAX | 9 | 8.128 | 24.384.000 |
| AUREOLE | 12 | 35.340 | 106.020.000 |
| NEXUS | 14 | 41.296 | 123.888.000 |

Das sind geometrische Mengen pro Renderdurchlauf, keine gemessenen GPU-Zeiten. Instancing reduziert Zeichenaufrufe, nicht die Geometrie je Instanz. Besonders im weit herausgezoomten Gefecht werden Details verarbeitet, die auf dem Bildschirm kaum Pixel belegen.

**Vorschlag:** Nach projizierter Bildschirmgröße zwischen Nahmodell, vereinfachtem Modell und Symbol wechseln; mit Hysterese gegen Flackern. Sichtbare Instanzen vor dem Batchaufbau auswählen oder räumlich gruppieren. Statische Teile mit gleicher Material- und Transformationsgruppe zusammenfassen, bewegliche Teile getrennt lassen. Die hochwertigen Modelle für Nahansicht und Hangar erhalten.

### 2. P2 – Instancing vervielfacht derzeit CPU-Matrizenarbeit und Uploads pro Modellteil

`src/model-assets.ts:232–246` multipliziert in jedem Frame jede Schiffsmatrix mit jedem Teiltransform. Anschließend wird jeder vollständige Instanzpuffer als verändert markiert. Ohne Update-Ranges lädt das installierte Three.js den gesamten Puffer hoch (`node_modules/three/src/renderers/webgl/WebGLAttributes.js:83–94`).

Ein NEXUS-Batch mit 3.000 Schiffen benötigt bei der auf 4.096 gewachsenen Kapazität 3,5 MiB Matrizen je Update. Bei angenommenen 165 Frames/s ergeben sich rechnerisch 577,5 MiB/s. Das ist keine Messung des tatsächlichen GPU-Busdurchsatzes. Derselbe Batch führt 42.000 Teil-/Schiffsmultiplikationen pro Frame aus. Der isolierte Node-Teiltest für `begin/add/end`, einschließlich einfacher Formationsmatrizen, benötigt auf dem i7-12700K rund 1,28 ms Median und 1,74 ms p95. Rendering, Shader, Browser und übrige Szene fehlen dabei vollständig.

**Vorschlag:** Einen gemeinsamen Schiffstransform-Puffer je Batch verwenden und den animierten Teiltransform als Uniform im Vertexshader anwenden. Damit muss die CPU die Schiffstransformation nicht für jeden Modellteil erneut berechnen und übertragen. Als kleinere erste Änderung nur belegte Bereiche mit `addUpdateRange` übertragen, Farben nur bei Änderungen aktualisieren und leere Batches überspringen. Statische Formationen nur bei Daten-/Auswahländerungen neu schreiben. Shaderänderungen müssen Normalen, Picking und animierte Anbauteile mit abdecken.

### 3. P2 – Die Systemansicht interpoliert reisende Flotten noch nicht pro Frame

`src/useGame.ts:190–192` liefert alle 250 ms ein neues GameView. `backend/game-client.ts:235–237` berechnet zu diesem Zeitpunkt den Reiseprogress. `src/SystemSpaceScene.tsx:574–601` verwendet genau diesen Wert für die Annäherung an den Hyperlane-Ausgang. Die bereits vorhandene lokale Framezeit wird dabei nicht berücksichtigt. Deshalb ändern sich diese Schiffspositionen trotz schneller Renderframes nur mit ungefähr 4 Hz. Bei höherem Spieltempo wachsen die Sprünge.

Die Galaxiekarte ergänzt bereits die lokal verstrichene Zeit (`src/GalaxyMap.tsx:419–420,760`). Planetenbahnen werden ebenfalls lokal aus Phase, Periode und Spielzeit berechnet.

**Vorschlag:** Eine gemeinsame Reisebeschreibung mit Start-/Zielpunkt und Abfahrts-/Ankunftszeit bis zum Renderer durchreichen. Zwischenpositionen direkt aus der gemeinsamen Anzeigezeit berechnen. Neu eintreffende Route, Rückzug, Ankunft und Pause ausdrücklich behandeln; nicht eine Glättung über beliebige Systemwechsel legen. Ressourcen und Gefechtsergebnisse bleiben serverseitig verbindlich.

### 4. P2 – Gefechtsbewegung verwendet begrenzte Extrapolation statt gepufferter Interpolation

`src/LabScene.tsx:221,236` zeichnet `Position + Geschwindigkeit × min(0,2, Zeitdifferenz)`. Frühere Snapshots werden nicht aufbewahrt. Bei einer Richtungsänderung ersetzt der nächste Snapshot die extrapolierte Position direkt. Bei Netzwerkjitter wird zunächst extrapoliert und danach angehalten.

Die Grenze von 0,2 gilt in **Spielsekunden**. Bei 4× Tempo sind das nur 50 ms Echtzeit; der Combat-Scheduler läuft nominell alle 100 ms und kann mehrere Simulationsschritte in einer Transaktion nachholen (`spacetimedb/src/seed.ts:202`, `spacetimedb/src/simulation.ts:212`). Höheres Tempo kann deshalb sichtbare Haltephasen erzeugen, selbst ohne schwache GPU.

**Vorschlag:** Zwei oder mehrere abgeschlossene, zusammengehörige Snapshots mit `simulatedAt` puffern. Mit kleiner, am tatsächlichen Empfangsabstand orientierter Anzeigeverzögerung zwischen ihnen interpolieren. Verzögerung und maximale Extrapolation in Echtzeit definieren und korrekt in Spielzeit übersetzen. Bei Pause, Schlachtende, Tod und Reconnect die Timeline ausdrücklich zurücksetzen. Die Snapshotfrequenz erst danach reduzieren und unter Jitter prüfen.

### 5. P1 – Clientzeit hängt von der unbereinigten lokalen Rechneruhr ab

`backend/game-client.ts:40` und `src/LabScene.tsx:197` übergeben `Date.now()` direkt an `gameTimeAt`. Dort wird die Differenz zum serverseitigen `clock.wallTime` gebildet (`backend/domain.ts:9–10`). Eine 30 Sekunden vorgehende Clientuhr bedeutet bei 4× Tempo 120 zusätzliche angezeigte Spielsekunden. Eine nachgehende Uhr wird durch `max(0, ...)` auf den jeweiligen Anker begrenzt. Das verfälscht Reise-, Bau- und Animationsdarstellung, auch wenn der Server weiterhin korrekte Zustände erzwingt.

**Vorschlag:** Gemeinsame Client-Clock mit gemessenem Serverzeitversatz und RTT-Abschätzung. Danach monoton mit `performance.now()` fortschreiben und Korrekturen kontrolliert angleichen. Eine empfangene Serverzeit einfach auf den Empfangszeitpunkt zu setzen wäre zwar monoton, enthielte aber weiterhin die Netzlaufzeit. Pause und Geschwindigkeitswechsel brauchen einen neuen Anker. Tests mit ±30 Sekunden Rechnerabweichung, wechselnder Latenz und Reconnect ergänzen.

### 6. P2 – Ganze Spielansicht wird auch bei unveränderten Daten viermal pro Sekunde rekonstruiert

`src/useGame.ts:190–192` ruft bedingungslos `gameView` und `setState` auf. `backend/game-client.ts:41–46,91–126,205–255` baut Indizes, alle Systemobjekte, Verbindungen und Flotten erneut auf, parst JSON und sortiert Listen. Dadurch wechseln Objektidentitäten auch dann, wenn lediglich die Anzeigezeit fortschreitet oder die Partie pausiert ist. Die App und aktive Unteransichten erhalten den vollständigen neuen Baum.

Einige vermeintliche SDK-Indexzugriffe sind im installierten Client tatsächlich lineare Scans: `node_modules/spacetimedb/src/sdk/table_cache.ts:200–205`. Beispielsweise wird bei der Site-Projektion die Sternsuche wiederholt ausgeführt. Der vorhandene `rosterById`-Index im Lab zeigt bereits das passendere Muster.

**Vorschlag:** SDK-Transaktionen in einen normalisierten Clientstore übernehmen; unveränderte Objekte und statischen Atlas referenzstabil halten. Updates erst nach einer vollständigen Transaktion veröffentlichen. React konsumiert kleine Ausschnitte, Renderer lesen direkt den Store plus Uhr. Indizes `systemById`, `fleetsBySystem`, `sitesBySystemAndSlot` und `playerById` nur bei relevanten Datenänderungen pflegen. Die einmalige Umbauarbeit ist wichtiger als zusätzliche `useMemo`-Aufrufe auf ständig neuen Arrays.

### 7. P2 – Galaxiekamera und Kartengrafik laufen mit unterschiedlichen Aktualisierungsraten

Beide Canvas-Schleifen brechen bei weniger als 33 ms Frameabstand ab (`src/GalaxyMap.tsx:188,227`). Kameraänderungen laufen hingegen über React-Pointerevents und positionieren die DOM-Systembuttons unmittelbar. Damit bleibt die gezeichnete Karte bei ungefähr 30 Hz oder darunter, selbst auf dem 165-Hz-Monitor. Die sichtbare Position und die Klickfläche können beim Verschieben kurz auseinanderliegen.

Im Vordergrund werden außerdem pro Zeichenframe System-/Spielerindizes neu aufgebaut, Besitzschlüssel über alle Systeme gebildet und DOM-Rechtecke abgefragt (`src/GalaxyMap.tsx:230–231,258–270`). Sterne werden räumlich ausgeblendet, Hyperlanes jedoch alle einzeln gezeichnet.

**Vorschlag:** Kamerabewegung, sichtbare Marker und Klickgeometrie gemeinsam pro Displayframe aktualisieren. Langsame Nebelanimation separat drosseln, ihre Kameraabbildung aber synchron halten. Statische Ebenen, Indizes und gemessene UI-Ausschlussflächen zwischenspeichern. Zunächst Canvas-Pfade je Stil bündeln und unsichtbare Linien aussparen; ein kompletter Wechsel aller Galaxiemarker zu WebGL ist erst nach Messung notwendig.

### 8. P2 – Feste GPU-Kosten der Raumzeitfläche und des Black-Hole-Passes sind noch nicht profiliert

`src/SystemSpaceScene.tsx:214` erzeugt die Fläche mit 400×400 Segmenten: 160.801 Vertices und 320.000 Dreiecke. Der Vertexshader wertet Gravitation und Portalfaltung aus, auch bei weit entfernter Kamera. In Black-Hole-Systemen wird die Hintergrundebene ein zweites Mal gerendert (`src/BlackHolePass.ts:192–198`), einschließlich zusätzlichem HDR-Ziel, MSAA-Auflösung und Mipmaps. Der Lensing-Shader besitzt bereits einen frühen Einflussbereich-Test; außerhalb davon laufen nicht pauschal alle 144 Integrationsschritte.

**Vorschlag:** Zuerst GPU-Zeit je Pass messen. Dann grobere Fläche außerhalb relevanter Trichter, lokale Verfeinerung an Mündungen und zoomabhängige Detailstufen prüfen. Für entfernte schwarze Löcher ein kleineres Effektziel und einen begrenzten Bildschirmbereich untersuchen. Konturenqualität, Portalränder und Verdeckung als Abnahmekriterien festhalten. AA und Gesamtbelichtung nicht pauschal reduzieren.

## Bereits gute Grundlagen

- Serverautorisierte Simulation und lokale analytische Reise-/Orbitaldarstellung sind getrennt.
- Strategische Ansicht und Sidebar brauchen keine laufenden Positionen aller Kampfschiffe. Die Detailabonnements werden beim Verlassen abgebaut.
- Gefechtsdaten sind in Roster, Motion und Vitals aufgeteilt; der Lab-Renderer liest direkt aus dem SDK-Cache.
- Asteroiden und Schiffe nutzen bereits Instancing. Die Schiffsanimation wird je Prototyp/Batch ausgewertet, nicht mit einem AnimationMixer je Schiff.
- Die Systembeschriftungen bleiben an den Renderframe gekoppelt; diesen Mechanismus beim Optimieren erhalten.

## Empfohlene Reihenfolge

1. **Messbasis und gemeinsame Anzeigezeit:** CPU-/GPU-Passzeiten, tatsächliche Dreiecke, Uploadvolumen und Reaktualisierungen erfassen; Client-Clock korrigieren.
2. **Bewegung vervollständigen:** Systemflotten analytisch pro Frame darstellen, Gefechtssnapshots puffern. Mit 1×/4×, Pause, Paketjitter, Richtungswechsel und Reconnect prüfen.
3. **Flotten skalieren:** Geometrische Detailstufen und Sichtbarkeitsfilter, danach gemeinsame Instanzpuffer und Teiltransform-Uniforms. Bei 100/1.000/3.000 sichtbaren Schiffen vergleichen.
4. **Datenfluss entlasten:** Transaktionsbasierte Store-Updates, stabile Objektidentitäten und Systemindizes. Alte JSON-/Sortierarbeit aus dem Zeitfortschritt entfernen.
5. **Karte und Effekte:** Kamerasynchronität, gecachte Ebenen und anschließend gezielt gemessene Raumzeit-/Lensing-Kosten optimieren.

## Prüfung und Grenzen

`npm test`: **104 Tests bestanden**. `npm run backend:check`: **bestanden**. Keine bestehenden Spiel-/Serverdateien für diesen Review geändert; nur dieser Bericht, das Messskript und die Messdaten wurden ergänzt. Kein neuer Mehrclient-/WAN-Test und kein aktueller GPU-Benchmark wurden durchgeführt.

Die alten 165-FPS-Labwerte betreffen einfache Geometrie und den bestätigten Monitor-Cap. Sie belegen nicht die Leistung der inzwischen integrierten detaillierten Modelle. Die neuen CPU-Zahlen sind Teilmessungen in Node, keine Browser-FPS-Zusage.

Reproduktion aus `StellarisWeb`: `node --import tsx backend/reports/measure-client-rendering.mjs`. Das Skript liest lokale Modelle, misst CPU-Matrizenarbeit und schreibt JSON auf stdout; es verbindet sich mit keinem Spielserver.
