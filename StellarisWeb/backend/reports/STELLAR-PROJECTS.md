# Kontrollierter Sternkollaps

Stand: 7. September 2026. Erste spielbare Sternveränderung auf persistenten Systemobjekten.

Das freiwillige Endspielprojekt benötigt einen eigenen untersuchten Hauptreihenstern oder Riesen, Megakonstruktion und einen vollständigen eigenen Dyson-Schwarm. Einstieg über Rechtsklick am Stern → „Dyson-Anlage / Sternprojekt verwalten“. Die Detailansicht zeigt Folgen, Voraussetzungen, Kosten, Fortschritt und Abbruch.

- Kosten: 1.200 Energie, 800 Mineralien und 400 Forschung bei Projektstart.
- Dauer: 120 Spieltage. Pause stoppt die Uhr. Das Projekt läuft unabhängig von der normalen Forschung.
- Abbruch vor Abschluss erstattet einmalig 50 % aller Projektkosten. Bei verlorenem oder verändertem Ziel endet es ohne Erstattung und ohne Kollaps.
- Abschluss: 2.500 Forschung, derselbe Stern wird zum Neutronenstern. Ein erneuter Kollaps ist dort nicht möglich.

## Folgen im System

Sternobjekt, System-ID, Besitz, Hyperlanes und vorhandene Bahnen bleiben bestehen. Sternklasse und Farbe werden sowohl im gespeicherten Körper als auch im Galaxieatlas geändert. Der Renderer übernimmt Größe, Licht und Gravitation aus dem neuen Neutronensternprofil.

Die auslösende Dyson-Anlage erhält den Lebenszyklus „destroyed“; ihre ID bleibt historisch reserviert. Ihre Anlagenzeile und ein Sonnenkollektor am kollabierten Stern werden gelöscht, einschließlich laufender Solar-Ausbaustufen. Sternenbasen und andere Anlagen bleiben erhalten. Neue Sonnenkollektoren oder Dyson-Anlagen sind am Neutronenstern unzulässig. Noch wartende Bauaufträge laufen durch die bestehende Zielprüfung und werden bei ungültigem Ziel übersprungen.

Alle aktiven Planeten mit Klimaklasse werden arktisch. Hauptkolonie und andere betroffene Körper behalten Namen, IDs, Umlaufbahnen und Infrastruktur; Pops werden durch dieses Ereignis nicht gelöscht. Laufendes Terraforming wird beendet, ohne dessen Kosten zu erstatten. Vor dem Wechsel werden alte Erträge und Wachstum abgerechnet, danach die Kolonieraten neu bestimmt. Die gewöhnlichen Terraforming-Regeln stehen anschließend wieder zur Verfügung. Dies ist eine vereinfachte Spielregel für einen technisch ausgelösten Kollaps, kein Modell natürlicher Sternentwicklung.

## Speicherung und Prüfung

Das Projekt verwendet dauerhafte private `job`-Zeilen mit Ziel-ID und Sternrevision. Der zentrale Spieljob-Abschluss führt alle Folgen in derselben Transaktion aus; keine neue Tabelle, Migration oder Kompatibilitätsschicht wurde ergänzt.

- Frontend- und Backend-TypeScript sowie beide Builds erfolgreich.
- Vorhandene lokale Tests und ergänzter Test für Sternprofil, unveränderte Bahnen/Identität, Vereisung und zulässige Anlagen erfolgreich.
- Echter Datenbanktest in `backend/tests/megastructures.test.ts`: gesamte Dyson-Kette, Fremdzugriff, veraltete Revision, doppelter Auftrag, Pause, einmalige Erstattung, Wiederverbindung während des Projekts und danach, Kollaps während Terraforming, Klima-/Atlasänderung, erhaltene Sektoren und Hyperlanes, Anlagenverlust und Forschungsbuchung.
- Browser: Rechtsklick-Zugang, lesbare Kosten/Folgen und gesperrter Start ohne Forschung in einer getrennten Testpartie geprüft, keine Warnungen oder Fehler. Der vollständige Kollaps wurde im nativen Integrationstest geprüft.

Weitere Sternereignisse, vollständiges Entfernen eines Sterns, Kollateralschäden an Schiffen und eine KI-Strategie für solche Projekte sind noch offen. Mehrere eigene Kolonien pro System bleiben der nächste Architekturausbau.
