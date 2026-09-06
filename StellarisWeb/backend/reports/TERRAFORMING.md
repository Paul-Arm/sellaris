# Terraforming

Stand: 6. September 2026. Zweite Etappe der veränderbaren Sternsysteme.

## Spielregeln

„Klimagestaltung“ kostet 250 Forschung und benötigt regulär 60 Spieltage vor Forschungsmodifikatoren. Danach können eigene, untersuchte Planeten zwischen den neun Klimaklassen wechseln. Monde, Gasriesen und Sterne sind keine Terraforming-Ziele.

| Wechsel | Energie | Mineralien | Forschung | Spieltage |
| --- | ---: | ---: | ---: | ---: |
| Innerhalb einer Klimagruppe | 400 | 250 | 100 | 80 |
| Zwischen Klimagruppen | 600 | 375 | 100 | 120 |

Pro Planet läuft höchstens ein Projekt. Unterschiedliche Planeten und der Anlagenbau arbeiten parallel. Kosten werden beim Start atomar bezahlt. Ein freiwilliger Abbruch erstattet einmalig 50 % aller Projektkosten. Bei Systemverlust endet das Projekt ohne Erstattung. Ein Planet mit laufendem Projekt kann nicht über die interne Entfernung entfernt werden.

Pause hält die Fristen an. Wiederverbindung und Datenbankneustart setzen dasselbe Projekt fort. Der Abschluss verändert Klima, Farbe und Beschreibung desselben Objekts; Name, Objekt-ID, Bahn, Anlagen und Bevölkerung bleiben bestehen. Auf Hauptwelten beeinflusst das Klima die Bewohnbarkeit, das Wachstum und die tatsächlichen Kolonieerträge. Alte Produktionszyklen und das bis dahin angefallene Wachstum werden vor dem Klimawechsel abgerechnet.

Nebenwelten besitzen weiterhin keine eigene Bevölkerung. Dort verändert Terraforming Klima und Darstellung; Außenanlagen behalten ihre bestehenden Erträge. Dies wird im Browser ausdrücklich erläutert. KI-gesteuertes Terraforming ist noch nicht implementiert.

## Umsetzung

- `shared/terraforming.ts`: Klimafarben, Kosten und Dauer.
- `game_terraform`: private Projektzeilen mit Fristenindex, Besitzer und tatsächlich gezahlten Kosten.
- `start_terraforming` / `cancel_terraforming`: serverseitige Besitz-, Forschungs-, Erkundungs-, Revisions- und Ressourcenprüfung.
- `my_terraform_projects`: ausschließlich eigene Projekte; Objektänderungen erreichen berechtigte Zuschauer über bestehende Systemabonnements.
- `TerraformingPanel`: Zielklima, Bewohnbarkeit, Ertragsvorschau auf Hauptwelten, Kosten, Fortschritt und Abbruch.
- `gameStrategic`: Abschluss fälliger Projekte; `updateColony`: sofortige Bereinigung bei Systemverlust.

## Neue Galaxien statt Kompatibilität

Der Nutzer hat das Löschen alter Galaxien ausdrücklich erlaubt und Abwärtskompatibilität ausgeschlossen. Diese Vorgabe steht in `AGENTS.md` und `PLAN.md`. Die eingefrorenen Generatoren und der Körperimport-Reducer sind entfernt; neue Galaxien verwenden `shared/systemGeneration.ts` mit dem aktuellen Sternkatalog. Der Objektkatalog benötigt keine Importversion mehr.

Die zehn zuvor registrierten lokalen Galaxien wurden mit `backend:reset-games` gelöscht. Das Werkzeug validiert Registry und Datenbanknamen, verwendet die native Löschfunktion und entfernt erfolgreiche Löschungen einzeln aus der Registry. Vorlagen und Laborwelten bleiben erhalten. Für neue Partien provisioniert der Gateway das aktuelle Modul.

## Prüfungen

- 121 Regeltests bestanden.
- 30 Backendtests bestanden, einschließlich Forschungs-/Besitzschutz, unzureichender Rohstoffe, veralteter Revisionen, privater Projektsicht, parallelem Bau, Pause, einmaliger Erstattung, erfolgreichem Klimawechsel, realen Produktionsraten und Systemverlust.
- Der native Neustarttest vergleicht laufende Projekte und Körperdaten vor und nach einem abrupten Datenbankabsturz.
- TypeScript-Prüfung, nativer Modulbuild und Browser-Produktionsbuild bestanden. Vite weist weiterhin auf große JavaScript-Chunks hin.
- Browserprüfung in einer neuen 400-System-Galaxie: Klimagestaltung regulär erforscht, Hauptwelt von Kontinental- zu Ozeanklima umgewandelt, pausierten Fortschritt geprüft, einmal abgebrochen und die Erstattung von 200 Energie / 125 Mineralien / 50 Forschung in der Ressourcenleiste bestätigt. Danach erneut gestartet und erfolgreich abgeschlossen. Neues Klima, Farbe, Bewohnbarkeit und Ertragsvorschau sind sichtbar; die Browserkonsole meldet keine Fehler. Testpartie abschließend pausiert.

Die folgende Etappe mit freien Stationen, Systemflügen und Erkundungsrouten ist inzwischen umgesetzt: [Systemnavigation](SYSTEM-NAVIGATION.md). Mehrere bewohnte Planeten je System, Megastrukturen und Sternereignisse folgen separat.
