# SINGULARITY

Ein spielbarer Multiplayer-4X-RTS-Prototyp für den Browser. Inspiriert von interstellarer Strategie, Gravitationskonturen und leuchtenden Raumzeit-Anomalien. Eigenständige Gestaltung, keine Stellaris-Assets.

**Das normale Spiel verwendet SpacetimeDB.** Neue Galaxien enthalten wahlweise 400, 700 oder 1.000 Systeme und bis zu 25 menschliche/KI-Imperien. Wirtschaft, Forschung, Reisen, Kolonisierung, Diplomatie und Gefechte liegen dauerhaft im nativen Backend. Die Node-Schicht vermittelt Lobby, private Vorlagen und Browserzugriff. Der alte Node-Spielserver und automatische Import sind entfernt; bereits übernommene Galaxien und native Sitzungen bleiben erhalten. [Diplomatie und Prüfung](backend/reports/DIPLOMACY.md), [Architektur](backend/README.md), [Ausbauplan](PLAN.md).

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

### Gemeinsam spielen

1. Oben rechts den Sektor öffnen und Raumcode oder Einladungslink kopieren.
2. Im zweiten Browser den Link öffnen, eine Reichsvorlage wählen und beitreten. Bis zu 25 Menschen und KI-Imperien pro Sektor.
3. Für weitere Geräte die vom Dev-Server ausgegebene **LAN-Adresse** anstelle von `localhost` verwenden, etwa `http://192.168.x.x:5173`. Den Einladungslink von dieser Adresse aus kopieren. Die Geräte müssen den Rechner erreichen können.

Die Spielsimulation läuft auf deinem Server. Der Host steuert Pause und Tempo. Wenn er geht, übernimmt der nächste verbundene Spieler. Ohne verbundene Spieler pausiert die Simulation. Beim Wiederverbinden eines zuvor leeren Sektors erhält der erste Spieler die Zeitsteuerung.

## Spielen

Ziel: **8 Kolonien** kontrollieren.

- **Erkunden:** `ISS Horizon` wählen → `Kurs setzen` → `Alpha Centauri`. Nach Ankunft im rechten Panel `System untersuchen` (8 Spielsekunden).
- **Expandieren:** `ISS Genesis` in das untersuchte System schicken → `Kolonie gründen`. Kosten: 80 Energie + 80 Mineralien. Das Kolonieschiff wird nach 12 Spielsekunden zur Kolonie.
- **Wirtschaft:** Kolonien produzieren alle vier Spielsekunden Ressourcen. Eine Bergbaustation kostet 50 Energie + 100 Mineralien und verdoppelt die lokalen Energie- und Mineralienerträge.
- **Raumwerft:** Eigene Kolonie wählen → Raumwerft → Forschungsschiff, Kolonieschiff oder Korvette bauen. Die Warteschlange arbeitet nacheinander; maximal fünf Aufträge.
- **Forschung:** Drei Technologien verbessern Antrieb, Rohstoffproduktion und Kampfkraft. Forschungspunkte werden beim Start verbraucht.
- **Kampf:** Korvetten greifen im selben System Kriegsgegner und deren Verteidigung automatisch an. Friedliche Reiche können einander passieren. Wächter besiegst du mit Korvetten. Fällt eine Kolonialverteidigung, wird das System unabhängig und kann neu kolonisiert werden. Zerstörte Schiffe gehen verloren.
- **Diplomatie:** Handschlag-Symbol links öffnen. Krieg ausdrücklich erklären, Frieden anbieten und als Empfänger annehmen oder ablehnen. Angenommener Frieden beendet gemeinsame Gefechte sofort und schützt 120 Spielsekunden vor erneutem Krieg.
- **Handel:** Energie, Mineralien und Forschung direkt tauschen. Die angebotenen Mengen werden sofort reserviert, der Tausch wird bei Annahme atomar ausgeführt. Ablehnung, Rücknahme, Krieg oder Ablauf erstatten die Reservierung genau einmal. Angebote gelten 60 Spielsekunden; Pause hält Fristen an. Nur die beiden Vertragspartner sehen die Konditionen.
- **Anomalien:** Die erstmalige Untersuchung einer unberührten Anomalie liefert 90 Forschung. Reguläre Untersuchungen liefern 25. Schwarze Löcher und Raumzeitrisse sind nicht kolonisierbar.
- **Ereignisse:** Das Funksymbol links öffnet das **Lagezentrum**. Anomalie-Archive und deine erste neue Außenkolonie bieten Entscheidungen mit sichtbaren Kosten und Erträgen. Nach 90 Spielsekunden wird eine kostenlose Standardoption gewählt. Abgeschlossene Entscheidungen bleiben im Verlauf.
- **Resonanzkaskade:** Nach 180 Spielsekunden beginnt die Vorwarnung; eine Untersuchung des goldenen Risses kann sie früher auslösen. Ohne Eindämmung sinkt die Kolonieproduktion nach 120 weiteren Spielsekunden um 25 %, nach nochmals 120 um 50 %. Die Grundversorgung bleibt erhalten. 120 Energie schützen alle eigenen heutigen und künftigen Kolonien. Ein Stabilisierungspaket kostet 60 Energie und 30 Forschung. Gemeinsam sind `3 + ceil(Imperienzahl / 2)` Pakete erforderlich; spätere Beitritte erhöhen dieses Ziel nicht. Erfolgreiche Eindämmung beendet die Krise und vergütet jeden Beitrag mit 40 Forschung. Fristen, Beiträge, Schutz und Entscheidungen überstehen Pause und Wiederverbindung.
- **Navigation:** Über die Systemsuche Sterne und Kolonien finden und direkt zentrieren. Enter wählt den ersten Treffer. Bei aktiver Zielwahl kann so auch ein Flottenziel gewählt werden.
- **Verbände:** Neue Korvetten verstärken einen passenden eigenen Verband an der Werft. Über **Verband verwalten** einzelne Schiffe auswählen, abteilen und ruhende militärische Verbände am selben Ort vereinen. Im Kampf ist zunächst ein Rückzug erforderlich.
- **Gefechtsansicht:** Status, Verluste, Hülle/Schilde und verursachter Schaden erscheinen als gedrosselte Übersicht. **Gefecht ansehen** öffnet die taktische Systemansicht; beim Verlassen werden die individuellen Kampfbewegungen abbestellt.
- **Systemansicht:** Ein System doppelklicken oder **Systemansicht öffnen** wählen. Sterne, Planeten, Monde, Gasriesen, Asteroiden und Ruinen lassen sich direkt oder über den Systematlas auswählen. Sichtbare Flotten stehen als Schiffsmodelle im System; die Nahansicht zentriert Körper oder Verband. Die Hauptwelt öffnet weiterhin die Kolonieverwaltung.
- **3D-Kamera:** Links ziehen dreht und neigt die Perspektive, rechts ziehen verschiebt sie, das Mausrad zoomt. Die Fadenkreuz-Schaltflächen fokussieren die Auswahl beziehungsweise setzen die Kamera zurück. Hyperlane-Zugänge sind als türkis leuchtende Wurmlöcher in die Raumzeitfläche eingebettet. In der aktuellen Experimentvariante stehen die Öffnungen senkrecht, mit ihrem Mittelpunkt auf Höhe der lokalen Raumzeitfläche. Die Fläche und ihre Konturen biegen sich weich zum Portal und laufen hinter ihm als längere, flachere Rampe nach außen aus; der animierte Tunnel führt ebenfalls nach außen. Die Zugänge liegen nahe dem Systemrand. Ihre verlängerten Routen führen durch die Mittelachse der Trichter und schließen weiter außen weich an die lokale Fläche an; die Trichterwände verdecken dahinterliegende Linienabschnitte. Ihre Richtung entspricht den echten Verbindungen; eng benachbarte Öffnungen sind unter Berücksichtigung ihrer Ausläufe radial versetzt. Ein Klick auf den Zugang oder seine seitliche Beschriftung öffnet das Nachbarsystem. **Konturen** und **Licht** schalten Gravitationslinien beziehungsweise Bloom um.
- **Systemanlagen:** Nach Untersuchung im eigenen Sternsystem einen Körper auswählen und eine passende Anlage errichten. Sonnenkollektoren liefern Energie, Förderanlagen Mineralien, Forschungsstationen Forschung; Außenposten und Atmosphärenkollektoren liefern gemischte Erträge. Jeder Körper hat einen Anlagenplatz mit drei Ausbaustufen. Mehrere Körper können parallel bebaut werden, ein Abbruch erstattet einmalig 50 %. An unbesetzten Rissen und Schwarzen Löchern ermöglicht eine eigene Flotte vor Ort den Bau. Anlagen liefern alle vier Spielsekunden Erträge, unterliegen der Resonanzkrise und erscheinen separat in der Wirtschaftsübersicht.

Die Sternenkarte ist öffentlich. Untersuchte Systeme zeigen ihre Rohstoffe. Fremde Flotten sind nur dort sichtbar, wo eigene Flotten oder Kolonien sind. Territorien und Koloniezahlen sind öffentlich.

**Hyperlane-Lichtstrom:** Hinter den Portalen verlaufen feine türkisfarbene Lichtfäden mit weichem Saum. Auf den geraden Austritt folgt ein flacher Bogen; sein Ende und seine Endrichtung liegen auf der tatsächlichen galaktischen Zielrichtung. Die Spuren verjüngen sich und verblassen bis etwa 55 % über den Rand der Raumzeitfläche hinaus. Radial versetzte Zugänge erhalten entsprechend unterschiedliche Spurlängen. Die Raumzeitfläche geht auf der Systemseite über einen breiteren, flacheren Einflussbereich in die Öffnungen über. Wenige langsam nach außen wandernde Impulse folgen der Kurve. Die Breite passt sich dem Zoom an; verdeckte Abschnitte bleiben hinter den Trichterwänden verborgen.

**Sternvielfalt:** Die Systemansicht unterscheidet Spektralklassen, Riesensterne, Neutronensterne und Pulsare. Schwarze Löcher verwenden einen [Schwarzschild-Shader](backend/reports/BLACK-HOLE-SHADER.md) mit gekrümmten Lichtwegen, mehrfach abgebildeter Akkretionsscheibe und Dopplerverschiebung; neue Galaxien enthalten auch seltene Quasare mit polaren Jets. Die Suche versteht Begriffe wie „O-Klasse“, „Neutronenstern“ und „Quasar“. Sternoberflächen und feine Koronen reduzieren die weiße Überstrahlung, während die Raumbeleuchtung erhalten bleibt. [Umsetzung und Prüfung](backend/reports/STELLAR-VARIETY.md).

**Systemverteilung:** Primäre Umlaufbahnen liegen weiter außerhalb des Zentrums, in Sternsystemen bei etwa 462 bis 1.165 Karteneinheiten. Monde behalten ihre lokalen Bahnen. Die Übersichtskamera berücksichtigt die größere Ausdehnung. Vollständige Asteroidengürtel sind selten (8 % Seed-Wahrscheinlichkeit): feine, langsam rotierende Lichtfragmente in Perlweiß und Lavendel, verbunden durch dezente, unterbrochene Bögen. Übrige Systeme enthalten kompakte Rohstofffragmente. Gürtel und auswählbare Fragmente erzeugen keine Gravitationstrichter oder Lichtflecken auf der Raumzeitebene. Häufigkeit und Aussehen bleiben pro System stabil. Bestehende Anlagenplätze bleiben erhalten; die Darstellung gilt auch für vorhandene Spielstände.

### Neu in Alpha 0.2: Kolonien & autonome Imperien

Eigene Welt auswählen → **Kolonie verwalten**. Alternativ das Planetensymbol links verwenden. Jede Welt hat eine wachsende Bevölkerung und begrenzte Distriktplätze. Pro Kolonie kann ein Ausbau gleichzeitig laufen, unabhängig von der Raumwerft.

| Ausbau | Ertrag pro Stufe | Erste Stufe | Bauzeit |
|---|---|---|---|
| Fusionsreaktor | +4 Energie / Zyklus | 50 Energie, 100 Mineralien | 16 s |
| Orbitalindustrie | +4 Mineralien / Zyklus | 80 Energie, 80 Mineralien | 18 s |
| Quantenlabor | +3 Forschung / Zyklus | 90 Energie, 120 Mineralien | 22 s |
| Schildbastion | +40 Verteidigung, +1 Hüllenreparatur / s | 60 Energie, 120 Mineralien | 20 s |

Jeder Ausbau hat drei Stufen, die jeweils einen Distrikt belegen. Weitere Stufen kosten 65 % der Grundkosten zusätzlich pro bestehender Stufe und brauchen jeweils acht Sekunden länger. Abbrechen erstattet einmalig 50 % der bezahlten Kosten.

Hauptwelten starten mit 6 Mrd. Einwohnern, neue Kolonien mit 2 Mrd. Die Bevölkerung wächst alle 240 Spielsekunden um 1 Mrd., bis maximal 12 Mrd. Die Distriktkapazität ist `4 + floor(Bevölkerung / 2)`, maximal zehn. Bevölkerung repräsentiert in diesem Stand das Ausbaupotenzial; eine Arbeitsplatzzuteilung gibt es noch nicht.

**Schwerpunkte:** Ausgewogen lässt alle Erträge unverändert. Energie, Industrie oder Forschung erhöhen den jeweiligen Ertrag um 40 % und senken die beiden anderen um 15 %. Bergbau verdoppelt die natürlichen Energie-/Mineralienvorkommen; Ausbau-Erträge werden anschließend addiert. Danach folgen Schwerpunkt und Technologiebonus. Die Wirtschaftsübersicht (auf eine Ressource oben klicken) zeigt jede Kolonie, die Grundversorgung und die Summe.

**Reparatur:** In eigenen, feindfreien Systemen regenerieren Schiffe 1,5 Hülle/s plus 1 pro Bastionstufe. Kolonialverteidigung regeneriert 0,75/s bis zum aktuellen Maximum. Bei Verlust einer Kolonie gehen Infrastruktur und planetare Bauaufträge verloren. Zivile Routen vermeiden feindliche Verteidigung. Untersuchung und Kolonisierung warten bei feindlichen Korvetten im System.

**KI:** Multiplayer-Dialog → **KI-Imperium hinzufügen**. Nur der Host kann freie Plätze mit KI besetzen. Die KI erkundet, kolonisiert, forscht, baut ihre Wirtschaft aus und führt Korvettenverbände. Es gelten dieselben Befehle, Kosten und Produktionsregeln wie für Menschen. Sie greift nur erklärte Kriegsgegner an und erklärt derzeit nicht selbst Krieg. Friedensangebote nimmt sie an; bezahlbare Tauschgeschäfte akzeptiert sie ab gleichem Wert (Energie 1, Mineralien 1,2, Forschung 2). Eine differenziertere Außenpolitik ist ein späterer Ausbauschritt.

KI-Imperien pausieren mit dem Sektor und halten einen menschenleeren Raum nicht aktiv. Sie können wie Menschen durch acht Kolonien gewinnen. Die KI wird bestehenden Räumen nur auf Host-Befehl hinzugefügt.

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

- `src/`: React + TypeScript, HTML/CSS-Kommandopanels; Canvas-Overlay für Sterne, Hyperraumverbindungen und Flotten.
- `src/GalaxyMap.tsx`: Three.js-Shader für Rauschen, Gravitationskonturen und Anomalien; Canvas-Fallback. Strategische Anzeige derzeit auf 30 FPS begrenzt, mit lokaler Reiseinterpolation. `LabScene.tsx` zeichnet geöffnete Gefechte mit Instancing ohne diese Begrenzung. Die gemeldeten 165 FPS waren die Displaygrenze des Nutzers, keine gemessene Leistungsobergrenze.
- `shared/game.ts`: reine Spielregeln, Wegsuche, Produktion, Bau, Forschung, Kolonisierung, Sichtbarkeit und gleichzeitige Schadensberechnung.
- `shared/colonies.ts`: additive Spielstandmigration, Bevölkerung, Ausbauten, Schwerpunkte und einheitliche Produktionsberechnung. `src/ColonyManager.tsx` enthält die Kolonieverwaltung.
- `spacetimedb/src/game-*.ts`: Native Spieltabellen, Reducer, Sichtbarkeit, Produktion, Kolonien, Reichsänderungen und KI. `commands.ts`, `rules.ts` und `simulation.ts` teilen das geprüfte Flotten-/Gefechtsfundament mit dem Labor.
- `server/index.ts`, `nativeGateway.ts`, `nativeProxy.ts`: Private Vorlagenbibliothek, einmalige Sitzplatz-Tickets, native Galaxie-Provisionierung, statische Dateien und WebSocket-Weiterleitung. Kein eigener Spieltick, kein Welt-Snapshot-Versand und keine alten Sitzungs-/Befehlswege.
- `backend/game-client.ts`: Projektion der berechtigten Abonnements in das React-Spielmodell. Kein Versand vollständiger Weltzustände durch Node für native Partien.
- `.spacetime/data/`: Dauerhafte SpacetimeDB-Daten. `data/native-sectors.json`: Zuordnung der Raumcodes. Alte Node-Speicher wurden einmalig nach `data/archive/node-backend-2026-09-05/` verschoben und werden nicht mehr geladen oder fortgeschrieben. `data/empire-libraries.json` enthält die private Vorlagenbibliothek.

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

Die Tests prüfen Erkundung, Kolonisierung, Besitzschutz, Forschung, Produktion, Sichtbarkeit, Kämpfe, Kolonieausbau und KI. Native Mehrspieler-Verbindungen prüfen zusätzlich private Angebote und Entscheidungen, reservierte Rohstoffe, Krieg/Frieden, tatsächliche Krisenproduktion, Abschirmung, gemeinsame Eindämmung, Hot Joins und Wiederherstellung nach Datenbankabsturz. Gateway-Tests nutzen zufällige Ports und getrennte Datenverzeichnisse; der isolierte Absturztest verwendet Port 3110. [Ereignis-/Krisenprüfung](backend/reports/STORIES.md).

## Umfang dieses Stands

Dies ist eine spielbare Grundlage mit 1.000 Systemen in neuen Galaxien. Importierte Sektoren behalten ihre bisherige Größe. Kolonieverwaltung, automatische Kämpfe, Flottenverbände und eine strategische KI sind spielbar. Krieg/Frieden und direkter Rohstofftausch sind spielbar. Dauerhafte Handelsrouten/-abkommen, Bündnisse, individuelle Schiffsdesigns, Sound und Accountverwaltung sind noch offen. Spielerplätze bleiben für eine Wiederverbindung reserviert. Die Darstellung ist für Desktop optimiert; schmale Ansichten bieten kompaktere Panels.

Die Systemansicht verwendet eine im Vertex-Shader verformte 3D-Fläche mit Gravitationskonturen, weißglühende Sternkerne, animierte Koronen, farbigen analytischen Lichtschein, direkte Lichtquellen und HDR-Bloom. Die Konturen werden für glatte Nahansichten pro Bildpunkt ausgewertet; der Lichtschein wird bei starker Vergrößerung reduziert. **Echte Radiance Cascades, physikalisch korrekte Raumzeitgeometrie und indirekte Beleuchtung sind noch nicht implementiert.** Umlaufbahnen, Monde und ruhende Schiffsformationen werden lokal anhand der gemeinsamen Spielzeit dargestellt. Individuelle Kampfpositionen werden nur für die geöffnete Gefechtsansicht abonniert, individuelle Schiffsdaten für die Verbandsverwaltung. Weitere Welten und Monde sind mit Außenanlagen bebaubar; Bevölkerung, Distrikte und Siegwertung bleiben in diesem Stand an der Hauptkolonie des Systems. Bei Verlust einer Hauptkolonie werden ihre Systemanlagen zerstört. Weitere Ausbauschritte stehen in [PLAN.md](PLAN.md).
