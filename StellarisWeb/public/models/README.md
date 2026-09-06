# Designsets

Quelle: ChatGPT-Work-Aufgabe „Schiffsdesigns erstellen“, Stand 6. September 2026.
Übernommen aus `all_114_animated_models.zip` und `all_6_animated_orbital_rings.zip`.
Die Originalarchive, Blender-Szenen, Generatoren und Prüfberichte liegen lokal unter
`artifacts/model-import/` (nicht Teil des ausgelieferten Webclients).

Die Überarbeitung basiert auf den sechs `*_concept.png` aus
`RTS_Designs_Alle_Bilder.zip`. Referenzen und zugehörige Designblätter liegen unter
`artifacts/concept-reference/RTS_Designs/`. Das ZIP hatte kein vollständiges
Inhaltsverzeichnis; die PNG-Einträge wurden anhand ihrer lokalen Header ausgelesen
und mit Größe sowie CRC geprüft. Je Shipset wurde eine eigene Blender-Überarbeitung erstellt.

PRISMA, AUREOLE, BASTION, PARALLAX, NEXUS und VEKTOR enthalten jeweils 20 GLBs:
acht Schiffe, vier Stationsstufen, zwei Verteidigungsplattformen, fünf Mining-/Megastrukturen
und einen Orbitalring. Insgesamt 120 Modelle und 204 Animationsclips.

## Laufzeit

- glTF: +Y oben, −Z vorwärts. Die GLBs enthalten Geometrie, Grundmaterialien und Animationen.
- Die in Blender modellierten Oberflächen folgen der jeweiligen Konzeptzeichnung:
  PRISMA mit geschichteter Keramik und tiefen Graphitkanälen; AUREOLE mit elfenbeinfarbenen
  Sichelschalen und Amberlinsen; BASTION mit Navy-Panzerstufen und eingefassten Magenta-Zellen;
  PARALLAX mit mineralischen Bruchflächen und feinen Gravitationsfasern; NEXUS mit dunklen
  Metallkäfigen und verästeltem Kobaltplasma; VEKTOR mit geschlossenen Perlmutt-Rümpfen
  und flächig angesetzten Deltaflügeln.
  PARALLAX, NEXUS und VEKTOR übernehmen Oberflächenfarben direkt aus ihren Konzeptbildern.
- `conceptAuthored`-Materialien behalten ihre in Blender erstellten Farben, Rauheiten,
  Metallwerte und Emissionen. Der Client legt keinen allgemeinen SciFi-Texturatlas darüber.
  Mineral-, Plasma- und Perlmuttfarben liegen in den GLBs als eingebettete PNGs
  oder Vertexfarben. Feine gemalte Details erfordern keine fein unterteilten Meshes.
  NEXUS erhält einen langsamen Plasma-Lichtverlauf; Gravitationsfelder und Energiekanäle
  pulsieren dezent. Schmale Triebwerksplumes werden weich ausgeblendet.
- VEKTOR folgt zusätzlich der nachgereichten V1-Einzelschiff-Referenz
  (`Vektor/vektor_connected_concept.png`). Oberseiten, Unterseiten und Seitenwände
  erhalten gesampelte Perlmuttfarben und dieselbe irisierende Materialfamilie.
  Die Militärschiffe haben eine geschlossene, zusammenhängende Hauptschale mit
  physischer Dicke. Jede Kriegsschiffklasse hat einen eigenen Umriss und Querschnitt:
  kompakte Korvetten-Pfeilspitze, schlanke Fregattenlanze, Zerstörer-Doppelpfeil,
  breites Kreuzer-Delta, massiger Schlachtschiff-Mehrfachkeil und gestufter Titan.
  `tests/vektor.test.ts` prüft Materialabdeckung, Zusammenhang, geschlossene Kanten
  und Volumen der Rümpfe sowie unterscheidbare Silhouetten unabhängig von Größe,
  Streckung und Materialfarben.
- Anschlusspunkte, Knotentransformationen und Animationswerte bleiben erhalten.
  Das Ergebnis nähert die illustrierten Vorlagen mit spielbarer Geometrie an; feinste
  gemalte Details sind vereinfacht. Die vorhandenen Animationen bleiben WIP.
- Vorberechnete Umgebungsreflexe und gerichtetes Licht zeigen die Formen; animierte Energieflächen,
  weiche additive Triebwerks-/Waffen-Effekte und HDR-Bloom im Hangar ergänzen die vorhandenen Clips.
- `Idle` bzw. `*_ORBITAL_LOOP` läuft in einer Schleife. `Operate` wird während Arbeit verwendet.
- `Fire` bleibt im Hangar prüfbar. Die gegenwärtigen Gefechtsabonnements liefern keine individuellen
  Schussereignisse; die Darstellung spielt daher keine erfundenen Schussereignisse ab.
- Zeit folgt der Simulation einschließlich Pause und Tempo. Der Hangar hat einen eigenen Vorschau-Takt.
- `planet_surface_reference` bestimmt die Skalierung der Orbitalringe. `star_center` und
  `planet_center` richten umgebende Strukturen aus. Animierte innere Knoten bleiben unangetastet.
- Schiffe verwenden instanzierte GLB-Bauteile; Geometrie und Materialien werden innerhalb einer
  Szene gemeinsam verwendet. Jede Bauteilinstanz behält ihre Flottenadresse für die Auswahl.
- Nur benötigte Modelle werden geladen. Beim Szenenwechsel werden Mixer und GPU-Ressourcen freigegeben.

## Darstellung vorhandener Spielobjekte

| Spielobjekt | Modell |
|---|---|
| Korvette | Korvette |
| Forschungsschiff | Forschungsschiff; Operate bei Untersuchung |
| Kolonieschiff | Arbeiter; Operate während Kolonisierung |
| Neue Körperanlage im Bau | Baustelle Stufe 0 |
| Förderanlage Stufe 1 / Atmosphärenkollektor | Bergbaustation |
| Förderanlage ab Stufe 2 | Bergbauring |
| Sonnenkollektor | Dyson-Schwarm |
| Körper-Außenposten ab Stufe 3 | Orbitalring |
| Forschung / niedrigere Außenposten | Passende Stationsstufe |
| Kolonie, Schildbastion 0–3 | Außenposten → Sternenbasis → Festung → Zitadelle |
| Schildbastion ab Stufe 1 / 2 | Leichte / zusätzliche schwere Plattform |
| Orbitalindustrie ab Stufe 2 / 3 | Mega-Werft / zusätzlicher Orbitalring |

Diese Zuordnungen visualisieren bestehende Spielwerte. Fregatte, Zerstörer, Kreuzer,
Schlachtschiff und Titan sind im Designhangar verfügbar; eigene Bauaufträge und Kampfwerte
für diese zusätzlichen Klassen sind noch nicht Teil der Spielsimulation.

## Import aktualisieren

Die folgenden Import-/Bevel-Schritte stellen die ursprünglichen Grundmodelle wieder her.
Danach müssen die Konzept-Scripts erneut laufen, um den aktuellen Look herzustellen.

Beide entpackten Pakete gemeinsam angeben; der Import ersetzt den Katalog vollständig:

```sh
node scripts/import-models.mjs artifacts/model-import/rings artifacts/model-import/animated
```

Das Werkzeug liest die GLBs mit dem Three.js-Loader, kopiert sie in diesen Ordner und schreibt
`src/assets/model-catalog.json`. Es führt keine mitgelieferten Generatoren aus.

Materialabstimmung und Oberflächenshader liegen in `src/model-materials.ts`.
Die geometrischen Kanten lassen sich in Blender reproduzieren:

```sh
blender --background --factory-startup --python scripts/bevel-models.py
```

Das Blender-Werkzeug sichert beim ersten Lauf die ursprünglichen GLBs unter
`artifacts/model-import/surface-originals/` und baut immer von dieser Sicherung aus auf.
Bei einem neuen Quellpaket diese Sicherung zuerst in einen anderen Archivordner verschieben,
damit das neue Paket als Ausgangspunkt verwendet wird. Optional nur ein Modell bearbeiten:
`-- --only prisma/01_korvette`. Es werden ausschließlich Mesh-Primitiven ersetzt; keine
Animationen neu exportiert. `npm test` prüft weiterhin alle 204 Clips, gemeinsam genutzte
Geometrie, Materiallebensdauer und Instancing.

## Konzeptmodelle reproduzieren

Alle sechs Set-Scripts erzeugen die in Blender überarbeiteten, reduzierten Netze.
Der gemessene Katalog umfasst **392.810 statt 3.966.575 Dreiecke (−90,1 %)**.
Die 120 GLBs benötigen zusammen 79.500.384 statt 161.004.796 Bytes.
Alle 204 Animationsclips behalten ihre ursprünglichen Kanäle und Keyframewerte.
Die aufgeschlüsselten Messungen stehen in `artifacts/model-remesh/RESULTS.md`.
Ebene Panzer- und Keramikflächen verwenden wenige Polygone, gekrümmte Ringe und
Linsen erhalten nur die für ihren Umriss nötigen Segmente. Silhouetten, echte
Materialstufen, Anschlüsse und animierte Bauteile bleiben erhalten.
NEXUS backt sein bestehendes Wolkenfeld auf einen 1024²-Atlas. PARALLAX backt
die Mineralproben aus der Referenz und seine feinen Feldlinien auf Texturen.
VEKTOR behält die verbundenen, geschlossenen Rümpfe und sechs unterschiedlichen
Kriegsschiffprofile.

Blender 4.5 LTS aus dem Projektverzeichnis aufrufen, pro Set etwa:

```sh
blender --background --factory-startup --python scripts/concept-sets/prisma.py
```

Entsprechende Scripts existieren für `aureole`, `bastion`, `parallax`, `nexus` und `vektor`.
`scripts/concept_asset.py` sichert den Ausgangszustand unter
`artifacts/concept-refit/base/` und ersetzt ausschließlich Materialien und Mesh-Primitiven.
Bei Wiederholungen wird dieselbe Basis verwendet; Detailstufen akkumulieren nicht.
Bearbeitbare Blender-Beispiele, gerenderte Prüfansichten und Berichte liegen unter
`artifacts/concept-refit/<set>/`.
Die Remesh-Berichte und Vorher/Nachher-PNGs liegen unter `artifacts/model-remesh/<set>/`.
Wegen des knappen Platzes auf O: liegen große neue Blender-Vergleichsszenen unter
`C:/Users/paulp/AppData/Local/Temp/stellaris-remesh/`; die bereits fertigen NEXUS-
und VEKTOR-Vergleichsszenen wurden dort nach `archived-comparisons/<set>/` ausgelagert.
Die vollständigen GLB-Vergleichskopien bleiben in `artifacts/model-remesh/before/`.

Nach allen Blender-Durchläufen:

```sh
node scripts/finalize-concept-models.mjs
node scripts/audit-model-meshes.mjs
npm test
npm run build
```

Der Finalizer entfernt unerreichbare alte Geometrie, aktualisiert Größen und Clipdaten
im Katalog und prüft Nodes, Animationssamples, Normalen, Positionen und Indizes. Beim
Kompaktieren ändern sich interne Accessor-Adressen, aber keine Animationswerte.
`npm run build` übernimmt die Modelle in den ausgelieferten Client.
Die Prüfung lädt auch die echten Pixel eingebetteter PNGs und prüft die UVs.
`tests/model-budgets.test.ts` begrenzt Schiffe auf 6.000 Dreiecke, gewöhnliche
Anlagen auf 16.000 und vollständige Dyson-Schwärme auf 32.000. Gezählt werden
alle gerenderten Module eines Modells, einschließlich wiederholter Kollektoren.
Für den gesamten Katalog gilt ein Budget von 400.000 Dreiecken.
Der lokale Vite-Vergleich unter `/artifacts/model-remesh/compare.html` zeigt
die gesicherten und neuen Modelle mit gleicher Kamera, Skalierung, Beleuchtung,
Animationszeit und wahlweise als Drahtgitter.
