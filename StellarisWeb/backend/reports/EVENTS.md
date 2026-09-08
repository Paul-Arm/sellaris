# Ereignisse und Spezialprojekte

Stand: 09.09.2026. Das bisherige separate Story-Modell ist durch einen gemeinsamen Ereignis- und Projektkern ersetzt. Natürlicher Sternkollaps ist entfernt; kontrollierter Sternkollaps und Sternenstürme bleiben erhalten. Weltformat 6 setzt neue Partien voraus, ohne Migration alter Spielstände. Reichs- und Speziesvorlagen bleiben unabhängig davon erhalten.

## Umfang

- 28 Pool-Einträge mit wiederverwendbaren Definitionen, Bedingungen, Chancen, Gewichten, Wiederholungsregeln und Abklingzeiten.
- Trigger für Gründung, Erkundung, Kolonisierung, Systembesitz, Forschung, Spezies-/Reichsänderungen, Zeit, Krisen und Sternenstürme.
- Private persistente Vorgänge, Folgeprojekte, Ressourcenfolgen und Reichs-/Speziesmodifikatoren. Das Evolutionsprojekt verbindet mehrere Arbeitsphasen mit Entscheidungen und einer neuen Speziesgeneration.
- Täglich positiver oder negativer Fortschritt, feste Phasen, Startkosten, individuelle Pause und optionale Entscheidungsfristen mit kostenlosem Standardpfad.
- Lagezentrum mit Suche, Filtern und Archiv. Eigene Detailseiten mit Verlauf, Dialogen, Bildflächen, Fundortkarte, Entscheidungen und Projektprotokoll. Ankündigungen für neue Funde und Phasen; gespeicherter Lesestatus.

`game_situation` speichert Instanzen und indizierte nächste Arbeitstermine; `game_event_director` speichert Auswahlhistorie und Flags. `my_situations` liefert ausschließlich eigene Vorgänge und zulässige Optionen. Der Gateway projiziert diese Daten direkt in das aktuelle Spielmodell. Der frühere Produktionspfad über `game_story`, `my_game_stories` und die Story-Oberfläche ist entfernt. Die allgemeine Labor-Entscheidungstabelle bleibt Bestandteil der unabhängigen Backend-Kernproben.

## Prüfung

- `npm test`: 120 Kern-/Regeltests bestanden, darunter deterministische Auswahl, Bedingungen, Wiederholungsschutz, begrenzte offene Vorgänge, schwankender Fortschritt, Phasen, Pause, Fristen und einmalige Effekte.
- Native Ereignisprüfung: private Ansichten, Besitzschutz, unzureichende Ressourcen, tatsächliche Startkosten, doppelte Befehle, idempotente Lesebestätigungen, unverdeckte neue Meldungen, Pause, Neuverbindung, Entscheidung und Abschluss bestanden.
- Nativer Absturztest: gespeicherte Vorgänge und Krisenzustand werden nach abruptem Serverende wiederhergestellt.
- Backend- und Frontend-Build erfolgreich. Vite weist weiterhin auf größere Bundles hin.

Diese erfolgreichen Prüfungen liefen vor den gleichzeitig begonnenen Änderungen der Task „Compute vielseitig einsetzen“. Ein anschließender Gesamtbuild wurde durch dort noch fehlende `ComputePlayer`-/`optimizeProduction`-Imports in `shared/planetaryEconomy.ts` blockiert. Nach Abschluss dieser parallelen Arbeit muss der kombinierte Stand erneut gebaut werden.

Die Tests wurden auf zentrale Regeln, Berechtigungen, Transaktionen, Transport und Speicherung konzentriert; einzelne Modelle, Inhaltskataloge und reine Darstellung erhalten keine separaten Suiten. Historische Prüfberichte beschreiben teilweise inzwischen entfernte Tests.

## Browserprüfung

In einem frisch gegründeten Sektor mit 400 Systemen geprüft: Fund-Popup, Projektstart, Fortschritt bis zur ersten Entscheidung, Auswahl, Folgephase mit Bild, individuelle Pause, Übersicht, Suche und Spezialprojektfilter. Weitere Ereignis- und Evolutionsmeldungen erscheinen in der Ankündigungswarteschlange und lassen sich bestätigen. Die breite Übersicht und Detailansicht wurden bei 1280 × 720 visuell kontrolliert. Der Testsektor bleibt pausiert.

## Inhalte erweitern

Siehe [Autorenleitfaden](../../shared/events/README.md). Der Pool ist eine Grundlage für weitere Geschichten; zusätzliche Weltveränderungen benötigen neue zentrale Effekttypen. Die KI verwendet dieselben bezahlbaren Projekt- und Entscheidungsbefehle. Differenzierte narrative KI-Strategien und weitere globale Krisen sind weitere Ausbauschritte.
