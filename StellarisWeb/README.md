# SINGULARITY

Ein spielbarer Multiplayer-4X-RTS-Prototyp für den Browser. Inspiriert von interstellarer Strategie, Gravitationskonturen und leuchtenden Raumzeit-Anomalien. Eigenständige Gestaltung, keine Stellaris-Assets.

**Das normale Spiel verwendet SpacetimeDB.** Neue Galaxien enthalten wahlweise 400, 700 oder 1.000 Systeme und bis zu 25 menschliche/KI-Imperien. Wirtschaft, Forschung, Reisen, Kolonisierung, Diplomatie und Gefechte liegen dauerhaft im nativen Backend. Die Node-Schicht vermittelt Lobby, private Vorlagen und Browserzugriff. Der alte Node-Spielserver und automatische Import sind entfernt. Bei inkompatiblen Entwicklungsänderungen werden alte Galaxien gelöscht und neue Partien begonnen; Abwärtskompatibilität ist keine Anforderung. [Diplomatie und Prüfung](backend/reports/DIPLOMACY.md), [Architektur](backend/README.md), [Ausbauplan](PLAN.md).

## Starten

Voraussetzung: Node.js 22.12+ (hier mit Node 24 geprüft).

```sh
npm ci
npm run backend:setup
npm run backend:build
npm run backend:start
```

In einem zweiten Terminal:

```sh
npm run dev
```

Spiel öffnen: **http://localhost:5173**. Reichsvorlage auswählen und einen Sektor gründen oder einem Raumcode beitreten. Vite leitet `/ws` und `/v1` an den Gateway auf Port 3001 weiter; SpacetimeDB bindet intern auf Port 3100. Die laufende Sitzung bleibt innerhalb des Tabs gespeichert und wird nach Neuladen wieder aufgenommen. Ein Labor-Seed ist für das normale Spiel nicht erforderlich.

### Serververwaltung

Unter **/admin** (auch über „Serververwaltung“ in der linken Navigation) zeigt eine kompakte Tabelle alle registrierten Matches dieses Gateways. Jede Zeile öffnet eine Detailansicht; der Raumcode im URL-Fragment macht die Auswahl direkt verlinkbar. Die Übersicht aktualisiert sich alle 15 Sekunden. Suche und Statusfilter grenzen die Liste ein. Nicht erreichbare Datenbanken bleiben sichtbar.

Die Matchdetails enthalten eine verschiebbare, zoombare Galaxiekarte mit Systemen, Hyperlanes, Besitzfarben und Flotten. Ein besetztes System oder eine Reichszeile öffnet Regierung, Spezies, Ethiken, Technologien, Ressourcen, Bevölkerung und Kriege. Kolonien und Flotten haben eigene Listen und lassen sich auf der Karte zentrieren. Der JSON-Bericht exportiert die angezeigten Matchdaten; er ist kein wiederherstellbares Backup.

Der Zugang verwendet einen separaten Schlüssel: `ADMIN_PANEL_TOKEN` beim Gateway-Start setzen oder den automatisch erzeugten Schlüssel aus dem Gateway-Terminal verwenden. Automatische Schlüssel wechseln bei jedem Neustart. Der Browser hält den Schlüssel nur im Arbeitsspeicher; nach Neuladen ist eine neue Anmeldung erforderlich. Der SpacetimeDB-Administratorschlüssel bleibt auf dem Gateway. Bei Zugriff über das Internet HTTPS verwenden.

Aktionen: Pause/Fortsetzen, Tempo 1×–4×, KI hinzufügen, einen verbundenen menschlichen Spieler als Host einsetzen, Ressourcen gutschreiben oder abziehen (maximal 100.000 pro Buchung), Einladungslink kopieren und dauerhaft löschen. Reichseingriffe werden im nativen Backend auf Admin-Berechtigung geprüft; Ressourcenbuchungen und Hostwechsel erscheinen im Ereignisprotokoll. Negative Bestände werden atomar abgelehnt. Löschen verlangt die Eingabe des Raumcodes und entfernt ausschließlich die registrierte Galaxiedatenbank samt Registrierung. Reichs- und Speziesvorlagen bleiben erhalten. Ein menschenleerer Server kann vom Administrator ebenfalls gestartet werden.

### Gemeinsam spielen

1. Oben rechts den Sektor öffnen und Raumcode oder Einladungslink kopieren.
2. Im zweiten Browser den Link öffnen, eine Reichsvorlage wählen und beitreten. Bis zu 25 Menschen und KI-Imperien pro Sektor.
3. Für weitere Geräte die vom Dev-Server ausgegebene **LAN-Adresse** anstelle von `localhost` verwenden, etwa `http://192.168.x.x:5173`. Den Einladungslink von dieser Adresse aus kopieren. Die Geräte müssen den Rechner erreichen können.

Die Spielsimulation läuft auf deinem Server. Der Host steuert Pause und Tempo. Wenn er geht, übernimmt der nächste verbundene Spieler. Ohne verbundene Spieler pausiert die Simulation. Beim Wiederverbinden eines zuvor leeren Sektors erhält der erste Spieler die Zeitsteuerung.

## Spielen

Ziel: **8 Systeme** durch Sternenbasen kontrollieren.

- **Erkunden:** Forschungsschiff in ein Zielsystem schicken → **Alle Himmelskörper erkunden**. Das Schiff fliegt Sterne, Planeten, Monde, Asteroidenfelder und Ruinen nacheinander an und untersucht jeden Körper vor Ort. Die Dauer ergibt sich aus dem Flugweg und einem Spieltag Untersuchung je Körper. Bauplätze und Forschungsbonus werden erst nach der vollständigen Route freigegeben.
- **Freie Flüge und Warteschlange:** In der Systemansicht eine eigene Flotte wählen → **Flugaufträge**. X/Z auf der Karte wählen, Höhe Y festlegen und **Position anfliegen**. **Aufträge anhängen** verbindet bis zu 32 lokale Flüge, Hyperraumreisen, Erkundungen und Kolonisierungen. Wartende Aufträge können einzeln entfernt werden. **Stoppen** leert die Liste; ein laufender Hyperraumabschnitt endet am nächsten System. Verbände bewegen sich gemeinsam.
- **Freie Stationen:** Im eigenen untersuchten System **Freie Station platzieren** öffnen, Position und Höhe wählen, Forschungsstation oder Orbitalhabitat auswählen und errichten. Die Vorschau bucht keine Kosten. Körper, Stationen und Umlaufbahnen benötigen Abstand. Nach Bauabschluss liefert die Station Produktion und kann wie eine Körperanlage ausgebaut werden.
- **Expandieren:** Ein vollständig untersuchtes, unbeanspruchtes System wählen → **Außenposten errichten**. Kosten: 100 Energie + 150 Mineralien, Bauzeit 24 Tage. Erst die Fertigstellung überträgt den Systembesitz. Danach kann ein Kolonieschiff für 80 Energie + 80 Mineralien eine Welt besiedeln; Besitznahme und Koloniegründung sind getrennt.
- **Wirtschaft:** Kolonien produzieren alle vier Spieltage Ressourcen. Eine Bergbaustation kostet 50 Energie + 100 Mineralien und verdoppelt die lokalen Energie- und Mineralienerträge.
- **Sternenbasis / Raumwerft:** Basis im Systempanel oder in der Systemansicht öffnen. Außenposten → Sternenhafen → Sternenfestung → Zitadelle; 0/2/4/6 Modulplätze. Raumwerft, Geschützbatterie, Versorgungsdock und Handelszentrum besitzen jeweils drei Modulstufen. Ein fertiges Werftmodul erlaubt Schiffsbau auch ohne Kolonie. Die gemeinsame Schiffswarteschlange umfasst bis zu fünf Aufträge. Zusätzliche Werftstufen beschleunigen neue Aufträge.
- **Forschung:** Eine Gebietsübersicht führt zu den aufgedeckten Technologien. Anfangs sind nur Grundlagen bekannt; abgeschlossene Voraussetzungen enthüllen die nächste Forschungsstufe. Verborgene Technologien erscheinen weder in der Suche noch als auswählbare Ziele. Ziel auswählen → **Forschung einplanen**. Gebiets- und Wissensfilter, eingeklapptes erforschtes Wissen und Zoom halten auch große Bäume übersichtlich. Daten bezahlen den Projektstart; Compute wird nach Prioritäten auf parallele Projekte verteilt. Projekte lassen sich ohne Fortschrittsverlust parken. Der Datensynthese-Regler reserviert Compute für neue Daten; ungenutzte Rechenleistung fließt automatisch dorthin. Rechenzentren liefern durch besetzte Arbeitsplätze zusätzliches Compute. Karte ziehen, zoomen oder über Suche und Pfeiltasten erkunden. [Regeln und Prüfung](backend/reports/RESEARCH.md).
- **Kampf:** Korvetten greifen im selben System Kriegsgegner und deren Verteidigung automatisch an. Friedliche Reiche können einander passieren. Wächter besiegst du mit Korvetten. Fällt die Systemverteidigung, wird die Sternenbasis zerstört. Das System wird unabhängig und kann mit einem neuen Außenposten beansprucht werden. Zerstörte Schiffe gehen verloren.
- **Diplomatie:** Handschlag-Symbol links öffnen. Krieg ausdrücklich erklären, Frieden anbieten und als Empfänger annehmen oder ablehnen. Angenommener Frieden beendet gemeinsame Gefechte sofort und schützt 120 Spieltage vor erneutem Krieg.
- **Handel:** Energie, Mineralien und Daten direkt tauschen. Die angebotenen Mengen werden sofort reserviert, der Tausch wird bei Annahme atomar ausgeführt. Ablehnung, Rücknahme, Krieg oder Ablauf erstatten die Reservierung genau einmal. Angebote gelten 60 Spieltage; Pause hält Fristen an. Nur die beiden Vertragspartner sehen die Konditionen.
- **Anomalien:** Die erstmalige Untersuchung einer unberührten Anomalie liefert 90 Daten. Reguläre Untersuchungen liefern 25. Schwarze Löcher und Raumzeitrisse sind nicht kolonisierbar.
- **Ereignisse:** Das Funksymbol links öffnet das **Lagezentrum**. Anomalie-Archive und deine erste neue Außenkolonie bieten Entscheidungen mit sichtbaren Kosten und Erträgen. Nach 90 Spieltagen wird eine kostenlose Standardoption gewählt. Abgeschlossene Entscheidungen bleiben im Verlauf.
- **Resonanzkaskade:** Nach 180 Spieltagen beginnt die Vorwarnung; eine Untersuchung des goldenen Risses kann sie früher auslösen. Ohne Eindämmung sinkt die Kolonieproduktion nach 120 weiteren Spieltagen um 25 %, nach nochmals 120 um 50 %. Die Grundversorgung bleibt erhalten. 120 Energie schützen alle eigenen heutigen und künftigen Kolonien. Ein Stabilisierungspaket kostet 60 Energie und 30 Daten. Gemeinsam sind `3 + ceil(Imperienzahl / 2)` Pakete erforderlich; spätere Beitritte erhöhen dieses Ziel nicht. Erfolgreiche Eindämmung beendet die Krise und vergütet jeden Beitrag mit 40 Daten. Fristen, Beiträge, Schutz und Entscheidungen überstehen Pause und Wiederverbindung.
- **Navigation:** Über die Systemsuche Sterne und Kolonien finden und direkt zentrieren. Enter wählt den ersten Treffer. Bei aktiver Zielwahl kann so auch ein Flottenziel gewählt werden.
- **Verbände:** Neue Korvetten verstärken einen passenden eigenen Verband an der Werft. Über **Verband verwalten** einzelne Schiffe auswählen, abteilen und ruhende militärische Verbände am selben Ort vereinen. Im Kampf ist zunächst ein Rückzug erforderlich.
- **Gefechtsansicht:** Status, Verluste, Hülle/Schilde und verursachter Schaden erscheinen als gedrosselte Übersicht. **Gefecht ansehen** öffnet die taktische Systemansicht; beim Verlassen werden die individuellen Kampfbewegungen abbestellt.
- **Systemansicht:** Ein System doppelklicken oder **Systemansicht öffnen** wählen. Sterne, Planeten, Monde, Gasriesen, Asteroiden und Ruinen lassen sich direkt oder über den Systematlas auswählen. Sichtbare Flotten stehen als Schiffsmodelle im System; die Nahansicht zentriert Körper oder Verband. Die Hauptwelt öffnet weiterhin die Kolonieverwaltung.
- **Systembefehle:** Rechtsklick in den freien Raum setzt das Flugziel des ausgewählten eigenen Verbands, Umschalt + Rechtsklick hängt es an. Rechtsklick auf Objekte oder ihre Beschriftungen öffnet passende Aktionen, etwa Sternenbasis oder Bergbaustation bauen. Das separate Flugziel-Menü entfällt. Systemflüge behalten bei Kurswechseln ihren Schwung, drehen in Kurven ein und haben einen Bremsweg; 800 Einheiten dauern aus dem Stand bei 1× zehn Sekunden. Bauaufträge schicken das ausgewählte eigene Schiff zuerst zum Bauplatz. Bau und Kostenbuchung beginnen erst in Reichweite.
- **3D-Kamera:** Links ziehen dreht und neigt die Perspektive, rechts ziehen verschiebt sie, das Mausrad zoomt. Die Fadenkreuz-Schaltflächen fokussieren die Auswahl beziehungsweise setzen die Kamera zurück. Hyperlane-Zugänge sind als türkis leuchtende Wurmlöcher in die Raumzeitfläche eingebettet. In der aktuellen Experimentvariante stehen die Öffnungen senkrecht, mit ihrem Mittelpunkt auf Höhe der lokalen Raumzeitfläche. Die Fläche und ihre Konturen biegen sich weich zum Portal und laufen hinter ihm als längere, flachere Rampe nach außen aus; der animierte Tunnel führt ebenfalls nach außen. Die Zugänge liegen nahe dem Systemrand. Ihre verlängerten Routen führen durch die Mittelachse der Trichter und schließen weiter außen weich an die lokale Fläche an; die Trichterwände verdecken dahinterliegende Linienabschnitte. Ihre Richtung entspricht den echten Verbindungen; eng benachbarte Öffnungen sind unter Berücksichtigung ihrer Ausläufe radial versetzt. Ein Klick auf den Zugang oder seine seitliche Beschriftung öffnet das Nachbarsystem. **Konturen** und **Licht** schalten Gravitationslinien beziehungsweise Bloom um.
- **Systemanlagen:** Nach Untersuchung im eigenen Sternsystem einen Körper auswählen und eine passende Anlage errichten. Sonnenkollektoren liefern Energie, Förderanlagen Mineralien, Forschungsstationen Daten; Orbitalhabitate und Atmosphärenkollektoren liefern gemischte Erträge. Jeder Körper hat einen Anlagenplatz mit drei Ausbaustufen. Mehrere Körper können parallel bebaut werden, ein Abbruch erstattet einmalig 50 %. Auch Risse und Schwarze Löcher benötigen zuerst einen eigenen Außenposten. Anlagen liefern monatliche Erträge, unterliegen der Resonanzkrise und erscheinen separat in der Wirtschaftsübersicht.
- **Objektnamen:** Eigene Nebenwelten, Monde und weitere Nebenobjekte in der Systemansicht auswählen → **Umbenennen**. Namen und Himmelskörper werden dauerhaft gespeichert und mit Mitspielern synchronisiert. Anlagen bleiben an derselben Objekt-ID. [Speicherung und Prüfungen](backend/reports/SYSTEM-OBJECTS.md).
- **Terraforming:** „Klimagestaltung“ erforschen, einen eigenen untersuchten Planeten in der Systemansicht auswählen und das Zielklima festlegen. Die Vorschau zeigt Bewohnbarkeit, Kosten und auf besiedelten Haupt- und Nebenwelten die Kolonieerträge. Pause hält Projekte an, Abbruch erstattet 50 %. Bevölkerung und Infrastruktur bleiben erhalten. [Regeln und Prüfungen](backend/reports/TERRAFORMING.md).

Die Sternenkarte ist öffentlich. Untersuchte Systeme zeigen ihre Rohstoffe. Fremde Flotten sind nur dort sichtbar, wo eigene Flotten oder Kolonien sind. Territorien und Koloniezahlen sind öffentlich.

**Hyperlane-Lichtstrom:** Hinter den Portalen verlaufen feine türkisfarbene Lichtfäden mit weichem Saum. Auf den geraden Austritt folgt ein flacher Bogen; sein Ende und seine Endrichtung liegen auf der tatsächlichen galaktischen Zielrichtung. Die Spuren verjüngen sich und verblassen bis etwa 55 % über den Rand der Raumzeitfläche hinaus. Radial versetzte Zugänge erhalten entsprechend unterschiedliche Spurlängen. Die Raumzeitfläche geht auf der Systemseite über einen breiteren, flacheren Einflussbereich in die Öffnungen über. Wenige langsam nach außen wandernde Impulse folgen der Kurve. Die Breite passt sich dem Zoom an; verdeckte Abschnitte bleiben hinter den Trichterwänden verborgen.

**Sternvielfalt:** Die Systemansicht unterscheidet Spektralklassen, Riesensterne, Neutronensterne und Pulsare. Schwarze Löcher verwenden einen [Schwarzschild-Shader](backend/reports/BLACK-HOLE-SHADER.md) mit gekrümmten Lichtwegen, mehrfach abgebildeter Akkretionsscheibe und Dopplerverschiebung; neue Galaxien enthalten auch seltene Quasare mit polaren Jets. Die Suche versteht Begriffe wie „O-Klasse“, „Neutronenstern“ und „Quasar“. Sternoberflächen und feine Koronen reduzieren die weiße Überstrahlung, während die Raumbeleuchtung erhalten bleibt. [Umsetzung und Prüfung](backend/reports/STELLAR-VARIETY.md).

**Systemverteilung:** Primäre Umlaufbahnen liegen weiter außerhalb des Zentrums, in Sternsystemen bei etwa 462 bis 1.165 Karteneinheiten. Monde behalten ihre lokalen Bahnen. Die Übersichtskamera berücksichtigt die größere Ausdehnung. Größere Asteroidenansammlungen sind selten (8 % Seed-Wahrscheinlichkeit): lockere, örtlich begrenzte Wolken aus einzelnen glatten Körpern mit dezent leuchtenden Rändern und räumlicher Tiefe. Übrige Systeme enthalten kompakte Rohstofffragmente. Die Wolken erzeugen keine Gravitationstrichter oder Lichtflecken auf der Raumzeitebene. Häufigkeit und Aussehen bleiben pro System stabil. Bestehende Anlagenplätze bleiben erhalten; die Darstellung gilt auch für vorhandene Spielstände.

### Neu in Alpha 0.2: Kolonien & autonome Imperien

Eigene Welt auswählen → **Kolonie verwalten**. Alternativ das Planetensymbol links verwenden. Jede Welt hat eine wachsende Bevölkerung und begrenzte Distriktplätze. Pro Kolonie kann ein Ausbau gleichzeitig laufen, unabhängig von der Raumwerft.

| Ausbau | Ertrag pro Stufe | Erste Stufe | Bauzeit |
|---|---|---|---|
| Fusionsreaktor | +4 Energie / Zyklus | 50 Energie, 100 Mineralien | 16 Tage |
| Orbitalindustrie | +4 Mineralien / Zyklus | 80 Energie, 80 Mineralien | 18 Tage |
| Quantenlabor | +3 Daten / Zyklus | 90 Energie, 120 Mineralien | 22 Tage |
| Schildbastion | +40 Verteidigung, +1 Hüllenreparatur / Tag | 60 Energie, 120 Mineralien | 20 Tage |

Jeder Ausbau hat drei Stufen, die jeweils einen Distrikt belegen. Weitere Stufen kosten 65 % der Grundkosten zusätzlich pro bestehender Stufe und brauchen jeweils acht Spieltage länger. Abbrechen erstattet einmalig 50 % der bezahlten Kosten.

Hauptwelten starten mit 6 Mrd. Einwohnern, neue Kolonien mit 2 Mrd. Die Bevölkerung wächst alle 240 Spieltage um 1 Mrd., bis maximal 12 Mrd. Die Distriktkapazität ist `4 + floor(Bevölkerung / 2)`, maximal zehn. Bevölkerung repräsentiert in diesem Stand das Ausbaupotenzial; eine Arbeitsplatzzuteilung gibt es noch nicht.

**Schwerpunkte:** Ausgewogen lässt alle Erträge unverändert. Energie, Industrie oder Forschung erhöhen den jeweiligen Ertrag um 40 % und senken die beiden anderen um 15 %. Bergbau verdoppelt die natürlichen Energie-/Mineralienvorkommen; Ausbau-Erträge werden anschließend addiert. Danach folgen Schwerpunkt und Technologiebonus. Die Wirtschaftsübersicht (auf eine Ressource oben klicken) zeigt jede Kolonie, die Grundversorgung und die Summe.

**Reparatur:** Eine fertige Sternenbasis repariert in eigenen, feindfreien Systemen 1 Hülle/Tag; Werftstufen erhöhen dies um 1, Versorgungsdockstufen um 2. Besetzte Schildbastionen ergänzen Reparatur und Verteidigung. Systemverteidigung regeneriert 0,75/Tag. Bei Zerstörung der Basis gehen Systembesitz, Kolonien und zugehörige Projekte verloren.

**KI:** Multiplayer-Dialog → **KI-Imperium hinzufügen**. Nur der Host kann freie Plätze mit KI besetzen. Die KI erkundet, kolonisiert, forscht, baut ihre Wirtschaft aus und führt Korvettenverbände. Es gelten dieselben Befehle, Kosten und Produktionsregeln wie für Menschen. Sie greift nur erklärte Kriegsgegner an und erklärt derzeit nicht selbst Krieg. Friedensangebote nimmt sie an; bezahlbare Tauschgeschäfte akzeptiert sie ab gleichem Wert (Energie 1, Mineralien 1,2, Daten 2). Eine differenziertere Außenpolitik ist ein späterer Ausbauschritt.

KI-Imperien pausieren mit dem Sektor und halten einen menschenleeren Raum nicht aktiv. Sie können wie Menschen durch acht Systeme gewinnen. Die KI wird bestehenden Räumen nur auf Host-Befehl hinzugefügt.

| Steuerung | Aktion |
|---|---|
| Linksklick | System auswählen |
| Ziehen | Galaxie verschieben |
| Mausrad / ± | Zoomen |
| Rechtsklick auf System | Ausgewählte Flotte dorthin schicken |
| Doppelklick auf System | Systemansicht öffnen |
| F | Auswahl zentrieren |
| Leertaste | Pause/Fortsetzen als Host |
| Escape | Dialog oder Zielwahl schließen |

## Architektur

### Schiffs- und Stationsdesigns

Alle sechs Sets **PRISMA, AUREOLE, BASTION, PARALLAX, NEXUS und VEKTOR** sind als 120 GLB-Modelle
mit 204 Animationsclips eingebunden. Das Reichsmenü und die Reichsvorlagen bieten die Auswahl
**Schiffs- und Stationsdesign**. Der kostenlose Wechsel einer laufenden Partie wird dauerhaft
gespeichert und an Mitspieler übertragen; vorhandene Partien ohne Auswahl verwenden PRISMA.

Das Raketensymbol unten links öffnet den **Designhangar** unter `/models`: alle Schiffe,
Stationsstufen, Plattformen und Megastrukturen lassen sich drehen, vergrößern und mit ihren
Animationsclips ansehen. Die System- und Gefechtsansicht verwenden die GLBs für die vorhandenen
Schiffstypen. Körperanlagen und Kolonieausbauten erhalten passende Stations-/Megastrukturmodelle.
Animationen folgen Pause und Spieltempo. Weitere Militärklassen von Fregatte bis Titan sind als
Modelle im Hangar verfügbar; ihre eigene Bau- und Kampflogik ist noch offen.

[Modellzuordnungen, Originalpakete und Import](public/models/README.md).

Für die erstmalige Übernahme in andere bestehende Datenbanken benötigt die erweiterte öffentliche
Reichsansicht `npm run backend:update-games -- --break-clients`; anschließend alle Clients neu laden.
Das Update-Werkzeug verbietet das Löschen von Daten ausdrücklich. Die hier registrierten acht
Galaxien wurden bereits aktualisiert.

- `src/`: React + TypeScript, HTML/CSS-Kommandopanels; Canvas-Overlay für Sterne, Hyperraumverbindungen und Flotten.
- `src/GalaxyMap.tsx`: Three.js-Shader für Rauschen, Gravitationskonturen und Anomalien; Canvas-Fallback. Kamera, Marker und Klickflächen folgen gemeinsam jedem Displayframe. Nur die ruhende Hintergrundanimation ist auf 30 Hz begrenzt. Reisen werden aus der synchronisierten Spieluhr pro Frame berechnet; `LabScene.tsx` interpoliert gepufferte Gefechtstage und verwendet gemeinsame Instanzpuffer. Die gemeldeten 165 FPS waren die Displaygrenze des Nutzers, keine gemessene Leistungsobergrenze.
- `shared/game.ts`: reine Spielregeln, Wegsuche, Produktion, Bau, Forschung, Kolonisierung, Sichtbarkeit und gleichzeitige Schadensberechnung.
- `shared/colonies.ts`: additive Spielstandmigration, Bevölkerung, Ausbauten, Schwerpunkte und einheitliche Produktionsberechnung. `src/ColonyManager.tsx` enthält die Kolonieverwaltung.
- `spacetimedb/src/game-*.ts`: Native Spieltabellen, Reducer, Sichtbarkeit, Produktion, Kolonien, Reichsänderungen und KI. `commands.ts`, `rules.ts` und `simulation.ts` teilen das geprüfte Flotten-/Gefechtsfundament mit dem Labor.
- `server/index.ts`, `nativeGateway.ts`, `nativeProxy.ts`: Private Vorlagenbibliothek, einmalige Sitzplatz-Tickets, native Galaxie-Provisionierung, statische Dateien und WebSocket-Weiterleitung. Kein eigener Spieltick, kein Welt-Snapshot-Versand und keine alten Sitzungs-/Befehlswege.
- `backend/game-client.ts`: Projektion der berechtigten Abonnements in das React-Spielmodell. Kein Versand vollständiger Weltzustände durch Node für native Partien.
- `.spacetime/data/`: Dauerhafte SpacetimeDB-Daten. `data/native-sectors.json`: Zuordnung der Raumcodes. Alte Node-Speicher wurden einmalig nach `data/archive/node-backend-2026-09-05/` verschoben und werden nicht mehr geladen oder fortgeschrieben. `data/empire-libraries.json` enthält die private Vorlagenbibliothek.

**Zeit und Optimierungen:** Der Server verarbeitet ganze Spieltage. Bei 1× vergeht ein Spieltag pro Echtzeitsekunde; der Client verwendet Tagesbruchteile für flüssige Bewegung. [Umsetzung, Messwerte und Prüfgrenzen](backend/reports/OPTIMIZATIONS-2026-09-06.md).

Rendering-Dokumentation: [Three.js ShaderMaterial](https://threejs.org/docs/pages/ShaderMaterial.html). Transport: [ws](https://github.com/websockets/ws).

## Produktionsbetrieb

```sh
npm run build
npm start
```

Bei laufendem SpacetimeDB liefert **http://localhost:3001** den gebauten Client und beide Verbindungswege aus. Nach Moduländerungen: `npm run backend:build`, `npm run backend:update-games`, anschließend Browser neu laden. Das Update-Werkzeug pausiert registrierte Galaxien kurz, aktualisiert sie ohne Datenreset und stellt Pause/Tempo wieder her. Bei einem fehlgeschlagenen Update bleibt die betroffene Galaxie zur Diagnose pausiert. Vorhandene aktive Gefechte werden bei der ersten Diplomatie-Übernahme als Krieg übernommen; übrige Beziehungen beginnen friedlich.

Konfiguration über Umgebungsvariablen:

| Variable | Standard | Zweck |
|---|---|---|
| `PORT` | `3001` | HTTP/WebSocket-Port |
| `HOST` | `0.0.0.0` | Bind-Adresse |
| `DATA_DIR` | `data` | Persistente Spielstände |
| `ALLOWED_ORIGIN` | nicht gesetzt | Optional genau erlaubter WebSocket-Origin |
| `SPACETIME_HTTP` | `http://127.0.0.1:3100` | Interner SpacetimeDB-Endpunkt |
| `SPACETIME_WS` | `ws://127.0.0.1:3100` | Interner nativer WebSocket-Endpunkt |
| `SPACETIME_CLI` | lokale Installation | CLI für Provisionierung und Modulupdates |
| `SPACETIME_ADMIN_TOKEN` | lokale CLI-Konfiguration | Optionaler Betreiberzugang; ausschließlich serverseitig |

Für Internetbetrieb einen Reverse Proxy mit HTTPS und WebSocket-Upgrades vor den Node-Prozess setzen und `ALLOWED_ORIGIN` auf die Spiel-Domain setzen. Ein Serverprozess verwaltet bis zu 64 Sektoren. Kein kostenpflichtiger externer Dienst wird benötigt. Schriftarten werden aktuell von Google Fonts geladen; bei fehlender Verbindung greift die Systemschrift.

Der veraltete Node-only-Containerstart wurde entfernt. Ein vollständiger Containerbetrieb mit dauerhafter SpacetimeDB-Instanz, CLI und Betreiberkonfiguration ist noch nicht eingerichtet.

## Galaxie und Kartografie

Beim Erstellen eines Sektors stehen Spiral-, Balkenspiral-, elliptische und Ringgalaxien zur Wahl. Die Größe beträgt 400, 700 oder 1.000 Systeme; drei Hyperlane-Dichten bestimmen Engpässe und alternative Routen. Eine Formvorschau zeigt die Auswahl. Alle Formen sind reproduzierbar aus dem Sektor-Seed, alle Sterne bleiben über ein zusammenhängendes Netz erreichbar. Der Gateway prüft und speichert die Parameter vor der Provisionierung; ein unterbrochener Start verwendet beim Wiederholen dieselben Parameter.

Die Karte verwendet zoomabhängige Marker und kollisionsgeprüfte Beschriftungen mit einem festen Bildschirmbudget. Auswahl, Heimatwelt, Kolonien und besondere Systeme haben Vorrang; normale Schwarze Löcher behalten einen kleinen Marker, Erebus bleibt eine große Landmarke. Sternstaub, Gravitationsfelder und Spezialeffekte folgen den tatsächlichen Systempositionen. Reichsgrenzen bilden benachbarte Besitzflächen ohne innere Trennlinien; neutrale Systeme und getrennte Inseln bleiben getrennt. Das Sechseck in der Kartenleiste schaltet Grenzen ein und aus.

Bestehende Galaxien behalten Positionen, Verbindungen und Spielstände. Nur neu gegründete Sektoren verwenden die neue Erzeugung. Der Gateway muss nach Codeänderungen neu gestartet werden; vorhandene Datenbanken benötigen dafür keine Migration. Echter Fog of War ist noch offen: Die Sternenkarte ist weiterhin öffentlich bekannt, sensible Wirtschafts- und Flottendaten bleiben durch die vorhandenen Server-Sichtbarkeitsregeln geschützt.

## Prüfen

```sh
npm test
npm run backend:test
npm run build
```

Die Tests prüfen Erkundung, Kolonisierung, Besitzschutz, Forschung, Produktion, Sichtbarkeit, Kämpfe, Kolonieausbau und KI. Native Mehrspieler-Verbindungen prüfen zusätzlich private Angebote und Entscheidungen, reservierte Rohstoffe, Krieg/Frieden, tatsächliche Krisenproduktion, Abschirmung, gemeinsame Eindämmung, Hot Joins und Wiederherstellung nach Datenbankabsturz. Gateway-Tests nutzen zufällige Ports und getrennte Datenverzeichnisse; der isolierte Absturztest verwendet Port 3110. [Ereignis-/Projektprüfung](backend/reports/EVENTS.md).

## Umfang dieses Stands

**Natürliche Sternenstürme:** Erkundung ausgewählter Riesensterne entdeckt Ausbrüche mit 120 Tagen Vorwarnung. Für 60 Tage liefern Sonnenkollektoren und Dyson-Anlagen nur 25 % ihrer Energie. Lagezentrum und Systemansicht zeigen den Countdown und die anschließende Erholung. [Ablauf und Prüfungen](backend/reports/STELLAR-WEATHER.md).



**Materiedekompressor:** Nach „Megakonstruktion“ ein Schwarzes Loch untersuchen und dort über das Kontextmenü die Megastruktur verwalten. Ein Schiff errichtet drei Etappen; der Extraktionsring liefert 25, der vollständige Ausbau 75 Mineralien pro vier Spieltage vor Kriseneffekten. Forschungsstationen können parallel bestehen. [Bau und Regeln](backend/reports/DECOMPRESSOR.md).

Eigene untersuchte Systeme können mehrere Planetenkolonien haben: Rechtsklick auf einen bewohnbaren Nebenplaneten → **Planeten besiedeln**. Ein Kolonieschiff fliegt zuerst dorthin und gründet für 80 Energie und 80 Mineralien in zwölf Spieltagen eine neue Welt. Jede Kolonie verwaltet eigene Bevölkerung, Sektoren, Distrikte und Bauaufträge. Wirtschaft, Terraforming, Speziesmodifikation und KI sind angeschlossen; Schildbastionen verstärken das gemeinsame System. Details: [Mehrere Planetenkolonien](backend/reports/PLANET-COLONIES.md).

Dies ist eine spielbare Grundlage mit 1.000 Systemen in neuen Galaxien. Importierte Sektoren behalten ihre bisherige Größe. Kolonieverwaltung, automatische Kämpfe, Flottenverbände und eine strategische KI sind spielbar. Krieg/Frieden und direkter Rohstofftausch sind spielbar. Dauerhafte Handelsrouten/-abkommen, Bündnisse, individuelle Schiffsdesigns, Sound und Accountverwaltung sind noch offen. Spielerplätze bleiben für eine Wiederverbindung reserviert. Die Darstellung ist für Desktop optimiert; schmale Ansichten bieten kompaktere Panels.

Die Systemansicht verwendet eine im Vertex-Shader verformte 3D-Fläche mit Gravitationskonturen, weißglühende Sternkerne, animierte Koronen, farbigen analytischen Lichtschein, direkte Lichtquellen und HDR-Bloom. Die Konturen werden für glatte Nahansichten pro Bildpunkt ausgewertet; der Lichtschein wird bei starker Vergrößerung reduziert. **Echte Radiance Cascades, physikalisch korrekte Raumzeitgeometrie und indirekte Beleuchtung sind noch nicht implementiert.** Umlaufbahnen, Monde und ruhende Schiffsformationen werden lokal anhand der gemeinsamen Spielzeit dargestellt. Individuelle Kampfpositionen werden nur für die geöffnete Gefechtsansicht abonniert, individuelle Schiffsdaten für die Verbandsverwaltung. Weitere Planeten können eigene Bevölkerung und Distrikte erhalten; Monde bleiben mit Außenanlagen bebaubar. Die Siegwertung zählt Systeme. Bei Zerstörung der Sternenbasis gehen Besitz, Kolonien und Anlagen des Systems verloren. Weitere Ausbauschritte stehen in [PLAN.md](PLAN.md).

**Ereignisse und Spezialprojekte:** Das Lagezentrum bündelt einen allgemeinen Pool mit 28 Einträgen, gewichteten Auslösern und Bedingungen für Reich, Spezies, Forschung, Zeit und Systeme. Projekte bieten schwankenden Fortschritt, Phasen und Folgeentscheidungen. Eigene Detailseiten zeigen Dialoge, Bilder, Karten und Protokolle; Ankündigungen machen neue Funde sichtbar. [Inhalte erweitern](shared/events/README.md). Aktuelles Weltformat: **6**, neue Partien erforderlich.

Die automatisierten Tests konzentrieren sich auf zentrale Spielregeln, Wirtschaft, Zustandsübergänge, Besitzschutz, Transport und Speicherung. Einzelne Inhalte, Modelle und reine Layoutdetails erhalten keine eigene Testsuite.
