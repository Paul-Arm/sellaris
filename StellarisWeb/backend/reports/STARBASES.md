# Sternenbasen und Systembesitz

Stand: 8. September 2026. Neue Partien verwenden Weltformat 4. Alte Besitzregeln und die orbitale `starbase`-Anlage sind entfernt; es gibt keinen Migrationspfad.

## Spielablauf

Ein vollständig untersuchtes, unbeanspruchtes System kann einen Außenposten erhalten. Wächter müssen vorher besiegt werden. Bau kostet 100 Energie und 150 Mineralien und dauert 24 Spieltage. Der Bauplatz reserviert das System gegen konkurrierende Außenposten; erst der Abschluss überträgt den Besitz. Eine Kolonie entsteht dabei nicht. Außenposten benötigen kein Kolonieschiff und können auch Schwarze Löcher und Risse beanspruchen.

Kolonieschiffe besiedeln anschließend Welten im eigenen Gebiet. Sämtliche orbitalen Anlagen und Megastrukturen benötigen eigenen Systembesitz. Orbitalhabitate sind Produktionsanlagen und beanspruchen kein Territorium. Acht kontrollierte Systeme gewinnen die Partie, unabhängig von der Zahl besiedelter Welten.

| Stufe | Modulplätze | Basisverteidigung | Grundunterhalt / Monat |
|---|---:|---:|---:|
| Außenposten | 0 | 40 | 1 Energie |
| Sternenhafen | 2 | 100 | 3 Energie |
| Sternenfestung | 4 | 220 | 6 Energie |
| Zitadelle | 6 | 400 | 10 Energie |

Die Heimat startet mit einem Sternenhafen und einer Raumwerft. Weitere Basisstufen kosten 200/300, 400/600 und 800/1.000 Energie/Mineralien; ihre Bauzeiten betragen 40, 60 und 90 Tage.

Vier Module besitzen jeweils drei Stufen: Raumwerft ermöglicht Schiffsbau und beschleunigt neue Aufträge um 25 % je zusätzlicher Werftstufe; Geschützbatterien liefern je Stufe 80 Verteidigung, Versorgungsdocks 2 Hüllenreparatur pro Tag und Handelszentren 8 Energie pro Monat. Jedes Modul hat eigenen Unterhalt. Eine fertige Basis repariert grundsätzlich 1 Hülle pro Tag; Werftstufen ergänzen jeweils 1. Besetzte planetare Bastionen ergänzen die Systemwerte.

Je Basis läuft ein Ausbau oder Modulauftrag gleichzeitig, unabhängig von Kolonien und anderen Basen. Abbruch erstattet einmalig 50 % der gezahlten Kosten. Fertige Module lassen sich ohne Erstattung entfernen; eine Werft mit offenen Schiffsaufträgen ist dagegen geschützt. Die bestehende gemeinsame Schiffswarteschlange umfasst maximal fünf Aufträge. Sinkt die Systemverteidigung im Krieg auf null, gehen Basis, Besitz, Kolonien und Anlagen verloren.

## Umsetzung

- `shared/starbases.ts` enthält das gemeinsame Zustandsmodell, Kataloge, atomare Regeln, Fertigstellung und Wirtschaftszeilen. Lokaler Regelsimulator und natives Backend verwenden dieselben Bauregeln.
- `game_system` speichert Basiszustand und eine über Abbruch/Neubau hinweg fortlaufende Revision. `game_starbase`-Jobs verwenden dauerhafte Fristen und die gemeinsame Spieluhr. Ein verspäteter Befehl kann keinen späteren Neubau verändern.
- Private Intel-Views übertragen nur eigene Modul- und Projektdaten. Fremde Basisstufen werden nur in aktuell sichtbaren Systemen angezeigt. Die generierten TypeScript-Bindungen und der Spielclient sind angepasst.
- Wirtschaft, Verteidigung, Reparatur, Schiffsbau, Besiedlung, Produktionsanlagen, Siegwertung und KI berücksichtigen Außenposten ohne Kolonie. Die KI reserviert Expansion im normalen Ressourcenbudget und begrenzt frühe militärische Ausgaben.
- Die eigene Basisverwaltung öffnet sich aus Galaxiepanel und Systemansicht. Sie zeigt Stufen, Module, Kosten, Baufortschritt, Abbruch, Systemwerte, Energiebilanz und Werft. Das native Dialogelement hält den Tastaturfokus; Spiel-Hotkeys bleiben innerhalb der Verwaltung ausgesetzt.
- Systemmodelle verwenden die tatsächliche Basisstufe und Werftmodule. Der alte Schiffsbau im Kolonie-/Systempanel und die alte Anlagenvariante der Sternenbasis sind entfernt.

## Prüfung

- 165 gemeinsame Regeltests bestanden, einschließlich neuer Tests für Erkundung, Baureservierung, Besitznahme, Kosten, Abbruch/Neubau, Revisionen, fremde Befehle, Modulplätze, Effekte, Werftpflicht und Systemverlust.
- Gezielt geprüfte native Bereiche: Sternenbasen mit zwei Clients, Kolonien, Nebenwelten, Anlagen, Navigation, Dekompressor, Wirtschaft, KI, Spielgründung, Kolonisierung, Kampf, Ereignisse und Krisen. Angepasste alte Erwartungen berücksichtigen Basisunterhalt und Basisverteidigung; alle zunächst fehlgeschlagenen Prüfungen wurden anschließend erfolgreich wiederholt.
- Erzwungener Neustart eines isolierten Datenbankservers: Identität, Module, Revisionen, bezahlter Basisbau und Frist werden unverändert wiederhergestellt.
- TypeScript-Prüfung für Backend und Frontend, generierte Bindungen und Produktionsbuild erfolgreich.
- Browserprüfung einer neuen Partie: Verwaltung öffnet, Modulbau wird serverseitig gespeichert, Pausenstatus und Fortschritt erscheinen, Abbruch aktualisiert den Zustand, Werft zeigt die verfügbaren Schiffe und tatsächlichen Bauzeiten. Ein dabei sichtbarer Fehler eines abgehängten Galaxiekarten-Rendercallbacks wurde behoben.

Die Tests prüfen gezielt die betroffenen Bereiche; dies ist keine Behauptung eines vollständigen Durchlaufs sämtlicher unabhängiger Backend-Lasttests. Neue Galaxien werden aus dem aktuellen Modul erstellt. Reichs- und Speziesvorlagen wurden nicht verändert oder gelöscht.


## Visuelle Slots (Folgeausbau)

Die Verwaltung verwendet einen Stationsplan mit sechs festen Andockpositionen. Nur ein gewählter freier Slot öffnet die Modulauswahl. Belegte Plätze zeigen Symbol, Stufe und Verwaltung; Bauaufträge erscheinen direkt im betroffenen Platz. Das gemeinsame `BuildSlot`-/`SlotPicker`-Muster wird auch in Koloniesektoren, Schiffsbau und orbitalen Anlagen verwendet. Escape schließt nur die Auswahl und gibt den Fokus an den Platz zurück.

Module und planetare Distrikte speichern ihren `slot` unabhängig von ihrer Arrayposition. Bauaufträge und Befehle nennen den konkreten Platz; Regeln prüfen Grenzen, Belegung und Revision. Abriss erhält die übrigen Positionen. Lokale Simulation, KI, native JSON-Speicherung, Wiederverbindung und Oberflächen verwenden das neue Modell ohne Adapter. Weltformat 4 und Kolonieschema 3 erfordern neue Partien.

Nachweise für diesen Folgeausbau: 167 Regeltests bestanden, darunter beliebige Slotreihenfolge, JSON-Rundlauf, Abbruch, Abriss, Wiederbelegung und atomare Ablehnung ungültiger Plätze. Native Tests für Hauptkolonien, Nebenplaneten, Sternenbasen (Werft zuerst in Slot 2) sowie erzwungenen Datenbankneustart bestanden. Frontend-Produktionsbuild und Backendbuild bestanden. Browser: Stationsplan, Modul einsetzen/abbrechen, Escape/Fokusrückgabe, Werftauswahl, Kolonieslot 3 bauen/abbrechen und orbitaler Anlagenplatz geprüft. Neue pausierte Demopartie: `8BB3B1`; Vorlagen wurden nicht verändert.
