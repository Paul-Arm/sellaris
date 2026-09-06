# Systemlabels und Kantenglättung

06.09.2026. Reine Frontend-Änderung; bestehende Spielstände und native Spielregeln bleiben unberührt.

## Ursache und Umsetzung

Die selbst projizierten HTML-Labels wurden bisher nur alle 70 ms aktualisiert. Die Three.js-Kamera wurde dagegen mit jedem Browserbild bewegt. Diese unterschiedliche Taktung verursachte das sichtbare Nachhinken.

Körperbeschriftungen sind jetzt echte `CSS2DObject`-Kinder der jeweiligen Three.js-Körper. `CSS2DRenderer` zeichnet sie unmittelbar nach der Szene mit derselben Kamera in jedem Frame. Auch Kollisionsprüfung und seitliche Hyperlane-Positionen werden in jedem Frame berechnet. Nur die numerische Zoomanzeige bleibt gedrosselt. Labelgrößen werden bei Zustandsänderungen, Schriftladen und Größenänderungen bestimmt; der Framepfad liest keine Labelbreiten aus dem DOM.

Bei vorhandenen `layoutSubtree`, `requestPaint` und `drawElementImage` verwendet dieselbe Labelschicht stattdessen natives HTML-in-Canvas. Szene und HTML werden gemeinsam im Canvas-`paint`-Ereignis präsentiert. `drawable` und die aktuelle automatische Treffergeometrie werden unterstützt; für den älteren Origin-Trial wird die zurückgegebene Transformationsmatrix verwendet. Fehlende, fehlerhafte oder ausbleibende Paint-Unterstützung schaltet auf Three.js CSS2D zurück. Es wurde keine zusätzliche CanvasUI-Bibliothek installiert.

Die native API ist weiterhin experimentell: [WICG-Entwurf](https://wicg.github.io/html-in-canvas/), [älterer Chrome-Origin-Trial](https://developer.chrome.com/blog/html-in-canvas-origin-trial). Der hier geprüfte eingebettete Browser verwendet `three-css2d`; der native Zeichen- und Trefferpfad wurde in diesem Browser nicht praktisch validiert.

## Antialiasing

Das bisherige `antialias: true` am WebGL-Canvas glättete den separaten Composer-Puffer nicht. Die Systemansicht verwendet jetzt bis zu vier MSAA-Samples direkt im HDR-Renderziel. Die gemeinsame Sample-Unterstützung von RGBA16F und Tiefenpuffer wird beim Initialisieren abgefragt. Zusätzlich folgt SMAA nach Bloom und vor OutputPass, entsprechend dem linearen Farbraum der installierten Three.js-Version. SMAA bleibt auch ohne MSAA-Unterstützung aktiv. Die HTML-Schrift wird separat gezeichnet und durchläuft keinen Weichzeichner.

Passgrößen folgen dem Composer bei Fensteränderungen; SMAA und Renderziele werden beim Verlassen der Ansicht freigegeben. [Three.js SMAAPass](https://threejs.org/docs/pages/SMAAPass.html), [RenderTarget samples](https://threejs.org/docs/pages/RenderTarget.html).

## Prüfung

- 67 Tests bestanden, darunter drei neue Tests für gemeinsame Szene/HUD-Präsentation, Zusammenfassung ausstehender nativer Frames und Rückfall bei unvollständiger API. 165 aufeinanderfolgende Kamerazustände werden geprüft; das ist keine FPS-Messung.
- TypeScript und Produktionsbuild erfolgreich. Die bestehenden Vite-Hinweise zu großen Haupt-/Three-Chunks bleiben bestehen.
- Bestehende Vorschau auf Port 52306, Raum 3F962F: tatsächlich aktiv sind `msaa-4+smaa` und `three-css2d`.
- Szene und Labels vor und nach Kameradrehung visuell geprüft. Auswahl über das bewegte Mars-Label bestätigt. Seitliches Hyperlane-Label öffnet Alpha Centauri; Rückweg nach Sol funktioniert.
- Keine Browserfehler oder -warnungen während dieser Prüfung. Keine Spielbefehle oder neuen Spieler für diese Prüfung angelegt.

Eine Zusage von 165 FPS oder vollständiger nativer HTML-in-Canvas-Kompatibilität ist nicht Bestandteil dieser Prüfung.
