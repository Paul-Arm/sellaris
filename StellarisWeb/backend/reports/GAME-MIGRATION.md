# Normales Spiel auf SpacetimeDB · 5. September 2026

Der Spieleinstieg auf `/` verwendet SpacetimeDB 2.10.0 als autoritative Simulation. Neue Partien starten mit 1.000 Systemen und 25 Plätzen. Das Labor auf `/lab` bleibt eine getrennte Lastumgebung. Seine früheren Messwerte sind keine Messung der gesamten jetzt migrierten Spiel-KI und Oberfläche.

## Verantwortlichkeiten

- Gateway: privater Bibliotheksschlüssel, Vorlagenprüfung, Raumcode, einmaliges Sitzplatz-Ticket, HTTP-Dateien und Weiterleitung des nativen Transports. Kein periodischer Weltzustandsversand für native Partien.
- Native Galaxie: eigene dauerhafte Tabellen für Reichsinstanzen, Ressourcen, Kolonien/Pop-Kohorten, Jobs, Flotten/Schiffe, Gefechte, Sitzplätze, Verbindungen und Ereignisse.
- Browser: berechtigte initiale Abonnements, danach Änderungen; lokale Projektion für React, Reise-/Arbeitsfortschritt zwischen Aktualisierungen. Gzip und geordnete Dekompression bleiben aktiv.
- Details: Einzelschiffe nur in der geöffneten Flottenverwaltung bzw. passenden Systemansicht. Individuelle Gefechtspositionen nur für die geöffnete berechtigte Schlacht. Zurück zur Galaxie bedeutet bestätigtes Abbestellen.

## Übernahme bestehender Sektoren

1. Der Gateway prüft den bisherigen Sitzungsschlüssel gegen `data/sectors.json`.
2. Er friert die genaue Importquelle unter `data/native-imports/CODE.json` ein und hält die Legacy-Simulation dieses Raums an.
3. Der Datenbankname wird aus Code und Quellhash abgeleitet. Ein Wiederholungsversuch verwendet dieselbe Quelle und dieselbe Datenbank.
4. `initializeGame` importiert in einer Transaktion. Ein bereits bestätigter Import wird mit demselben Schlüssel nicht wiederholt; ein anderer Schlüssel darf die Welt nicht ersetzen.
5. Die neue Identität wird mittels eines einmaligen, zeitlich begrenzten Tickets an den bestehenden Spieler gebunden. Der Browser entfernt die alte Tab-Sitzung erst nach bestätigtem Erfolg.

Erhalten bleiben Raumcode, Spieler-IDs, eigene Reichs-/Speziesinstanzen und Gründungssnapshots, Ressourcen, Technologien, Untersuchungen, Kolonien, ursprüngliche Karte, Flottennamen, Hülle, Reiseprogress und verbleibende Auftragsarbeit. Neue Korvetten verwenden das native Schild-/Panzerungsmodell. Quellspeicher und alte Wiederherstellungsschlüssel bleiben erhalten. Ein Import vergrößert die ursprüngliche Karte nicht und vergibt keine erneuten Startboni.

## Geprüfte Abläufe

`npm test`: **49/49 bestanden**. `npm run backend:test`: **22/22 bestanden**. TypeScript-Prüfung, nativer Modulbuild und Produktionsbuild sind ebenfalls erfolgreich. Die Erweiterungen prüfen:

- 1.000 Systeme; 25 unterschiedliche Heimatsysteme; Ablehnung eines 26. Imperiums; laufende Simulation mit 23 KI-Imperien und zwei Spieleridentitäten.
- Einmalige Gründung/Ticketnutzung, private Reichsinstanzen und fremde Kolonien/Flotten, Besitzschutz und Hostrechte; der Laboreinstieg umgeht den normalen Sitzplatzschutz nicht.
- Import von Ressourcen, Reiseankern, Restforschung, Werftwarteschlange und Kolonieausbau; idempotente Wiederholung und Ablehnung eines anderen Importschlüssels.
- Abschluss von Untersuchung und Kolonisierung, Verbrauch des Kolonieschiffs, echte Produktion, Forschung und Bau. Korvetten verstärken den vorhandenen Verband.
- Atomare Aufteilung und Zusammenführung mit eindeutigen Schiffsmitgliedschaften; Ablehnung fremder und doppelter IDs.
- Regierungsreform, Revisionen, Speziesabstammung und Pop-Transfer im nativen Backend. Gründungssnapshot und Bevölkerungsmenge bleiben erhalten.
- Selbständige KI-Erkundung, Kolonisierung, Forschung und Flottenverstärkung ohne zusätzliche Ressourcengeschenke.
- Automatischer Kampfeintritt, private Übersicht, effektiver HP-Schaden, explizite Detailabonnements, Wiederbeitritt mitten ins Gefecht und atomarer Rückzug mit erhaltenem Abschlussbericht.
- Zwei native Identitäten durch den tatsächlichen Gateway, alter Sitzungsschlüssel, privates Bibliotheks-Template und neue Raumregistrierung; Wiederverbindung nach Gateway-Neustart ohne erneute Gründung.
- Erzwungener Neustart einer isolierten SpacetimeDB-Instanz: pausierte Reichs-, Forschungs-, Reise- und Gefechtszustände bleiben erhalten. Danach funktioniert die automatische Pause beim letzten Disconnect; keine alte Verbindung hält die Partie aktiv.
- Abgeschlossene alte Partien sind weiter lesbar, können aber weder fortgesetzt noch um neue Spieler erweitert werden.

Die Tests starten und beenden ausschließlich eigene Testprozesse. Alte Benutzersektoren und die vorhandenen Labordatenbanken werden nicht zurückgesetzt.

## Browserprüfung

Normale private Reichsvorlage → neue native Galaxie → zweiter Browserbeitritt → Flottenreise → Untersuchung → Forschung → Kolonisierung → zwei eigene Kolonien. Neuladen erhält Spieler, Ressourcen und Fortschritt. Systemsuche zentriert die gefundene Kolonie; die Flottenverwaltung lädt die ausgewählten Schiffsdaten. Zwei Spielerflotten wurden über die normale Oberfläche nach Alpha Centauri geschickt; der dauerhafte Abschlussbericht zeigte Sieger, einen Verlust und 71/80 verursachte HP. Die Oberfläche zeigte dabei keine Konsolenfehler.

Visuell bei 1.280 × 720 und in einer breiten Desktopansicht geprüft. Nach der Layoutkorrektur misst die Systemsuche 40 px Höhe; kein horizontaler Dokumentüberlauf. Der Pausenhinweis bleibt unterhalb der Suche sichtbar. Eine eigenständige mobile Spieloptimierung ist kein Ergebnis dieser Prüfung.

Die Hauptinstanz auf Port 3001 wurde ebenfalls geprüft: **C5A092** verwendet jetzt das native Backend mit seinen ursprünglichen 30 Systemen, zwei Kolonien und vier Flotten. Das zuletzt gebaute Modul wurde ohne Datenrücksetzung veröffentlicht; die Partie wurde für das Update pausiert und danach wieder fortgesetzt. Der Browser nahm dieselbe Sitzung nach Neuladen wieder auf. **F0535F** ist weiterhin in `data/sectors.json` vorhanden. Die beiden Browser-Spieler der Prüfung verwendeten einen getrennten Testsektor und ein eigenes Datenverzeichnis.

## Verbleibender Ausbau

Gefechte haben aktuell zwei Seiten und das vereinfachte Waffen-/Manövermodell des geprüften Fundaments. Dritte Parteien und Verstärkungen warten auf den Abschluss des bestehenden Gefechts. Alle anderen Imperien gelten noch als feindlich; Diplomatie, Handel, Ereignisentscheidungen und Krisenregeln sind die nächsten Spielsysteme. Ihre Labortabellen sind Erweiterungspunkte und noch keine fertigen Spielfunktionen.

Ein ungeplanter längerer Ausfall ohne vorherige Pause und Geräte mit stark unterschiedlicher Wanduhr brauchen weitere Betriebsregeln. Der geprüfte Neustartfall hält die Uhr unmittelbar vor dem Abbruch an, um exakte Vergleiche zu ermöglichen. Normale leere Partien pausieren automatisch. Die strategische Shader-/Canvas-Karte hat weiterhin ein 30-FPS-Limit; die früher genannten 165 FPS bezeichneten die Displaygrenze bei der Darstellungsprobe. Radiance Cascades und eine vollständige Containerbereitstellung gehören nicht zum abgeschlossenen Migrationsumfang.
