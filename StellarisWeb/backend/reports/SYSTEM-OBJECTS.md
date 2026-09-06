# Persistente Systemobjekte

Stand: 6. September 2026. Erste technische Etappe des Plans für veränderbare Sternsysteme.

## Verhalten

Neue Partien speichern ihren Körperbestand beim Erstellen aus `shared/systemGeneration.ts` und dem aktuellen Sternkatalog. Der Browser und die native Bauprüfung erzeugen keine Ersatzkörper. Auf Nutzerwunsch sind der Körperimport und eingefrorene Generatoren entfernt. Alte Galaxien dürfen gelöscht werden; Abwärtskompatibilität ist keine Anforderung.

Die Systemansicht bietet **Umbenennen** für eigene Nebenobjekte. Namen enthalten 1–60 Zeichen; Besitz, aktiver Zustand, Spielende und Revision werden serverseitig geprüft. Stern und Hauptwelt folgen weiterhin Gründungs- und Kolonieregeln. Eine Umbenennung ändert weder Bauaufträge noch Bahnen oder Produktion.

## Daten

- `game_object`: ID, System-ID, Slot, Revision, Zustand, Änderungszeit, Eltern-ID sowie der gespeicherte Körperdatensatz als JSON. Dieser enthält Namen, Art, Größe, Farbe, Beschreibung, Sternprofil und Bahnelemente.
- `game_object_catalog`: nächster freier Slot und `mainObjectId`. Ein ausdrücklich leerer Bestand bleibt leer.
- Die bisherige Anlagen-ID `systemId:bodySlot` ist zugleich die unveränderliche Objekt-ID. Bestehende `game_site`-Zeilen einschließlich Kosten und Fertigstellung bleiben unverändert. Die Hauptkolonie wird über den Katalog ihrem Objekt zugeordnet; Bevölkerung und Wirtschaft bleiben pro System.
- Neue Slots sind monoton und können über 8 hinausgehen. Entfernte Objekte bleiben als Tombstones gespeichert und werden nicht neu erzeugt.
- Interne Erzeugungs-/Entfernungsfunktionen sind keine Spielermöglichkeiten zum beliebigen Bearbeiten. Sternereignisse und Entfernung mit abhängigen Anlagen, Kolonien oder Monden werden ausdrücklich abgewiesen. Die Test-Reducer liegen ausschließlich in einer separat kompilierten Testdatei und fehlen im Produktionsmodul.

## Synchronisierung und Darstellung

`SystemSubscription` öffnet gefilterte Objekt- und Katalogabonnements beim Betreten der Systemansicht und schließt sie beim Verlassen. Wechsel sind serialisiert. Der Fokus ist pro Verbindung gespeichert; die berechtigte View vereinigt die Fokussysteme derselben Identität, und die Clientabonnements filtern jeweils ihr eigenes System. Die öffentlich bekannte Karte bleibt der geltende Sichtbarkeitsmaßstab. Anonyme Clients erhalten keine Körperdetails; Wirtschaft und Bauaufträge bleiben in ihren bisherigen privaten Views.

Die Szene verwendet aktive gespeicherte Körper, einschließlich neuer Slots. Ein leeres System zeigt einen ausdrücklichen Leerzustand. Zehn priorisierte Gravitationsquellen sind ein reines Effektbudget. Asteroiden erhalten keinen Gravitationseinfluss. Geometrieänderungen bauen die Systemszene mit Freigabe ihrer bisherigen Ressourcen neu auf; feingranulare Aktualisierung einzelner Renderobjekte ist ein späterer Optimierungsschritt.

## Prüfungen

- Regeltests: Projektion entfernter und leerer Bestände, mehr Körper als Gravitationsquellen; bestehende Atlas-, Anlagen-, Rendering- und Spielregeln.
- Native Objekttests: zwei Clients erhalten Erzeugung, Umbenennung und Entfernung; Besitzschutz, veraltete Revisionen, ungültige Namen, neue Bauplätze, blockierte Elternentfernung, nicht wiederverwendete IDs, ausdrücklich leerer Bestand, Detailwechsel/-abmeldung und Wiederverbindung.
- Der native Neustarttest vergleicht Körperdaten, Namen, Revisionen und Elternbezüge nach abruptem Beenden einer getrennten Datenbankinstanz.
- Produktionsbuild und TypeScript-Prüfung für Browser und Datenbankmodul.
- Ergebnis: 121 Regeltests und 29 Backendtests bestanden. Im Browser in einer getrennten 400-System-Partie: eigenen Mond umbenannt, dort Förderanlage begonnen, Browser neu geladen und Namen sowie pausierten Bauauftrag unverändert wiedergefunden. Rückkehr zur Galaxie und fehlerfreie Browserkonsole geprüft.
- Historisch wurden zehn Galaxien zunächst migriert und geprüft: [damaliger Nachweis](system-object-migration-2026-09-06.json). Diese Galaxien wurden beim anschließenden Terraforming-Ausbau mit Nutzerfreigabe gelöscht; der damalige Importpfad ist entfernt.

## Nächste Etappe

Terraforming und frei platzierte Stationen sind inzwischen umgesetzt: [Terraforming](TERRAFORMING.md), [Systemnavigation und Stationen](SYSTEM-NAVIGATION.md). Das Speicherformat unterstützt kreisförmige Bahnen und feste 3D-Positionen. Mehrere Kolonien je System, geneigte Bahnen, Megastrukturen und Sternereignisse folgen mit den jeweiligen Spielregeln.

Modul bauen: `npm run backend:build`. Bei inkompatiblen Änderungen den Gateway stoppen, registrierte Galaxien mit `npm run backend:reset-games` löschen, Gateway neu starten und eine neue Partie gründen. Das Update-Werkzeug ist nur für kompatible Moduländerungen vorgesehen.
