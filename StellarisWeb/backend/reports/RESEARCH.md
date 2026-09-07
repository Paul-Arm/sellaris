# Forschungsnetz: Daten und Compute

Stand: 8. September 2026. Ersetzt das vorherige Ressourcen- und Forschungsmodell vollständig; Weltformat 2. Bestehende Entwicklungswelten werden gelöscht, nicht migriert.

## Bedienung

Forschung oder Compute im HUD öffnet die Übersicht der vier Forschungsgebiete. Sie zählt nur bekannte Erkenntnisse und aktuell erforschbare Projekte, keine verborgenen Technologien. Ein Gebiet öffnet seine Forschungsfront. Erforschtes Wissen ist zunächst eingeklappt und lässt sich über den Wissensfilter wieder einblenden. Der Programmfilter zeigt laufende und geparkte Projekte. Die Suche umfasst ausschließlich aufgedeckte Namen und Beschreibungen und begrenzt die Ergebnisliste auf zwölf Treffer.

Anfangs sind nur die vier Grundlagen sichtbar. Eine weitere Technologie wird erst aufgedeckt, wenn alle Voraussetzungen erforscht sind. Derselbe Schutz gilt serverseitig: Ein erratener Technologiebezeichner erlaubt keine Planung verborgener Ziele. Entdeckungen werden aus dem abgeschlossenen Wissen abgeleitet und benötigen keine zusätzliche Speicherung.

Die Übersicht bündelt Gebiete; beim Hineinzoomen werden einzelne Knoten gezeigt. Beim Herauszoomen unter die lesbare Mindestgröße wechselt die Ansicht zur Gebietsübersicht. Automatisch angeordnete Knoten ersetzen manuelle Koordinaten. Pro Gebiet werden höchstens drei Spalten gebildet; weitere Knoten wachsen nach unten. Nur Knoten im sichtbaren Bereich einschließlich eines Vorlaufs werden in den SVG-Baum aufgenommen. Verbindungen sind auf die direkte Umgebung der Auswahl beschränkt. Voraussetzungen anderer Gebiete lassen sich im Inspektor gezielt öffnen.

Das Forschungsprogramm kennt keine drei Auswahlplätze und keine Zufallsauswahl. Bereite Projekte arbeiten parallel. Prioritäten 1–5 verteilen die verfügbare Rechenleistung proportional. Parken setzt die Priorität auf 0 und erhält Fortschritt und bezahlte Daten. Fehlende Daten werden als Wartezustand angezeigt.

## Wirtschaft

- Daten sind ein gespeicherter Rohstoff, auch für bisherige Forschungswährungskosten und Belohnungen. Der Projektpreis wird genau einmal beim tatsächlichen Start abgebucht. Wissensarchive und Semantische Kompression reduzieren künftige Preise um jeweils 15 %.
- Compute ist laufende Kapazität pro Spieltag. Basis: 4; Technologien und besetzte Rechenzentren erhöhen sie. Reichsmodifikatoren wirken auf die Kapazität.
- Ein Rechenzentrum kostet 100 Energie und 140 Mineralien, benötigt 24 Tage und hat zwei Arbeitsplätze pro Stufe. Jeder besetzte Arbeitsplatz liefert bei vollständiger Versorgung 2 Compute/Tag; Unterversorgung und deaktivierte Distrikte werden berücksichtigt. Haupt- und Nebenwelten zählen.
- Standardmäßig sind 25 % für Datensynthese reserviert; der Regler erlaubt 0–100 %. Nicht von Forschungsprojekten benötigtes Compute geht zusätzlich in die Synthese. Ohne Daten kann Forschung dadurch wieder anlaufen.
- Synthese liefert zunächst 0,25 Daten je Compute, mit Simulationsmodellen 0,5 und Prädiktiver Wissenschaft 0,75. 100 % Synthese stoppt Forschungsarbeit. Abhängige Projekte starten nach Abschluss ihrer Voraussetzungen beim nächsten Fortschrittsschritt.

## Speicherung und Regeln

`shared/research.ts` enthält Katalog, Abhängigkeiten, Kosten, Prioritäten und Fortschritt. Native Forschungsprogramme liegen in der privaten Tabelle `game_research`, getrennt von Bauaufträgen. Die Mitgliederansicht `my_research` liefert ausschließlich das eigene Programm und die autoritativ berechnete Kapazität. Strategische Spielticks berechnen Fortschritt und Synthese. Befehle rechnen zunächst den bisherigen Zeitraum ab, bevor sie die Verteilung ändern.

Pause, Wiederverbindung, doppelte Aufträge, unzureichende Daten und ungültige Prioritäten werden serverseitig behandelt. Vorhandene Wirkungen auf Flotten, Kolonieproduktion, Terraforming und Megastrukturen bleiben an die entsprechenden neuen Technologieknoten gebunden. Die KI verwendet dieselben Befehle und Abhängigkeiten.

Gelöschte registrierte Galaxien werden über eine Verfügbarkeitsabfrage erkannt. Der Client verwirft dann die nicht mehr gültige Spielsitzung und ermöglicht eine neue Gründung. Es gibt keinen Ersatzpfad für alte Tabellen oder Forschungsmodelle.

## Prüfung

- Acht gezielte Regeltests: topologische Planung, einmalige Zahlung, gewichtete Verteilung, Parken, Synthese bei leerem Datenkonto, Technologieeffekte, ungültige Eingaben und besetzte Rechenzentren.
- Nativer Forschungsablauf: getrennte Mitgliederansichten, vollständiger Technologiepfad, exakte Synthesebuchung neben normaler Produktion, Prioritäten, Pause, Wiederverbindung, einmalige Freischaltungen und Bau/Deaktivierung eines Rechenzentrums.
- Native Regressionen: Gründung mit 1.000 Systemen, Gateway und Neustart, Diplomatie, Handel, Ereignisse, Krise, Terraforming und Dyson-/Sternkollaps-Projekte.
- Browser: gelöschte Sitzung verlassen, neue Galaxie gründen, Forschungslandkarte laden, mehrstufigen Weg aufnehmen, Projekt parken/fortsetzen, Syntheseregler per Tastatur und Kartenübersicht bedienen.
- TypeScript-Prüfung, native Modulkompilierung und Produktionsbuild erfolgreich. Bestehende Vite-Hinweise zu großen Renderer-/Anwendungsbundles bleiben bestehen.

## Erweiterung für große Bäume

Prüfung: 151 Regeltests erfolgreich, einschließlich eines synthetischen Katalogs mit 500 Technologien (stabile Anordnung, keine überlappenden Karten, begrenzte Spaltenbreite, weniger als 40 montierte Knoten im geprüften Ausschnitt). Verborgene Zweige verändern weder Positionen noch Abmessungen des aufgedeckten Netzes. Nativer Forschungsablauf erneut erfolgreich; versteckte Befehle werden ohne Kostenbuchung abgewiesen und neue Ziele nach ihren Voraussetzungen akzeptiert. Produktionsbuild und Browserkontrolle bestanden.

Der Spielkatalog enthält weiterhin 15 ausgearbeitete Technologien. Der Testkatalog dient ausschließlich der Prüfung der Darstellung; er ergänzt keine Spielinhalte. Es wurde keine neue Speicherstruktur eingeführt. Die laufende lokale Partie wurde mit den neuen Regeln aktualisiert.
