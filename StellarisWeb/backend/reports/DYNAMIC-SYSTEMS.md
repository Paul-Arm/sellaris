# Veränderbare Sternsysteme

Status: Persistente Himmelskörper, Detailabonnements, Umbenennung, Terraforming, freie Systemflüge, Befehlswarteschlangen, Körpererkundung und freie Stationsplatzierung sind implementiert; siehe [SYSTEM-OBJECTS.md](SYSTEM-OBJECTS.md), [TERRAFORMING.md](TERRAFORMING.md) und [SYSTEM-NAVIGATION.md](SYSTEM-NAVIGATION.md). Die Planetenverwaltung mit Sektoren und Pops ist integriert. Eine dreistufige [Dyson-Megastruktur](MEGASTRUCTURES.md) und ein [kontrollierter Sternkollaps](STELLAR-PROJECTS.md) mit Folgen für Klima, Anlagen und Wirtschaft sind spielbar. Der folgende Text beschreibt die historische Ausgangslage und das weiterführende Zielmodell. Mehrere eigenständige [Planetenkolonien je System](PLANET-COLONIES.md) sind ebenfalls umgesetzt. Ein dreistufiger [Materiedekompressor](DECOMPRESSOR.md) an Schwarzen Löchern ist ebenfalls spielbar. Als erstes natürliches Sternereignis sind [Sternenstürme](STELLAR-WEATHER.md) mit Vorwarnung, vorübergehendem Solarverlust und Erholung umgesetzt. Weitere Megastrukturen, natürliche Sternumwandlungen und zerstörte Elternkörper bleiben offen. Alte Galaxien dürfen laut Nutzer gelöscht werden; Migration und Abwärtskompatibilität sind keine Anforderung.

## Historischer Ausgangspunkt vor persistenten Objekten

Die Galaxie, Besitzverhältnisse, Wirtschaft und Bauaufträge liegen in SpacetimeDB. Die einzelnen Himmelskörper werden bisher durch `shared/celestial.ts:systemBodies` aus Systemdaten abgeleitet. Dieselbe Funktion läuft im Browser und bei der serverseitigen Anlagenprüfung. Änderungen am Generator ändern dadurch auch die Darstellung bestehender Partien.

Weitere aktuelle Grenzen:

- `gameSite` adressiert Körper mit `systemId + bodySlot`; `game-sites.ts` akzeptiert nur Plätze 0–8.
- `gameSystem.colonyJson` und die Zuordnung der Kolonietabelle setzen derzeit eine Hauptkolonie je System voraus.
- `star` repräsentiert zugleich den Galaxieknoten und dessen zentralen Stern beziehungsweise Anomalie.
- Der Renderer erzeugt eine feste Körperliste und besitzt zehn Gravitationseinträge. Veränderungen einzelner Körper können noch nicht als Datenänderungen eingespielt werden.

## Zielmodell

Ein System ist ein dauerhafter Ort in der Galaxie. Sterne, Planeten, Monde, Asteroidenfelder, Stationen und Megastrukturen sind Objekte innerhalb dieses Ortes. Ein Stern kann sich verändern oder verschwinden, ohne die System-ID, Hyperlanes oder andere Objekte zu verlieren. Das Modell erlaubt auch mehrere Sterne.

`system_object` speichert gemeinsame Eigenschaften:

| Feldgruppe | Inhalt |
| --- | --- |
| Identität | Unveränderliche Objekt-ID, System-ID, Name, Objektart, Revision |
| Lebenszyklus | Aktiv, im Bau, zerstört oder entfernt; Zeitpunkt der Änderung |
| Ort | Feste lokale Position `x/y/z` oder Umlaufbahn um eine Objekt-ID beziehungsweise den Systemursprung |
| Bahn | Radius, Phase zum Referenzzeitpunkt, Periode, Neigung und Orientierung |
| Darstellung | Reproduzierbarer Visual-Seed, Größe und Referenz auf den Darstellungsstil |
| Gravitation | Expliziter Einflussparameter; Asteroidenfelder bleiben bei null |

Typspezifische Daten liegen in zugeordneten Tabellen: Sternzustand, Planetenzustand, Stationszustand und Megastrukturzustand. Eine Kolonie und eine Anlage referenzieren künftig ihre Körper-/Objekt-ID. Dadurch können mehrere Planeten eines Systems eigene Bevölkerung, Terraforming und Infrastruktur besitzen.

Ein Asteroidenfeld ist ein gespeichertes Spielobjekt mit Ausdehnung, Dichte und Visual-Seed. Seine rein dekorativen Fragmente dürfen weiterhin lokal erzeugt werden. Einzelne abbaubare oder zerstörbare Asteroiden benötigen dagegen eigene Objekt-IDs.

## Änderungen während des Spiels

Der Browser sendet eine Absicht an den Server. SpacetimeDB prüft Besitz, Forschung, Ressourcen, Zielzustand und Platzierung und schreibt die Änderung atomar. Es gibt keinen frei zugänglichen Clientbefehl zum beliebigen Ändern oder Löschen von Körpern. Ereignisse und Simulation benutzen dieselben internen Änderungsfunktionen.

| Vorgang | Serverzustand und Ablauf |
| --- | --- |
| Körper entsteht | Neue Objekt-ID und gültige Position/Bahn erzeugen; berechtigte Clients erhalten den neuen Datensatz. |
| Körper verschwindet | Lebenszyklus ändern; abhängige Monde, Anlagen, Kolonien und laufende Projekte nach einer expliziten Ereignisregel behandeln. IDs werden nie wiederverwendet. |
| Stern verändert sich | Sternzustand und Darstellungs-/Gravitationsparameter ändern; betroffene Planeten und die Galaxieübersicht konsistent aktualisieren. |
| Planet wird terraformt | Projekt mit Kosten, Zielklasse und Spielzeit anlegen; beim Abschluss den vorhandenen Planeten aktualisieren. Seine ID und zugehörige Kolonie bleiben erhalten. |
| Megastruktur entsteht | Bauprojekt mit Zielort und Ausbaustufen; Bauzustand bereits sichtbar. Bei Fertigstellung wird dieselbe Baustelle zum aktiven Objekt. |
| Station wird frei platziert | Der Spieler setzt eine Vorschau in lokalen Systemkoordinaten; der Server prüft Grenzen, Abstände und Kosten und speichert den bestätigten Ort. Eine Umlaufbahn kann optional gewählt werden. |

Freie Positionen beziehen sich auf den unverformten Systemraum. Die Gravitationsebene dient nur der Darstellung und verändert keine gespeicherten Stationskoordinaten. Die Mausposition wird mit einer definierten Platzierungsebene geschnitten; eine zusätzliche Höhensteuerung ermöglicht freie räumliche Platzierung.

Projekte verwenden die vorhandene Spieluhr: Pause, Geschwindigkeit, Abbruch, Wiederverbindung und Neustart müssen erhalten bleiben. Beim Abschluss wird erneut geprüft, ob Ziel und Voraussetzungen noch gültig sind. Zerstörte Ziele dürfen keine verwaisten Aufträge oder doppelte Erträge hinterlassen. Die konkrete Folge einer Sternzerstörung oder eines Terraforming-Abbruchs gehört in die jeweilige Spielregel.

## Browser und Synchronisierung

Der Browser liest die freigegebenen Objektzeilen aus SpacetimeDB. Objektentstehung, Entfernung und Eigenschaftsänderungen aktualisieren die Szene anhand stabiler IDs, einschließlich Auswahl, Beschriftung und Gravitation. Geometrien entfernter Objekte werden freigegeben; bei verlorener Auswahl kehrt die Ansicht zur Systemübersicht zurück.

Bahnen bleiben effizient: Der Server speichert Bahnelemente und Referenzzeitpunkt; beide Seiten können daraus zur gemeinsamen Spielzeit eine Position berechnen. Es müssen keine Planetenpositionen in jedem Bild übertragen werden. Ein neuer Client rekonstruiert dieselbe Bewegung aus dem aktuellen Zustand.

Detailabonnements werden auf das betrachtete System und die serverseitig erlaubte Sichtbarkeit begrenzt. Die Galaxiekarte erhält nur die nötige Zusammenfassung. Das bisherige Limit von zehn Gravitationseinträgen wird vom Objektbestand entkoppelt: Der Renderer verwendet ein begrenztes Darstellungsbudget für relevante Quellen, ohne die Anzahl der Spielobjekte zu begrenzen.

## Einführung mit neuen Spielständen

1. Tabellen und interne Objektänderungsfunktionen direkt weiterentwickeln. Keine eingefrorenen Generatoren oder Migrationen für alte Galaxien ergänzen.
2. Den aktuellen Generator nur beim Erstellen neuer Systeme einsetzen. Ein leerer Objektbestand ist keine Aufforderung zur Neuerzeugung.
3. Bei inkompatiblen Schemaänderungen alte Galaxien löschen und neue Partien erzeugen. Reichs- und Speziesvorlagen bleiben bestehen.
4. Nach Terraforming freie Stationen, danach mehrstufige Megastrukturen und Sternereignisse einführen. Mehrere Kolonien pro System erfordern außerdem die Anpassung von Wirtschaft, KI, Siegbedingungen und Flottenzielen an Körper-IDs.

Die erste technische Etappe ist eine beobachtbare Kette: Ein serverseitiger Test fügt einen Körper hinzu, verändert ihn und entfernt ihn wieder; zwei verbundene Clients übernehmen jeden Schritt, und Wiederverbindung sowie Datenbankneustart erhalten den letzten Zustand. Weitere Integrationstests prüfen veraltete Befehle, parallele Bauversuche, Platzierungskollisionen, Projektabbrüche und zerstörte Elternkörper.
