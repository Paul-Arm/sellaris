# Prüfung der Gefechtsübersicht · 5. September 2026

- TypeScript-Prüfung für Modul und Client sowie Produktionsbuild bestanden.
- 28 Spiel-/Domain-/Transporttests bestanden; 16 Backendtests bestanden. Neue Prüfungen umfassen die gedrosselte Übersicht bei vierfachem Spieltempo, effektiven HP-Schaden, Abonnementabbau, schnelle Ansichtswechsel, Reconnect ohne Details, Rückzug ohne künstlichen Schaden und dauerhaftes Endergebnis. Der Absturz-/Neustarttest vergleicht jetzt auch die gespeicherten Zusammenfassungen.
- Der isolierte [Netzwerktest](OVERVIEW.md) prüft 25 unabhängige Spieleridentitäten mit 75.000 Schiffen und einem Gefecht mit 3.000 Teilnehmern.
- Browserprüfung im separaten Testsektor `singularity-overview-ui`: Übersicht zeigt keine geladenen Schiffsdaten, Gefecht zeigt 3.000 Teilnehmer, Rückkehr leert die Details, Reconnect aus dem Gefecht startet wieder in der Übersicht. HP-Schaden und Zeitstand schreiten in der Sidebar weiter fort. Keine Browserwarnungen oder -fehler.
- Sidebar bei normaler Browserbreite und bei 390 px geprüft; kein horizontaler Überlauf. Temporären Viewport zurückgesetzt und Prüftab geschlossen. Der Testsektor ist anschließend pausiert.
- `singularity-foundation`, `singularity-lab` und `singularity-network` wurden additiv aktualisiert. Fehlende Gefechtsberichte wurden angelegt; ihre Spieluhren blieben beim Initialisieren unverändert. Frühere Schäden werden nicht erfunden, der Messbeginn ist sichtbar.

Die frühere 165-FPS-Beobachtung ist durch die Bildwiederholrate begrenzt. Diese Änderung bewertet den Netzwerkbedarf der Ansichten; aus den Browserprüfungen wird keine neue FPS-Leistungsgrenze abgeleitet.
