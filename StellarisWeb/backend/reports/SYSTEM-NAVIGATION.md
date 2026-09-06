# Systemnavigation und freie Stationen

Stand: 6. September 2026.

## Spielablauf

Eigene Flotten besitzen lokale Positionen im Systemraum. Rechtsklick in den freien Systemraum setzt direkt ein Flugziel auf der aktuellen Flughöhe; Umschalt + Rechtsklick hängt es an. Der Flugpfad und die Warteschlange bleiben sichtbar. Ein eigenes Flugziel-Menü entfällt. X/Z liegen innerhalb eines Radius von 1.600 Einheiten, Y zwischen 0 und 400. Lokale Flüge benötigen Entfernung / 80 Spieltage, mindestens vier Tage. Eine Hermite-Kurve erhält bei Zielwechseln die aktuelle Geschwindigkeit: Das Schiff driftet weiter und schwenkt in einem Bogen ein. Ohne Anfangsgeschwindigkeit entspricht sie Smoothstep. Server und Darstellung verwenden dieselbe Kurve; die Routenvorschau zeichnet den Bogen. Modelle drehen mit begrenzter Winkelgeschwindigkeit und neigen sich leicht in Kurven. Die Steuerung gilt pro bestehendem Flottenverband; militärische Abteilungen können über die Verbandsverwaltung getrennt werden.

Eine Warteschlange hält bis zu 32 Aufträge: lokale Flüge, Hyperraumreisen, Erkundung und Kolonisierung. Ein direkter lokaler Flug ersetzt den aktiven Auftrag samt Warteschlange atomar und startet an der aktuellen Position. Ungültige Ziele lassen die bisherigen Aufträge bestehen. Erkundung und Kolonisierung werden über ihre Aktionsknöpfe angehängt. Wartende Aufträge können einzeln entfernt werden. Stoppen leert die Warteschlange und bremst die vorhandene Geschwindigkeit über drei Spieltage mit endlichem Bremsweg ab. Ein bereits begonnener Hyperraumabschnitt bleibt verbindlich und endet am nächsten System; spätere Abschnitte entfallen. Eine abgebrochene Kolonisierung erstattet die reservierten Gründungskosten einmalig.

Kosten und situationsabhängige Regeln gelten bei Ausführung. Wird ein wartender Auftrag ungültig, meldet das Ereignisprotokoll den Grund und die Flotte fährt mit dem nächsten Auftrag fort. Warteschlangen werden nur dem Besitzer gezeigt. Sichtbare fremde Flotten liefern ihre aktuelle Bewegungsbahn, aber keine Folgeaufträge oder Erkundungsziele.

## Erkundung

Forschungsschiffe fliegen jeden aktiven natürlichen Körper sowie Ruinen im System in stabiler Slot-Reihenfolge an. Monde werden über ihre Elternbahn verortet. Der Zielpunkt berücksichtigt die Bewegung während des Anflugs. Am Ziel dauert die Untersuchung einen Spieltag. Erst nach dem letzten Körper wird das System untersucht, der bisherige einmalige Forschungsbonus ausgezahlt und gegebenenfalls ein Ereignis ausgelöst. Neu gebaute Stationen zählen nicht als unerkundete Himmelskörper.

Die Erkundung ist ein persistenter Zustandsautomat: Anflug → Untersuchung → nächster Körper. Flugbahn, Zielkörper und besuchte Körper werden gespeichert. Pause hält die Spieluhr an. Feindkontakt blockiert Aufträge; beim Gefechtsbeginn wird die lokale Bahn eingefroren und nach Freigabe fortgesetzt. Auch die zivile KI verwendet die neue Erkundung.

## Objektaktionen

Rechtsklick auf Körper, Beschriftungen, Atlas-Einträge, Flotten und Hyperlane-Zugänge öffnet ein Kontextmenü am Zeiger. Es bietet passende Aktionen einschließlich Details, Anflug, Erkundung, Bau, Ausbau und Bauabbruch. Fehlende Rohstoffe, Untersuchung oder Besitz sperren Bauaktionen mit einem Hinweis. Escape, Schließen und Klick außerhalb schließen das Menü; Pfeiltasten wählen Aktionen.

Sterne bieten eine Sternenbasis als Versorgungs- und Handelsanlage (150 Energie, 180 Mineralien, 24 Tage; 2 Energie, 2 Mineralien und 1 Forschung je Stufe pro vier Tage). Sie nutzt einen Anlagenplatz und drei Ausbaustufen. Asteroiden bieten die vorhandene Förderanlage unter „Bergbaustation bauen“. Die Sternenbasis ergänzt keine neue Kampfmechanik.

## Bauanflug

Körperanlagen, Ausbauten und freie Stationen benötigen ein eigenes Schiff im selben System. Die Oberfläche verwendet das ausgewählte Schiff oder automatisch einen freien Verband, bevorzugt das Arbeiterschiff (Kolonieschiff). Der Auftrag wird an dessen Warteschlange angehängt. Bei größerer Entfernung fliegt der Verband zunächst zum Bauplatz; bewegte Körper werden anhand ihrer künftigen Orbitalposition angeflogen.

Der Server prüft unmittelbar vor dem Baustart einen Abstand von höchstens Körperradius plus 100 Einheiten; bei freien Stationen 100 Einheiten zum Bauplatz. Erst dann entstehen Baustelle und Kostenbuchung. Fehlende Rohstoffe, Systemverlust, entfernte Objekte oder bereits belegte Plätze verhindern den Baustart. Anflug abbrechen/leeren kostet nichts. Begonnene Anlagen bauen nach bisherigen Regeln selbstständig weiter; das Schiff kann weitere Aufträge ausführen.

## Stationsplatzierung

`CelestialBody.position` speichert eine feste Position statt einer Umlaufbahn. Freie Stationen sind normale persistente Objekte mit monotoner ID, Name und Revision. Der Server prüft Besitz, Untersuchung, Koordinaten, eine Grenze von 24 freien Stationen je System sowie Abstand zu bestehenden Objekten und vollständigen Umlaufbahnen einschließlich Mondumgebung.

Forschungsstationen und Außenposten verwenden die bestehenden Kosten, Baufristen, drei Ausbaustufen und realen Erträge. Die Platzierung und die erste Kostenbuchung sind eine Transaktion. Ungültige Platzierungen hinterlassen kein Objekt. Der Abbruch eines ersten Bauauftrags erstattet 50 % und entfernt die Baustelle; die ID wird nicht wiederverwendet. Stationsobjekte erzeugen keine Gravitationsmulde.

## Technik und Grenzen

- `shared/navigation.ts`: gemeinsame Koordinaten, Bahnauswertung und Fluginterpolation.
- `game_navigation`: persistente Flottenaufträge, lokale Bewegung, Erkundungsfortschritt und Fristenindex.
- `game-navigation.ts`: Besitz-/Eingabeprüfung, Ausführung, Abbruch, Folgebefehle und Erkundung.
- `game_fleet_info`: berechtigte Bewegungsprojektion; Folgeaufträge ausschließlich für den Besitzer.
- `SystemSpaceScene` / `NavigationPanel`: Kartenwahl, räumliche Vorschau, Flottenbewegung und Warteschlange.

Die lokale Navigation ergänzt die strategischen Flotten. Gefechte verwenden weiterhin ihre eigene taktische Simulation und beginnen nach den bisherigen Regeln bei feindlicher Anwesenheit im selben System. Kollisionsvermeidung für Flugwege und ein verpflichtender Anflug auf Hyperlane-Portale sind spätere Ausbauschritte. Die Stationsprüfung vermeidet Körperbahnen; frei fliegende Schiffe sind noch keine vollständige physikalische Raumflugsimulation.

## Prüfungen

- 123 Regeltests und 31 Backendtests erfolgreich.
- Nativer Test mit mehreren Identitäten: Koordinaten-/Besitzschutz, private Warteschlangen, sequentielle lokale Flüge, Entfernen wartender Aufträge, Pause und Wiederverbindung; Hyperraumreise → vollständige Körpererkundung → weiterer lokaler Flug.
- Stationsprüfung: ungültiger Ort ohne Restobjekt, feste Position, Kollisionsablehnung, Abbruch und Neubau mit neuer ID sowie tatsächliche Forschungsproduktion.
- Neustartprüfung vergleicht lokale Flugbahnen und eine Warteschlange vor/nach abruptem Ende einer eigenen Datenbankinstanz.
- Verschärfte Nachprüfung: jeder Körper wurde im Untersuchungszustand beobachtet; ungültiger Folgeauftrag wird übersprungen, nächste Befehle laufen weiter; Stoppen hält einen teilweise ausgeführten Flug an seiner aktuellen Position an.
- Produktionsbuild und TypeScript-Prüfungen erfolgreich; die bestehende Vite-Warnung zu großen Chunks bleibt.
- Browserprüfung in eigener 400-System-Partie: Kartenklick setzt X/Z, unterschiedliche Höhen, zwei gespeicherte Flüge nach Neuladen bis zur korrekten Endposition; freie Forschungsstation bei 1400 / 250 / 0 gebaut, nach Serverneustart mit Stufe 1 und aktivem Ertrag sichtbar. Hyperraumreise und Erkundung lassen sich während des Flugs in derselben Liste verwalten. Die Kette nach Helion 282 wurde vollständig ausgeführt; danach zeigt das System „KARTIERT“, die Warteschlange ist leer und die Browserkonsole fehlerfrei. Testpartie abschließend pausiert.

Ein zusätzlicher Kontrolllauf wurde durch einen vollen Projekt-Datenträger abgebrochen. Nach Bereinigung abgeschlossener Testläufe und 15 alter Benchmark-Datenbanken einschließlich ihrer bereits abgemeldeten Replikadateien standen rund 2,7 GB bereit. Navigation und Neustartprüfung wurden danach erfolgreich wiederholt. Aktuelle Galaxien, Vorlagen und gespeicherte Messberichte blieben erhalten; der lokale Server läuft wieder.

Nächste Planstufe: Megastrukturen und Sternveränderungen.

Nachprüfung der Rechtsklick-Steuerung: nativer Integrationstest für atomaren Zielwechsel während eines Flugs, unveränderte Warteschlange nach ungültigem Zielwechsel sowie Bauabschluss von Sternenbasis und Bergbaustation erfolgreich.

Browserprüfung in eigener Testgalaxie F93004: Stern- und Asteroidenmenü mit tatsächlichem Bauauftrag und Rohstoffabzug; Rechtsklick auf 3D-Objekt, Beschriftung und Atlas; direkter Flug, Umschalt-Rechtsklick mit zwei Listeneinträgen sowie Ersetzen der Warteschlange; Escape schließt das Menü. Keine Konsolenfehler. 123 Regeltests, erweiterter nativer Navigationstest und Produktionsbuild erfolgreich.

Langsamere Systemflüge: Durchschnittstempo 80 statt 600, Mindestdauer 1,5 Tage; zeitliches Smoothstep-Easing gemeinsam für Simulation und Darstellung. Drei Navigation-Regeltests, nativer Navigationstest, Produktionsablauf mit Erkundung und KI-Kolonisierungsprüfung erfolgreich; Produktionsbuild erfolgreich. Testfristen berücksichtigen die längeren regulären Flugzeiten.

Trägheit und Bauanflug: 125 Regeltests erfolgreich; native Prüfungen für Navigation/Baunähe, Anlagenbau, persistente Systemobjekte, Terraforming und abrupten Serverneustart erfolgreich. Der alte direkte `mine`-Befehl ist gesperrt; die Galaxie öffnet die objektbezogene Bauverwaltung. Browserprüfung in Testgalaxie 7CF80D bestätigt Bauauftrag in der Schiffswarteschlange, Ankunft vor dem Baustart, fertige Asteroidenanlage mit Produktion, sichtbar gekrümmte Kurswechsel und Bremsstatus bei leerer Warteschlange. Keine Konsolenfehler.
