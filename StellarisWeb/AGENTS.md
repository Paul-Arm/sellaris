# Projektvorgaben

- Immer ALLES UMZIEHEN: Bei jedem Rework sämtliche Erzeuger, Verbraucher, Speicher- und Transportmodelle, Oberflächen, Simulatoren und Tests vollständig auf das neue System umstellen. Die alte Implementierung und ihre Aufrufer entfernen. Keine parallelen Altpfade, Adapter oder Kompatibilitätsschichten behalten. Diese Vorgabe gilt dauerhaft für alle künftigen Änderungen.

- Der Nutzer erlaubt ausdrücklich das Löschen alter Galaxien und Spielstände für die Weiterentwicklung.
- Keine Abwärtskompatibilität als Entwicklungsanforderung: keine Migrationspfade, eingefrorenen Generatoren oder Fallbacks nur für alte Galaxien ergänzen. Bei inkompatiblen Änderungen neue Partien verwenden.
- Für den Forschungs-Rework ausdrücklich erneut bestätigt: alte Ressourcen-/Forschungsmodelle direkt ersetzen; bestehende Partien dürfen gelöscht werden. Keine Kompatibilitätsschicht für alte Forschung oder alte Ressourcen hinzufügen.
- Löschungen auf die Spiel-/Testdaten dieses Projekts begrenzen. Reichs- und Speziesvorlagen sowie Quellcode sind von dieser Freigabe nicht umfasst.

- Bau- und Ausrüstungsoberflächen grundsätzlich visuell über belegbare Slots gestalten: zuerst den Platz wählen, dann den Inhalt einsetzen. Freie, belegte, im Bau befindliche und gesperrte Plätze direkt zeigen; keine dauerhaft angezeigten Bauoptionslisten.

- Tests auf zentrale Spielregeln, Zustandstransitionen, Persistenz, Transport und Berechtigungen konzentrieren. Keine eigenen Testsuiten pro Ereignis, Inhaltseintrag oder rein visuellem Detail.
