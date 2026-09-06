# Raumzeitkarte: Gestaltung und Browserprüfung

05.09.2026. Frontend-Erweiterung der bestehenden Systemansicht, ohne Änderungen an nativen Tabellen, Spielregeln oder Bauplatz-IDs.

## Darstellung

`SystemSpaceScene.tsx` ersetzt den Renderer mit fester orthographischer Kamera. Eine perspektivische Orbit-Kamera erlaubt 360 Grad Drehung, Neigung von nahezu oben bis zu einem flachen Blickwinkel, Verschieben, Zoomen, Auswahlfokus und Rücksetzung. Mausrad und Schaltflächen verwenden dieselbe Kameradistanz. Animationen folgen der gemeinsamen Spielzeit; der Renderloop folgt der Browser-Bildrate, ohne eigenen 60-FPS-Begrenzer.

Ein begrenztes Mesh mit 320 × 320 Segmenten wird im Vertex-Shader anhand von maximal zehn Potentialquellen verformt. Die Konturen werden im Fragment-Shader analytisch ausgewertet, damit Vergrößerungen nicht die Dreiecksstruktur als kantige Linien zeigen. Körper schweben über der Fläche, um auch bei flachen Blickwinkeln sichtbar zu bleiben. Monde, Ruinen, Gasringe, Schiffsformationen und Bauanlagen bleiben auswählbar beziehungsweise sichtbar. Instanzgrenzen verteilen das Schiffsbudget weiterhin über alle sichtbaren Verbände.

Sternkerne und Koronen geben hohe Helligkeitswerte aus. Ein HDR-Postprocessing-Pfad mit abschaltbarem Bloom und abschließender Tonwertabbildung erzeugt den Lichtschein. Bei Nahansichten sinkt die Bloom-Stärke. Die Oberfläche erhält analytischen farbigen Lichtschein; Schiffe und Anlagen erhalten direkte Beleuchtung. Das ist eine stilisierte Darstellung, keine physikalische Raumzeitberechnung und kein Radiance-Cascades-Verfahren.

Die Hyperlane-Portale entsprechen ausschließlich echten Einträgen in `game.links`, mit der Richtung aus den galaktischen Systemkoordinaten. Beschriftungen bleiben an den Seiten, ändern ihre Richtung mit der Kamera und öffnen das jeweilige Nachbarsystem. Das Betrachten eines Systems erteilt keinen Reisebefehl. Körperverwaltung und Gefechts-Abonnements bleiben getrennt.

## Prüfung dieser Änderung

- `npm test`: 64 Tests bestanden.
- `npm run build`: TypeScript und Produktionsbuild erfolgreich. Bestehender Vite-Größenhinweis für Haupt-/Three-Chunks; die Systemansicht wird separat nachgeladen.
- Eigene Browser-Testpartie `3F962F` auf Gateway `52306`: Drehung und Neigung durch Mausziehen, Zoom mit Mausrad, Zentrieren, Mond- und Schiffsfokus geprüft.
- Hyperlane von Sol nach Alpha Centauri und zurück geöffnet; reale Nachbarsysteme und neue Körperauswahl korrekt dargestellt.
- Förderanlage auf Luna in pausierter Testpartie errichtet und abgebrochen; autoritativer Bauzustand und Erstattung in der UI sichtbar.
- 1280 × 720: Oberfläche und Shader wiederholt visuell überprüft. Fehler bei der Darstellung korrigiert: sichtbarer Flächenrand, zu dominante Konturen, mittige Hyperlane-Beschriftungen, verdeckte Körper bei flacher Kamera und Überstrahlung der Oberfläche in Nahansichten.

- Der goldene Riss in Nahansicht sowie die Schalter für Konturen und Licht geprüft; keine Browserfehler oder -warnungen im abschließenden Ablauf.

Es wurden keine Testspieler oder Bauaufträge in den bestehenden Hauptpartien angelegt. Für diese reine Frontend-Änderung war kein Modulupdate bestehender Galaxien erforderlich. Eine neue Großlastmessung oder Zusage einer bestimmten FPS-Zahl ist nicht Bestandteil dieser Prüfung.

Die lokalen Hauptdienste waren zu Beginn der Browserprüfung beendet und wurden auf den bestehenden Datenverzeichnissen gestartet (Gateway 3001, SpacetimeDB 3100). Die pausierte Testpartie bleibt auf Port 52306 als ausdrücklich geöffnete Vorschau erreichbar. Ihre Daten liegen getrennt in `.spacetime/system-ui-data`.
