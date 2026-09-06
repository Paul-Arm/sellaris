# Systemansicht und bebaubare Himmelskörper

Stand und Prüfung: 05.09.2026.

## Umsetzung

Die normale Systemansicht verwendet jetzt eine eigene Three.js-Szene. Sie zeigt einen Stern beziehungsweise eine Singularität, Planeten, Monde mit Unterumlaufbahnen, Gasriesen, einen Asteroidengürtel und orbitale Ruinen. Körper lassen sich im Bild und über die Objektleiste auswählen. Zoom, Schwenken und Zentrieren der aktuellen Auswahl sind verfügbar. Die bestehende Hauptwelt führt direkt zur Kolonieverwaltung.

Forschungsschiffe, Kolonieschiffe und Korvetten haben unterschiedliche geometrische Modelle. Sichtbare Flotten werden aus den berechtigten strategischen Reihen als lokale Formationen dargestellt. Große Verbände werden in der Entfernung zusammengefasst, ohne ihre tatsächlichen Schiffszahlen zu verändern. Der Renderer verteilt sein Instanzbudget über alle sichtbaren Flotten. Körperbahnen und die lokale Präsentation verwenden die gemeinsame Spielzeit und halten bei Pause an.

Ein laufendes Gefecht hat einen eigenen Zugang aus der Systemansicht. Nur die geöffnete taktische Ansicht fordert individuelle Kampfpositionen an. Der separate Dialog zur Verbandsverwaltung fordert die jeweiligen Schiffsdaten an. Die normalen System- und Galaxieansichten benötigen dafür keine einzelnen Schiffsbewegungen.

## Tatsächlicher Anlagenbau

| Körper | Verfügbare Anlagen |
|---|---|
| Stern | Sonnenkollektor |
| Planet und Mond | Außenposten, Förderanlage, Forschungsstation |
| Gasriese | Atmosphärenkollektor |
| Asteroidenfeld | Förderanlage |
| Ruine | Forschungsstation oder Förderanlage |
| Schwarzes Loch und Riss | Forschungsstation auf Sicherheitsabstand |

Jeder Körper hat einen Anlagenplatz mit bis zu drei Stufen. Körper haben feste Slot-IDs im versionierten Atlas; Namen und Kamerapositionen sind keine Bauadressen. Aufträge werden in der privaten nativen Tabelle `game_site` gespeichert und serverseitig beendet. Kosten, Fristen, Besitzer und Produktionsanker überstehen einen Neustart. Unterschiedliche Körper können parallel bebaut werden, ein einzelner Körper hat höchstens einen laufenden Auftrag. Abbruch erstattet einmalig 50 % der bezahlten Kosten. Beim Abbruch eines Upgrades bleibt die vorhandene Stufe bestehen.

In gewöhnlichen Sternsystemen sind Untersuchung und eigener Systembesitz erforderlich. In neutralen Riss-/Schwarzlochsystemen ermöglicht eine eigene Flotte vor Ort den Bau nach der Untersuchung. Fremde Bauplätze lassen sich weder bebauen noch abbrechen. Die Sichtbarkeitsprojektion zeigt eigene Anlagen sowie fertige fremde Anlagen in aktuell sichtbaren Systemen. Fremde laufende Aufträge und Kosten bleiben privat.

Fertige Anlagen erzeugen Ressourcen alle vier Spielsekunden. Aufwertungen rechnen zuvor angefallene Zyklen mit dem alten Ertrag ab. Die Resonanzkrise beeinflusst die Produktion. Erträge erscheinen in der Reichswirtschaft und in der eigenen Systemproduktion. Der Verlust einer Hauptkolonie zerstört auch ihre Systemanlagen.

## Prüfungen

- **64 Regeltests bestanden:** einschließlich stabiler Körper-IDs, Elternbeziehungen, passender Gebäudetypen und korrekter Einrechnung zusätzlicher Anlagenerträge.
- **28 Backendtests bestanden:** unabhängige Spieler, Eigentumsschutz, nicht passende Körper/Gebäude, unbekannte Slots, unzureichende Ressourcen, doppelte Bauaufträge, paralleler Bau, einmalige Erstattung und Ausbau bis Stufe 3.
- Ein nativer Produktionsfenster-Test vergleicht tatsächlich gutgeschriebene Ressourcen mit den Produktionsankern von Grundversorgung, Kolonie und Anlagen.
- Wiederverbindung rekonstruiert pausierte Bauaufträge. Der isolierte Absturztest auf Port 3110 vergleicht zusätzlich Bauplatz, bezahlten Auftrag und Fertigstellungsfrist vor und nach erzwungenem Prozessende.
- Native Modulkompilierung, SDK-Generierung und Browser-Produktionsbuild erfolgreich. Vite meldet weiterhin einen Größenhinweis für Haupt-/Rendererchunks; die neue Systemoberfläche selbst wird separat nachgeladen.

## Browsernachweis

Testgalaxie **5FF843**, getrennte Gateway-Instanz auf Port 52306:

1. Neues Reich aus einer Vorlage gegründet und Heimatwelt in der Systemansicht geöffnet.
2. Sonne, Erde, Monde, Asteroiden, Gasriese und Ruine über den Systematlas ausgewählt; Schiffsauswahl und Nahansicht visuell geprüft.
3. Außenposten auf Luna bezahlt, bei pausierter Uhr kontrolliert und nach Neuladen mit gleicher Frist wieder aufgenommen.
4. Sonnenkollektor parallel gebaut. Nach Fertigstellung zeigt die Reichswirtschaft zusätzlich **7 Energie, 2 Mineralien und 1 Forschung pro Zyklus** vor Krisenabzügen.
5. Forschungsstation am verlassenen Relais errichtet. Nach Neuladen sind Stufe 1, Ausbauoption und tatsächlicher Ertrag erhalten. Während der späteren Kaskade zeigt sie korrekt 1,5 statt 3 Forschung.
6. Zur Galaxiekarte zurückgekehrt. Die Flotten-/Koloniebedienung bleibt verfügbar.

Bei 1280 × 720 visuell geprüft. Keine Browserfehler oder -warnungen im kontrollierten Ablauf. Die Testgalaxie bleibt pausiert; ihre eigene Gateway-Instanz wird danach beendet. Das normale Backend wurde nicht für diese Tests beendet.

Die bestehenden Galaxien **C5A092** und **7FC03D** wurden mit dem normalen Update-Werkzeug ohne Datenreset aktualisiert. Keine zusätzlichen Testspieler oder Bauten wurden dort erzeugt.

## Umfang und offene Ausbauschritte

Zusätzliche Planeten und Monde sind als Außenanlagen bebaubar. Individuelle Bevölkerung, Distrikte und Siegwertung je weiterer Welt sind noch nicht implementiert; die vorhandene Hauptkolonie bleibt die vollständige Kolonieeinheit. Der Anlagenbau ist in diesem Stand manuell steuerbar; die bestehende KI baut weiterhin ihre bisherigen Kolonien aus. Die Umlaufbahnen sind eine deterministische Darstellung, keine physikalische N-Körper-Simulation. Radiance Cascades und freie lokale Flottenbefehle bleiben spätere Ausbauschritte. Für diese Erweiterung wurde keine neue Großlastmessung oder 165-FPS-Garantie abgeleitet.
