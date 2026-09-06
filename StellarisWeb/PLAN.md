# Ausbauplan

## Erledigt

- Browser-Spiel mit Erkundung, Kolonisierung, Kolonieausbau und KI.
- Reichs-/Speziesbibliothek und getrennte Spielinstanzen.
- SpacetimeDB-Fundament und Lastproben mit 1.000 Systemen, 25 Imperien und 75.000 Schiffen.
- Berechtigte, gedrosselte Gefechtsübersichten und an die Ansicht gebundene Detailabonnements.

## Umgesetzt: Spielmigration

1. Spielregeln auf dauerhafte, indizierte SpacetimeDB-Tabellen und Reducer übertragen. Die Node-Schicht vermittelt Lobby/Vorlagen und liefert Dateien; sie simuliert neue Partien nicht.
2. Die bestehende Spieloberfläche mit initialen Snapshots, Wiederverbindung, lokalen Fortschrittsanzeigen und gezielten Gefechtsabonnements verbinden.
3. Vorhandene Sektoren kontrolliert übernehmen. Nach Freigabe des Nutzers den automatischen Legacy-Pfad entfernen und Quellspeicher archivieren.
4. Den normalen Spielstart um eine prozedurale Galaxie mit 1.000 Systemen und 25 Plätzen erweitern. Flottenverbände, Erkundung, Kolonisierung, Wirtschaft, Forschung und KI gemeinsam prüfen.
5. Echte Mehrspieler-Verbindungen, Regel-/Besitzschutz, Speicherwiederherstellung und Browserablauf prüfen.

Ergebnis: Die Migration ist abgeschlossen. Normale Partien laufen ausschließlich über SpacetimeDB. Der alte Node-Spieltick, Snapshot-Versand, Sitzungs-Resume und automatische Import sind entfernt. Beide vorhandenen nativen Galaxien bleiben erhalten; die alten Quelldateien liegen im Archiv. Reine gemeinsame Regelbausteine und der geschützte Betreiber-Snapshot-Import für Wiederherstellung/Tests bleiben erhalten. Nachweise: [GAME-MIGRATION.md](backend/reports/GAME-MIGRATION.md) und [DIPLOMACY.md](backend/reports/DIPLOMACY.md).

## Weiterer Spielausbau in diesem Stand

- Prozedurale, verbundene Karte mit 1.000 Systemen und voneinander entfernten Startsystemen für 25 Imperien.
- Systemsuche, Zentrierung, weniger Detailbeschriftungen auf Distanz und lokale Flotteninterpolation.
- Militärische Verbände durch Werftverstärkungen, Abteilungen und Zusammenführung spielbar.
- Taktischer Gefechtsrenderer in der normalen Systemansicht; Status-/HP-Vergleich in der Übersicht.
- Faire KI-Planung für Erkundung, Kolonisierung und Wirtschaft.

## Umgesetzt: Diplomatie und Rohstofftausch

- Explizite Kriegserklärung, friedliche Durchreise und feindabhängige Gefechte, Belagerung und Missionsblockaden.
- Beidseitiger Friedensschluss beendet gemeinsame Gefechte und sichert 120 Spielsekunden Waffenstillstand.
- Private Tauschangebote mit reservierten Rohstoffen, atomarer Annahme und einmaliger Erstattung bei Ablehnung, Rücknahme, Krieg oder Ablauf.
- Dauerhafte Fristen, Pause, Hot Join und Wiederherstellung nach Datenbankabsturz geprüft.
- Diplomatie-Dialog mit Flaggen, Status, Eingangsindikator, Angebotsformular und Verlauf.
- KI antwortet auf Frieden und faire bezahlbare Tauschangebote; eigene Kriegserklärungen der KI bleiben ein späterer Ausbauschritt.

## Umgesetzt: Ereignisse und erste Krise

- Lagezentrum mit privaten Ereignissen, Entscheidungen, Kosten, Folgen, Fundort-Navigation und Verlauf.
- Anomalie-Archive und die erste Außenkolonie lösen Entscheidungen aus. Fristen zählen Spielzeit; bei Ablauf greift eine kostenlose Standardoption.
- Resonanzkaskade mit Vorwarnung, Resonanzwelle, Kaskade und gemeinsamer Eindämmung. Ungeschützte Kolonieproduktion sinkt um 25 beziehungsweise 50 Prozent; die Grundversorgung bleibt bestehen.
- Eigene Kolonien abschirmen oder gemeinsam Stabilisierung finanzieren. Beiträge werden dauerhaft verbucht und bei Erfolg einmalig mit Forschung vergütet.
- Berechtigungen, reale Produktion, Pause, spätere Beitritte, Wiederverbindungen und Datenbankabsturz geprüft. Bestehende Galaxien erhalten einen neuen Vorlauf ohne Datenreset.
- Der Ereigniskatalog ist versioniert; die erste KI-Reaktion benutzt dieselben bezahlbaren Entscheidungen. Mehrstufige Geschichten und differenzierte Krisenstrategien sind noch offen.

Nachweis: [STORIES.md](backend/reports/STORIES.md).

## Umgesetzt: Systemansicht und bebaubare Himmelskörper

- Three.js-Systemansicht mit Sternen, Planeten, Monden, Gasriesen, Asteroidenfeldern, orbitalen Ruinen, Rissen und Schwarzen Löchern.
- Auswählbare Schiffsmodelle in Formationen, Objektliste, Nahansicht, Zoom und Schwenken. Große Verbände werden visuell zusammengefasst; ihre vollständigen Bestände bleiben erhalten.
- Körperbezogene Anlagen mit Kosten, Bauzeit, drei Ausbaustufen, parallelem Bau, Abbruch und tatsächlichen Produktionserträgen.
- Dauerhafte Bauplatz-IDs und autoritative Bauaufträge, Besitzschutz und geschützte Sichtbarkeit. Pause, Wiederverbindung und Datenbankabsturz geprüft.
- Hauptkolonie bleibt erhalten; weitere Planeten und Monde erhalten Außenanlagen. Individuelle Bevölkerung und Kolonieverwaltung je zusätzlicher Welt sind noch offen.
- Taktische Positionen werden nur beim Öffnen des Gefechts angefordert. Die normale Systemansicht zeichnet Flotten aus den strategischen Daten.

Nachweis: [SYSTEM-VIEW.md](backend/reports/SYSTEM-VIEW.md).

## Umgesetzt: Raumzeitdarstellung und freie 3D-Kamera

- Perspektivische Kamera mit 360°-Drehung, Neigung, Verschieben, Mausrad-Zoom, Auswahlfokus und Rücksetzung.
- Verformte 3D-Raumzeitfläche mit analytischen, entfernungsabhängig geglätteten Konturen. Helle Körper schweben über ihren Gravitationsmulden.
- Weißglühende Sterne, prozedurale Koronen und Risse, farbiger Lichtschein, direkte Beleuchtung und abschaltbares HDR-Bloom. Dies ist kein Radiance-Cascades-Verfahren.
- Hyperlane-Portale mit tatsächlichen galaktischen Richtungen und seitlichen, anklickbaren Zielen. Ein Klick öffnet das Nachbarsystem; Flottenbefehle bleiben ausdrücklich getrennt.
- Bestehende Körper-IDs, Bauaufträge und strategische Daten bleiben unverändert. Der alte Renderer mit fester orthographischer Kamera ist entfernt.
- Produktionsbuild und 64 Regeltests bestanden; Kameradrehung, Zoom, Systemwechsel, Körper-/Schiffsfokus und Bau/Abbruch in einer isolierten Browserpartie geprüft. Native Module waren für diese visuelle Änderung unverändert.

## Umgesetzt: Galaxieerzeugung und strategische Kartografie

- Vier natürliche Galaxieformen, 400/700/1.000 Systeme und drei Hyperlane-Dichten im Startdialog mit Formvorschau.
- Deterministischer Generator mit Mindestabständen und vollständig verbundenem Navigationsgraphen. Erstellungsparameter werden validiert und für Wiederholungen dauerhaft im Gateway gespeichert.
- Zoomabhängige Beschriftungsbudgets mit Kollisionsprüfung und freiem Platz für die Bedienoberfläche; kompakte reguläre Schwarze Löcher und größere Erebus-Landmarke.
- Reichsflächen aus begrenzten Voronoi-Zellen, vereinigte innere Grenzen und mehrschichtiger Lichtsaum. Die Kartengeometrie wird nur bei Besitz- oder Positionsänderungen neu aufgebaut.
- Generator- und Kartografietests, echter Gateway-/Datenbank-Durchlauf mit gewählten Parametern und Wiederherstellung sowie Browserkontrollen.
- Alte Galaxien werden nicht umverteilt. Echter Fog of War folgt separat und muss die bisher öffentliche Karte, Erkundung und Server-Views gemeinsam ändern.

## Danach

- Veränderbare Systemobjekte dauerhaft im Backend speichern; bestehende Körperplätze und Kolonien migrieren. Darauf Terraforming, freie Stationsplatzierung, Megastrukturen und Sternveränderungen aufbauen. Architekturvorschlag: [Veränderbare Sternsysteme](backend/reports/DYNAMIC-SYSTEMS.md).
- Handelsrouten, langfristige Verträge, Bündnisse und differenziertere diplomatische KI ergänzen.
- Mehrstufige Ereignisse, weitere Krisentypen und differenziertere Reaktionen der KI.
- Taktik, Schiffsausrüstung und Beleuchtung ausbauen; Radiance Cascades separat prototypisieren und messen.

Die langfristigen Systeme sind Ausbauschritte, keine Behauptung bereits fertiger Spielfunktionen.
