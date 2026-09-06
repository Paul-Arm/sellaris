# Ausbauplan

## Geltende Vorgabe

Alte Galaxien dürfen für die Entwicklung gelöscht werden. Abwärtskompatibilität ist keine Anforderung; inkompatible Spielstände werden durch neue Partien ersetzt. Diese Vorgabe ersetzt die Erhaltungszusagen der historischen Umsetzungsberichte.

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

## Umgesetzt: Persistente Systemobjekte – erste Etappe

- Himmelskörper mit unveränderlichen IDs, Revision, Lebenszyklus, Elternbezug und gespeicherten Bahnen/Darstellungsdaten in SpacetimeDB.
- Neue Galaxien speichern ihren Körperbestand einmalig aus dem aktuellen Generator. Leere Systeme bleiben leer; es gibt keinen Importpfad für alte Körperbestände.
- Bauprüfung verwendet gespeicherte aktive Körper und unterstützt weitere Plätze jenseits der alten Slots 0–8. Das Gravitationseffektbudget begrenzt keine Spielobjekte.
- Die Systemansicht lädt nur die Details des geöffneten Systems. Eigene Nebenwelten, Monde und andere Nebenobjekte können mit Besitz- und Revisionsprüfung dauerhaft umbenannt werden.
- Interne Funktionen für neue und entfernte Nebenobjekte; entfernte IDs werden nie wiederverwendet. Abhängige Monde, Kolonien oder Anlagen verhindern die Entfernung, bis eine eigene Ereignisregel ihre Folgen behandelt.
- Nachweis und noch offene Teile des Zielmodells: [Persistente Systemobjekte](backend/reports/SYSTEM-OBJECTS.md).

## Umgesetzt: Terraforming

- Forschung „Klimagestaltung“ schaltet die neun Klimaklassen für eigene untersuchte Planeten frei.
- Dauerhafte Projekte mit atomaren Kosten, parallelem Anlagenbau, Spielzeitfristen und einmaliger 50-%-Erstattung bei Abbruch. Systemverlust beendet Projekte ohne Erstattung.
- Hauptwelten erhalten neue Bewohnbarkeit, Wachstums- und Kolonieerträge; Namen, IDs, Bahnen, Bevölkerung und Ausbauten bleiben erhalten. Nebenwelten ändern zunächst Klima und Aussehen, ohne eigene Bevölkerung.
- Die Systemansicht zeigt Zielklima, Kosten, Ertragsvorschau und Fortschritt. Private Projektansichten, Pause, Wiederverbindung und Datenbankneustart sind geprüft.
- Die zehn bisherigen lokalen Galaxien wurden auf Nutzerfreigabe gelöscht. Eingefrorene Generatoren und die Körpermigration sind entfernt; Reichs- und Speziesvorlagen bleiben erhalten.
- Details und Prüfungen: [Terraforming](backend/reports/TERRAFORMING.md).

## Umgesetzt: Freie Systemflüge, Auftragsketten und Stationen

- Nutzerergänzung: Schiffe können frei im System fliegen, Befehle werden eingereiht und Forschungsschiffe erkunden alle Himmelskörper durch tatsächliche Anflüge.
- Autoritative lokale Flugbahnen mit X/Y/Z-Ziel, sichtbarer Interpolation und Flugpfad. Bestehende Verbände bewegen sich gemeinsam; Abteilungen werden über die Verbandsverwaltung gebildet.
- Bis zu 32 Aufträge je Flotte: Systemflug, Hyperraumreise, Erkundung und Kolonisierung. Wartende Aufträge einzeln entfernen oder stoppen und leeren. Kosten entstehen bei Ausführung; ein ungültig gewordenes Folgeziel wird mit Meldung übersprungen.
- Erkundung fliegt die aktiven Himmelskörper einschließlich Monde, Asteroidenfelder und Ruinen nacheinander an. Erst nach der vollständigen Route werden Bauplätze und Forschungsbonus freigegeben. KI nutzt dieselbe Route.
- Feste Stationspositionen mit Vorschau, Höhenwahl, Kosten, Bauzeit und Prüfung von Systemgrenzen, Abständen und Umlaufbahnen. Freie Forschungsstationen und Außenposten nutzen bestehende Ausbau-/Produktionsregeln.
- Pause, private Warteschlangen, Wiederverbindung, Datenbankneustart und parallele Aufträge geprüft. Details: [Systemnavigation und Stationen](backend/reports/SYSTEM-NAVIGATION.md).

## Danach

- Mehrstufige Megastrukturen und Sternveränderungen auf den persistenten Objekten aufbauen. Eigenständige Planetentabellen und die Folgen zerstörter Elternkörper ergänzen. Architekturvorschlag: [Veränderbare Sternsysteme](backend/reports/DYNAMIC-SYSTEMS.md).
- Handelsrouten, langfristige Verträge, Bündnisse und differenziertere diplomatische KI ergänzen.
- Mehrstufige Ereignisse, weitere Krisentypen und differenziertere Reaktionen der KI.
- Taktik, Schiffsausrüstung und Beleuchtung ausbauen; Radiance Cascades separat prototypisieren und messen.

Die langfristigen Systeme sind Ausbauschritte, keine Behauptung bereits fertiger Spielfunktionen.

- [x] Systemsteuerung: direktes Flugziel per Rechtsklick, Warteschlange per Umschalt + Rechtsklick; separates Flugziel-Menü entfernt. Objekt-Kontextmenüs mit passenden Bauaktionen, Ausbau, Abbruch und Anflug; Sternenbasis als orbitale Versorgungsanlage.

- [x] Trägheit beim Kurswechsel: Geschwindigkeit erhalten, gekrümmte Flugbahn, begrenzte Modelldrehung und Bremsweg. Orbitaler Anlagenbau/Ausbau und freie Stationen als Schiffsaufträge mit serverseitiger Nähenprüfung und Kostenbuchung erst bei Ankunft.
