# Schwarzschild-Shader für die Systemansicht

06.09.2026.

## Modell und Darstellung

`src/BlackHolePass.ts` ersetzt die zuvor sichtbare schwarze Kugel, die flache Ringgeometrie und den aufgesetzten Lichtbogen. Ein Three.js-Renderpass integriert pro Bildpunkt gekrümmte Nullgeodäten in einer Schwarzschild-Raumzeit. Die Kamera und die geneigte Scheibe sind dreidimensional; Kameradrehungen verändern die berechneten Scheibenschnittpunkte.

In Einheiten des Schwarzschild-Radius gilt für den inversen Radius `u = rs/r` die Gleichung `u'' = 1.5 u² − u`. Die Integration verwendet RK4 mit begrenzter adaptiver Schrittweite und höchstens 144 Schritten pro Pixel. Scheibenschnittpunkte werden innerhalb des jeweiligen Schritts erneut berechnet. Eingefangene Strahlen enden schwarz; nahe der kritischen Bahn entstehen zusätzliche Bilder der Scheibe. Die Scheibe beginnt bei `3 rs`, der innersten stabilen Kreisbahn dieses Modells. Die Referenz für die Gleichung ist [Eric Bruneton: A Real-time High-quality Black Hole Shader, Gleichung 8](https://ebruneton.github.io/black_hole_shader/paper.pdf). Dies ist eine eigene numerische Implementierung, keine Übernahme von Brunetons vorberechneten Lookup-Tabellen.

Kreisbahngeschwindigkeit, gravitative Rotverschiebung und Dopplerverschiebung steuern Farbe und relative Intensität der Scheibe. Ihre Emission und ihr Plasmamuster bleiben gestalterische Modelle. Zwei überblendete Strömungsfelder mit begrenzter Lebensdauer verhindern, dass differentielle Rotation in alten Partien beliebig feine, flimmernde Muster erzeugt. Die Bewegung folgt der Spielzeit. Die Scheibenemission ist begrenzt; globale Belichtung, Raumbeleuchtung und Sternmaterialien bleiben erhalten.

## Einbindung

- Eigener HDR-Pass vor Bloom, SMAA und Tonemapping, ausschließlich in Systemen der Art `blackhole`; Quasare verwenden denselben Pass mit einer anderen Emissionspalette und ihren vorhandenen Jets.
- Die 4×-MSAA/SMAA-Pipeline bleibt erhalten. Für zusammengedrückte Hintergrunddetails werden Mipmaps verwendet.
- Eine separate Hintergrundtextur enthält nur Raumzeitfläche und entfernte Sterne. Auswählbare Körper, Schiffe und Hyperlane-Markierungen werden nicht durch diese Textur mehrfach abgebildet oder von ihren Auswahlpositionen getrennt.
- Der Tiefenvergleich zwischen vollständiger Szene und separatem Hintergrund ordnet feste Spielobjekte gegenüber Scheibe und Schatten ein. Die Koordinatenfläche verdeckt die Außenseiten eingebetteter Wurmlöcher; ihre Tiefe wird beim Black-Hole-Raytracing vom Hintergrund unterschieden und kann deshalb nicht durch den schwarzen Kern scheinen.
- Unsichtbare Auswahlgeometrie und Three.js-Labels bleiben erhalten; der zusätzliche weiße Auswahlring um das schwarze Loch entfällt. Die Nahansicht hält mehr Abstand, damit die gesamte Scheibe ins Bild passt.
- Renderziele, Tiefentexturen, Materialien und Pass-Ressourcen werden bei Ansichtswechseln freigegeben.

## Grenzen

Das Modell beschreibt ein nicht rotierendes schwarzes Loch, keine Kerr-Raumzeit oder GRMHD-Simulation. Die Scheibe ist geometrisch dünn, mit einer nahezu opaken Emissionsschicht. Extrem schmale Bilder nahe der kritischen Bahn bleiben durch Pixelgröße und Integrationsbudget begrenzt.

Die Hintergrundverzerrung projiziert die berechnete Fluchtrichtung auf eine Bildschirmtextur. Außerhalb des Bildes wird ein dunkler prozeduraler Himmel verwendet. Das rekonstruiert keine vollständige Umgebung hinter der Kamera. Strategische Spielobjekte behalten bewusst ihre normale Projektion; ihre Verdeckung nutzt eine euklidische Tiefennäherung. Der neue Shader ist kein vollständiger relativistischer Renderer aller Spielobjekte und keine Radiance-Cascades-Beleuchtung.

## Prüfung

- `npm test`: 73 Tests erfolgreich. Vier neue Tests prüfen die analytische Einfanggrenze `sqrt(27)/2`, die Nähe zur Photonensphäre, die Energie am Umkehrpunkt, die schwache Lichtablenkung und die Konvergenz gegenüber kleineren Integrationsschritten. Diese Float64-Referenztests validieren das numerische Modell, nicht separat die GPU-Ausführung.
- `npm run build`: TypeScript und Produktionsbuild erfolgreich. Der vorhandene Vite-Hinweis zur Größe der Haupt-/Three-Chunks bleibt bestehen.
- Browser auf Port 52306, bestehende Partie `3F962F`: Erebus in Übersicht und Nahansicht, hohe und flache Kamerawinkel, Bloom und Konturen aus/ein sowie Auswahl des Asteroidenfelds geprüft. Keine neuen WebGL-/Shaderfehler im Browserprotokoll.
- Sol mit Planeten und Schiffen geprüft; der neue Pass ist dort deaktiviert. Im Browser sind `msaa-4+smaa` und das vorhandene Three.js-CSS2D-HUD aktiv.
- Keine neue Quasar-Partie für diese Änderung angelegt, keine Spielbefehle oder Backend-Migrationen ausgeführt. Keine neue FPS-Zusage oder GPU-Benchmarkmessung.
