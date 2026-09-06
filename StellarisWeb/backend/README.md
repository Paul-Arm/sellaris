# SINGULARITY · Backend-Fundament

Das normale Spiel und das getrennte Lastlabor verwenden **SpacetimeDB 2.10.0**, ein TypeScript-Modul und generierte Clientbindungen. React und Three.js bleiben erhalten. Die geprüfte Spielmigration ist in [GAME-MIGRATION.md](reports/GAME-MIGRATION.md) beschrieben. Die folgenden Laborszenarien bleiben unabhängig von normalen Galaxien; ihre Messberichte sind historische Messpunkte des Simulationsfundaments.

## Lokal starten

Node.js 22.12+ und SpacetimeDB 2.10.0 werden benötigt. Die geprüfte Umgebung ist Windows mit Node 24. Für andere Systeme die offizielle CLI installieren und bei Bedarf `SPACETIME_CLI` auf die ausführbare Datei setzen.

```powershell
npm ci
npm run backend:setup
npm run backend:start
```

`backend:setup` lädt die offizielle Windows-Version in `.tools/spacetime`, prüft einen vom Release gelieferten SHA-256-Digest und installiert die Modul-Abhängigkeiten. Keine globale Installation. Der Server bindet standardmäßig an **127.0.0.1:3100**. Daten und lokale Authentifizierungsschlüssel liegen unter `.spacetime/` und sind aus der Versionsverwaltung ausgeschlossen.

In einem zweiten Terminal:

Für das normale Spiel genügen `npm run backend:build` und `npm run dev`. Der Gateway provisioniert die Galaxie beim Erstellen. Der alte Node-Spielserver und automatische Import sind entfernt; native Sitzungen werden direkt in SpacetimeDB wiederaufgenommen. Es werden keine Labor-Schiffe oder Labor-Imperien in normale Partien kopiert.

Nur für ein zusätzliches Lastlabor:

```powershell
npm run backend:build
npm run backend:publish -- singularity-lab
npm run backend:seed -- singularity-lab large
npm run dev
```

Das Labor öffnen: **http://localhost:5173/lab**. Nach `npm run build` liefert der bestehende Server dieselbe Seite unter **http://localhost:3001/lab**. Datenbanknamen eingeben, freies Imperium wählen und verbinden. Im Labor werden freie KI-Imperien durch einen Beitritt übernommen; das ist noch keine Produktions-Lobby. Sitzungstoken bleiben pro Tab und Datenbank erhalten. Der Reconnect-Knopf stellt die Identität und die autoritativen Daten wieder her.

Die hier vorbereitete Demo heißt **`singularity-foundation`**: [Labor öffnen](http://localhost:3001/lab?database=singularity-foundation&empire=1), als Imperium 1 verbinden und **Fortsetzen** wählen. Sie enthält 75.000 ursprüngliche Schiffe und eine Schlacht mit ursprünglich 3.000 Teilnehmern und ist nach der Prüfung pausiert. Die Messsitzung verwendet Imperium 2; Imperium 1 wurde für den Nutzer freigehalten.

Die Sidebar zeigt Gefechtsstatus, gebundene Schiffe, Verluste, verbleibende Hülle/Schilde und tatsächlich verursachten HP-Schaden pro Seite. Mit **Gefecht ansehen** werden einzelne Kampfteilnehmer geladen; nur innerhalb dieser Ansicht lädt ein Klick auf eine eigene Flotte auch deren Schiffsdaten. Zurück in der **Galaxie** wird das Detailabonnement bestätigt beendet und sein Cache geleert. Ein Reconnect startet ebenfalls mit der Übersicht. Der Autopilot kann für das eigene Imperium aktiviert werden. Der Mensch in Imperium 1 und der Datenbankbetreiber dürfen pausieren; andere Imperien dürfen die gemeinsame Uhr nicht ändern.

```powershell
npm run backend:clock -- singularity-lab pause
npm run backend:clock -- singularity-lab resume 1
```

Eine Datenbank kann nur einmal konfiguriert/gefüllt werden. Erneutes Seeden setzt vorhandene Daten **nicht** zurück. Für ein anderes Szenario einen neuen Namen veröffentlichen. Der Seed-Cursor pro Imperium ist gespeichert; `seed_ships` nimmt erwarteten Offset und höchstens 1.000 Schiffe pro Transaktion entgegen. Bei unterbrochener Erstbefüllung kann der Betreiber den gespeicherten Cursor abfragen und die verbleibenden Batches fortsetzen; das einfache `backend:seed`-Kommando ist ein Erstbefüllungswerkzeug.

## Daten und Verantwortlichkeiten

Eine Datenbank entspricht einer Galaxie. Mehrere Galaxien teilen keine privaten Spieltabellen.

| Tabelle | Inhalt / Zugriff |
|---|---|
| `star`, `empire_summary` | Öffentliche Sternenkarte, Territorien und Imperiumsnamen |
| `clock`, `scenario` | Gemeinsame Spieluhr, Szenariokonfiguration, Schema-Version |
| `fleet` | Verband, Mitgliederzahl, Route, Auftrag, Formation, Reiseanker, Gefecht; privat |
| `ship` | Individuelle Hülle, Schilde, Ausrüstung, Waffen, Erfahrung, Fähigkeiten, Flottenzugehörigkeit; privat |
| `arrival` | Flotten-ID und indizierter Ankunftszeitpunkt; privat |
| `battle`, `participant` | Dauerhafter Gefechtsfortschritt, Verluste, Positionen, Geschwindigkeiten, Ziele und Waffenzyklen; privat |
| `battle_report` | Private effektive Schadenszähler und gespeicherte HP-Zusammenfassung je Gefecht; nur die gedrosselte Zusammenfassung wird projiziert |
| `colony`, `cohort`, `empire` | Wirtschaft, Pop-Gruppen und Ressourcen; privat |
| `job` | Forschungs-/Bauauftrag, geleistete Arbeit, Gesamtarbeit, Rate, Abschlusszeit, Status; privat |
| `treaty`, `decision`, `trade`, `crisis` | Dauerhafte Erweiterungspunkte mit Phase, Zuständigkeit und Fristen; nur die öffentliche Krise ist direkt öffentlich |
| `membership`, `focus`, `command_quota` | Identität/Berechtigung, gewählte Details, Befehlsrate; privat |
| `*_schedule`, `runtime` | Persistente geplante Aufrufe, Fortschrittsmarken und Diagnosewerte; privat |

`spacetimedb/src/tables.ts` enthält Schema und Indizes, `rules.ts` die wiederverwendbaren Regeln, `commands.ts` die autorisierten Befehle, `simulation.ts` die geplante Simulation, `views.ts` die Zugriffsgrenzen und `seed.ts` die Testweltgenerierung. `backend/domain.ts` enthält transportunabhängige Mathematik und die Szenarien. `backend/module_bindings/` wird ausschließlich von der offiziellen CLI erzeugt.

### Bewegung und Gefechte

Außerhalb eines Kampfes hat ein Schiff **keine eigene strategische Position**. Der Client interpoliert den Verband aus Start-/Zielpunkt und Abflug-/Ankunftsspielzeit. Kursänderungen schreiben Flotte und Ankunftsindex. Die einzelnen Schiffstabellen werden dabei nicht verändert – das wird mit einer echten Subscription getestet.

Aufteilen ist nur mit einem nichtleeren echten Teil der Schiffe einer ruhenden eigenen Flotte erlaubt. Auch eine Flotte mit einem Schiff verwendet dasselbe Modell. Zusammenführen verlangt zwei ruhende eigene Flotten im selben System; Schiffsmitgliedschaften, Flottensummen und betroffene Bauaufträge wechseln in einer Transaktion. Rückzug entfernt die Kampfteilnehmer und bereinigt ihre Zielreferenzen atomar. Kampfeintritt ist als wiederverwendbare serverseitige Funktion umgesetzt und wird beim Aktivieren des Lastszenarios atomar ausgeführt. Automatische strategische Abfang-/Kriegserklärungsregeln sind noch nicht angebunden.

Gefechte verwenden lineare Zielzuweisung statt eines Vergleichs jedes Schiffes mit jedem anderen. Schaden wird pro Schritt gleichzeitig angewendet. Gegenwärtig sind es zwei Seiten, einfache Flugmanöver, eine aggregierte Waffenkadenz, Schilde und Panzerung. Projektilphysik, Hindernisnavigation, Reichweiten-/Sichtlinienprüfung, getrennte Waffenzyklen je Waffenplatz und taktische Entscheidungsbäume sind **keine** Lastbestandteile dieses Prototyps.

### Taktung und Zeit

| System | Aufrufabstand in Echtzeit | Verarbeitung |
|---|---|---|
| Strategische Bewegung / Aufträge | 250 ms | Nur fällige Ankünfte und Jobabschlüsse über Indizes |
| Wirtschaft | 1 s | Ganze Produktionszyklen von vier Spielsekunden; aggregierte Pop-Erträge |
| KI | 200 ms | Höchstens vier fällige Planer pro Aufruf; individuelle, versetzte Fünf-Spielsekunden-Fristen |
| Kampf | 100 ms | Schritte von 200 Spiel-ms; höchstens vier Nachholschritte pro Gefecht/Aufruf |
| Gefechtsübersicht | Frühestens nach 1 s | Zusammenfassung aus dem Kampf, unabhängig vom Spieltempo; Rückzug, Ende und Pause aktualisieren sofort |

Die KI im Lastprototyp patrouilliert mit bis zu acht bereiten Flotten je Entscheidung. Sie ist eine repräsentative Grundlast, noch keine vollständige 4X-KI.

Die normale Spiel-KI in `game-ai.ts` nutzt stattdessen dieselben validierten Spielbefehle wie Menschen: eine rotierende Flottenentscheidung und eine unabhängige Wirtschaftsentscheidung pro Planungsbesuch. Der normale Spieleinstieg unterstützt 25 Plätze; das Labor darf seine Lastgrößen unabhängig konfigurieren.

Eine gemeinsame Uhr steuert 0,5×, 1×, 2× oder 4× sowie Pause. Kurse und Aufträge bleiben auf der Spielzeitachse; ein Tempowechsel schreibt deshalb nicht alle Schiffe um. Jobfortschritt wird aus Arbeitsstand, Zeitpunkt und Rate rekonstruiert. Forschung verbessert Produktion und Auftragsraten; vor einem Ratenwechsel wird bereits geleistete Arbeit abgerechnet. Fertige Schiffe werden nur einer passenden gedockten Flotte zugewiesen, sonst einer neuen Flotte an einer eigenen Kolonie. Abschlüsse sind dauerhaft markiert und werden nicht erneut ausgeführt.

Die Uhr verwendet einen serverseitigen Zeitanker und läuft im Prototyp auch ohne verbundene Spieler weiter. Nach **ungeplantem Ausfall ohne vorherige Pause** verstreicht die Zeit zwischen den Ankern weiter: Produktion und Ankünfte holen auf; Gefechte holen begrenzt nach, und der Rückstand bleibt sichtbar. Für reguläres Stoppen/Updates zuerst `backend:clock … pause` verwenden. Automatische Ausfallpause, zulässiger maximaler Nachholrückstand und Befehlsannahme während langer Wiederherstellung sind vor einem Produktionsbetrieb noch festzulegen. Auf verschiedenen Geräten braucht die visuelle Extrapolation außerdem eine gemessene Serverzeitabweichung; derzeit setzt das Labor eine passende lokale Wanduhr voraus. Spielbefehle übernehmen keine Clientzeit.

Normale Partien pausieren automatisch mit dem letzten getrennten Spieler und setzen nur eine solche automatische Pause beim Wiederbeitritt fort. Der Host wechselt zum nächsten verbundenen Spieler. Mehrere Verbindungen derselben Identität werden gezählt; ein einzelner geschlossener Tab entfernt keine weiterhin verbundene Identität. Ein erzwungener Serverneustart mit vorher pausierter Partie wurde auf erhaltene Spielstände und bereinigte Verbindungen geprüft. Längerer Ausfall während laufender Simulation und Geräte mit stark abweichender Wanduhr sind weiterhin gesonderte Betriebsfälle.

### Sichtbarkeit und Hot Joins

Private Tabellen können normale Clients weder per SQL noch per Subscription lesen. Views leiten das eigene Imperium ausschließlich aus der vom Server geprüften Identität ab. Die öffentliche Sternenkarte ist absichtlich bekannt. Sensorzugriff besteht an eigenen Kolonien und an Systemen mit eigenen anwesenden Flotten; Hyperraumflug gibt keine Fernsicht am Ziel.

- **Galaxie:** `galaxy_fleets` liefert eigene sowie aktuell sichtbare fremde Flotten, ohne komplette Auftrags-/Routenlisten oder Schiffsausrüstung.
- **Flottendetail:** `fleet_ships` liefert nur die ausgewählte eigene Flotte. Fremde IDs werden bereits beim Fokuswechsel abgewiesen und zusätzlich in der View geprüft.
- **Gefechtsübersicht:** `visible_battle_summaries` liefert berechtigte Status-/HP-Zusammenfassungen und eigene Gefechtshistorie. Die Galaxie abonniert weder Teilnehmer noch die laufende Gefechtsuhr. Die View projiziert gespeicherte Zusammenfassungen ohne Teilnehmer-Scan je Betrachter. Die Simulation läuft auch ohne Detailzuschauer weiter.
- **Geöffnetes Gefecht:** `focused_battle` liefert dessen laufende Uhr. Das Labor abonniert gemeinsam `battle_roster` (Zugehörigkeit), `battle_motion` (Position/Geschwindigkeit), `battle_vitals` (Hülle, Schild, Ziel, nächster Waffenzyklus) und `fleet_ships`. Jede View prüft unabhängig den berechtigten Fokus. Unveränderte Zugehörigkeit und Kampfwerte werden nicht mit jeder Bewegung erneut übertragen. `BattleDetailSubscription` serialisiert Öffnen/Schließen und wartet beim Verlassen auf das bestätigte Abbestellen. Eine künftige Systemansicht kann denselben Abonnement-Lebenszyklus verwenden. `visible_battles` und `battle_participants` bleiben für bestehende Diagnoseclients erhalten. Frühere Teilnehmerimperien behalten Zugang zu diesem Gefecht; das ist die aktuelle Zuschauerregel.
- **Wirtschaft:** Ressourcen, Kolonien, Pop-Gruppen, Aufträge, Entscheidungen, Handel und Verträge sind auf das eigene Imperium beschränkt.

Der Schadensvergleich zählt tatsächlich entfernte Hüllen-/Schild-HP nach Panzerung und ohne Overkill. Rückzüge vermindern die im Gefecht gebundenen HP und Schiffe, zählen aber nicht als Schaden oder Verlust. Beim Kampfende bleibt die letzte Zusammenfassung samt Sieger und überlebenden HP erhalten. Eine Siegchance wird derzeit nicht berechnet; dafür braucht das Kampfmodell erst belastbare Vorhersagen.

Nach einem Modul-Update vorhandener Datenbanken initialisiert `npm run backend:initialize-reports -- DATENBANK` ausschließlich fehlende Berichte. Das verändert weder Spieluhr noch Schiffe. Bei bereits laufenden Gefechten beginnt die Schadensmessung am angezeigten **Messbeginn**; ältere Schäden werden nicht rekonstruiert. Vor dem Update abgeschlossene Gefechte zeigen Status/Ergebnis und ausdrücklich keine historischen HP-Daten. Erneutes Initialisieren setzt keine Zähler zurück.

Die Ansichtstrennung wird mit 25 Spieleridentitäten und 3.000 Kampfteilnehmern gemessen: [Messbericht Übersicht/Gefecht](reports/OVERVIEW.md). Der ältere [Transportvergleich](reports/NETWORK.md) dokumentiert den Stand vor dieser zusätzlichen Drosselung.

Zusammengehörige Initialabonnements werden mit einem `subscribe([...])` angelegt und erst nach `onApplied` als bereit betrachtet. SpacetimeDB liefert nachfolgende Transaktionen atomar in den SDK-Cache. Rendering und UI lesen diesen Cache; sie rekonstruieren keine fehlenden Spielzustände aus flüchtigen Effekten. Flüchtige Effekt-Events werden hier noch nicht benötigt.

### Kompakter Gefechtstransport

Die Optimierung ändert ausschließlich die übertragenen Ansichten; die privaten Simulationszeilen, f32-Positionen, Ziele, Waffentermine und die Kampftaktung bleiben gleich. Es gibt keine Quantisierung und keine ausgelassenen Simulationsschritte. Neue Views sind additiv und benötigen keine Konvertierung gespeicherter Teilnehmer. Vor Verwendung des aktualisierten Labors bestehende Labordatenbanken mit `npm run backend:publish -- <name>` aktualisieren; bestehende Saves niemals löschen oder neu seeden.

Browser und Lastclient verwenden standardmäßig Gzip auf SpacetimeDB-Nachrichtenebene. `backend/transport.ts` entpackt komprimierte und unkomprimierte Nachrichten in Empfangsreihenfolge. Ein kleines Folgeupdate darf einen großen Initialsnapshot nicht überholen. Bei beschädigten Daten oder mehr als 64 MiB Empfangsrückstand/entpackter Einzelnachricht wird die Verbindung geschlossen; keine Transaktion wird still übersprungen. Wiederverbinden lädt den aktuellen konsistenten Snapshot. Diese Transportgrenze ist keine festgelegte Schiffsobergrenze. Ein automatischer Reconnect im Labor ist weiterhin ausstehend.

Die Telemetrie unterscheidet tatsächliche Nachrichtenbytes auf der Leitung, entpackte Bytes, Entpackdauer und Spitzenwert des Empfangsrückstands. Die Anzeige im Browser verwendet **KiB/s vor dem Entpacken**. Die feste 165-Hz-Begrenzung der Nutzerdarstellung bleibt als FPS-Cap eingeordnet.

## Nachmessen

```powershell
npm run backend:check
npm run backend:build
npm run backend:test
npm run backend:bench -- --profile=standard --seconds=60
npm run backend:bench -- --profile=large --seconds=60
```

Integrationstests benötigen den lokalen Server auf Port 3100. Der Neustarttest startet und beendet ausschließlich seinen eigenen Prozess auf Port 3110 und benutzt ein separates Datenverzeichnis. Beide Tests veröffentlichen eigene neue Datenbanken. Sie verändern keine bestehenden Spielsektoren. Abgeschlossene Testdatenbanken werden pausiert und zur Inspektion erhalten.

| Profil | Systeme | Imperien | Flotten | Schiffe | Gefechte | Teilnehmer je Gefecht | Kolonien / Pop-Kohorten / Pops |
|---|---:|---:|---:|---:|---:|---:|---:|
| `standard` | 1.000 | 25 | 1.250 | 25.000 | 5 | 200 | 250 / 1.000 / 25.000 |
| `large` | 1.000 | 25 | 1.250 | 75.000 | 5 | 600 | 250 / 1.000 / 100.000 |
| `smoke` | 100 | 4 | 40 | 400 | 1 | 40 | 40 / 80 / 800 |

50 der 1.250 regulären Flotten sind in den fünf Gefechten gebunden. Die übrigen 1.200 starten auf einer Route. Es sind 25 unabhängig authentifizierte Clients verbunden, alle 25 Imperien nutzen den Autopiloten. Fünf Clients abonnieren zusätzlich ein Gefecht und eine Flotte. Alle 2,5 Sekunden wird eine Verbindung getrennt und mit derselben Identität neu aufgebaut. Die restlichen Clients und die Simulation laufen dabei weiter.

Eigene Lastgrößen werden per JSON-Datei übergeben; weder 25.000 noch 75.000 ist eine festgelegte Schiffsobergrenze:

```powershell
npm run backend:bench -- --scenario=backend/scenarios/battle-heavy.json --profile=battle-heavy --seconds=120
```

Alle Größen sind offen konfigurierbar. Der aktuelle Lastgenerator verlangt unterschiedliche Imperienpaare je Testgefecht sowie mindestens eine Reserveflotte pro Imperium. Die einzige Gesamt-ID-Grenze ist der aktuelle u32-Adressraum. Seed-Batches und einzelne Befehlslisten sind aus Transaktions-/Eingabegründen begrenzt; dies sind keine Flotten-/Imperiumsobergrenzen des geplanten Spiels.

Reports stehen unter `backend/reports/`. Gemessen werden:

- Beitritt/Reconnect einschließlich Authentifizierung, Fokus und vollständig angewandtem Initialsnapshot.
- Echte BSATN-WebSocket-Nachrichtenbytes vor dem Entpacken; ohne TCP/TLS-Frame- und HTTP-Auth-Overhead. Die Dauerwerte enthalten die wiederholten Reconnect-Snapshots. Die ursprünglichen Reports nutzen Vollansicht/keine Kompression; neue Läufe dokumentieren das gewählte Format und die Kompression ausdrücklich.
- Native SpacetimeDB-Histogramme für Reducer **plus** Subscription-Auswertung. p95 wird als obere Histogrammklassengrenze angegeben, nicht als punktgenauer Wert. Queue-Wartezeiten liegen für geplante Reducer gemeinsam vor.
- Sichtbarer Simulationsrückstand und native Tabellen-/Indexgrößen. Fehlende native Messwerte erscheinen als `null`.
- Hardware, Node-Version, Quellcode-Fingerprint und Messdauer. Browser-FPS wird separat im sichtbaren Labor erfasst.

Die Three.js-Probe zeichnet Flotten bzw. ausgewählte Kampfteilnehmer instanziert. Das Gravitationsfeld wird beim Szenenaufbau einmal auf einem 96×96-Raster vorbereitet; der Fragmentshader liest nur die Textur. React aktualisiert Detailpanels zweimal pro Sekunde. Der FPS-Test ist ein Test dieser Laborszene, nicht des vollständigen bisherigen Spiels mit allen zukünftigen Effekten.

### Netzwerkvergleich reproduzieren

Gesamte Vergleichsreihe mit vier Varianten der Einzelschlacht und anschließend fünf verschiedenen Gefechten:

```powershell
node backend/compare-network.mjs 60
node backend/report-network.mjs
```

Einzelne Varianten:

```powershell
npm run backend:bench -- --scenario=backend/scenarios/battle-heavy.json --profile=network-heavy --detail=legacy --compression=none --seconds=60
npm run backend:bench -- --scenario=backend/scenarios/battle-heavy.json --profile=network-heavy --detail=compact --compression=none --seconds=60
npm run backend:bench -- --scenario=backend/scenarios/battle-heavy.json --profile=network-heavy --detail=compact --compression=gzip --seconds=60
npm run backend:bench -- --scenario=backend/scenarios/battle-heavy.json --profile=network-heavy --detail=compact --compression=gzip --battle-copies=10 --seconds=60
```

Die Läufe nacheinander ausführen. Andere große Testwelten vorher pausieren. `--battle-copies=10` öffnet insgesamt zehn Verbindungen je beobachtendem Spieler, mit derselben berechtigten Identität. Bei einer Einzelschlacht ergeben sich **34 Verbindungen mit 25 verschiedenen Identitäten**, zehn davon mit Gefechtsdetails. Dies misst zusätzliche Empfänger und gemeinsame View-Auswertung; es simuliert keine zehn unabhängig berechtigten Zuschauer. Ein zusätzlicher Test mit vielen unterschiedlichen Zuschaueridentitäten und entsprechenden Spielregeln steht aus. Datenbanknamen sind pro Lauf eindeutig; Reports verwenden Profil, Format, Kompression und Kopienzahl im Dateinamen.

Messungen: [ursprüngliche Lastprobe](reports/RESULTS.md), [Netzwerkvergleich](reports/NETWORK.md).

## Produktionsspiel und weitere Belastungsproben

Die normale Spielmigration ist abgeschlossen; die Lastmessungen bleiben historische Messpunkte und keine Garantie für jede spätere Mechanik. Maximale Einzelschlacht, gleichzeitig aktive Gefechte, WAN-Verbindungen und gewünschte Pop-Tiefe müssen weiterhin auf der Zielhardware erprobt werden.

Diplomatie verwendet `game_relation` für öffentliche Kriegs-/Friedenszustände sowie die private `treaty`-Tabelle mit `game_offer` für reservierte Tauschbedingungen. `my_game_offers` ist nach beiden beteiligten Imperien gefiltert. Annahme und Erstattungen sind transaktional; Fristen verwenden die autoritative Spielzeit. Der Detailstrom für Schiffe/Gefechte wird dabei nicht erweitert. [Prüfbericht](reports/DIPLOMACY.md).

`backend:update-games` pausiert jede registrierte Galaxie vor Veröffentlichung, initialisiert fehlende Beziehungen für bestehende Gefechte und stellt das bisherige Tempo/Pause wieder her. Labordatenbanken werden nicht aktualisiert oder zurückgesetzt. Der administrative `initialize_game`-Snapshot-Eingang bleibt für Wiederherstellung und reproduzierbare Tests bestehen; Browser/Gateway bieten keinen automatischen Altserver-Import mehr an.

Ereignisse verwenden die private `decision`-Tabelle mit `game_story` für Quelle und gespeichertes Ergebnis. `my_game_stories` und `my_decisions` geben nur eigene Beschlüsse frei. Der versionierte Katalog liegt in `shared/stories.ts`; die autoritativen Transaktionen und Fristen in `game-stories.ts`. Der Spiel-Economy-Tick bearbeitet Eskalationen und Abläufe. Sichere kostenlose Standardoptionen verhindern Ausgaben ohne Spielerbeschluss.

`crisis` und `game_crisis` enthalten öffentliche Phase, Frist, Ziel und Fortschritt. Die privaten `game_crisis_pledge`-Zeilen speichern eigene Beiträge und Abschirmung. Produktionswechsel rechnen zunächst abgeschlossene Zyklen ab und aktualisieren dann die Kolonieraten. Die Client-Wirtschaftsübersicht verwendet denselben Faktor. Es entstehen keine neuen individuellen Schiffs-/Gefechtsabonnements.

`initialize_stories` ergänzt das neue System idempotent auch in bestehenden Galaxien. Der Vorlauf beginnt an deren aktueller Spielzeit; bestehende Ereignisse, Ressourcen, Missionen und Beziehungen werden nicht zurückgesetzt. Das normale Update-Werkzeug ruft diesen Bootstrap nach der Veröffentlichung auf. Die erste Krise endet dauerhaft nach gemeinsamer Finanzierung; weitere Krisentypen und Ereignisketten sind noch offen. [Prüfbericht](reports/STORIES.md).

Es wurde kein Convex eingeführt und kein Wechsel auf Rust vorausgesetzt.

### Himmelskörper und Systemanlagen

`shared/celestial.ts` definiert einen deterministischen Orbitalatlas. Seine lokalen Slots sind dauerhafte Bauadressen: bestehende Slots dürfen bei späteren Katalogänderungen nicht umgeordnet oder neu verwendet werden. Die Körper werden bei Bedarf aus dem System abgeleitet; beim Galaxiebeitritt werden keine tausenden dekorativen Bahndaten übertragen.

Die private Tabelle `game_site` speichert Besitzer, Körper, Anlagentyp, Ausbaustufe, gezahlte Kosten, Baufrist und Produktionsanker. `site_build` und `site_cancel` sind autoritative Spielbefehle. Der strategische Scheduler beendet fällige Bauaufträge über den Fristenindex. Die Wirtschaft rechnet abgeschlossene Produktionszyklen ab, einschließlich des aktiven Krisenfaktors. Bei Verlust einer Hauptkolonie werden deren Systemanlagen zusammen mit der übrigen Infrastruktur entfernt.

`visible_game_sites` liefert alle eigenen Anlagen für die Wirtschaftsübersicht sowie fertiggestellte fremde Anlagen ausschließlich in aktuell sichtbaren Systemen. Fremde Bauaufträge und Kosten werden nicht freigegeben. Ein neuer Körper-/Anlagenbau fordert keine individuellen Schiffspositionen an. Die Erweiterung ist additiv und benötigt keinen Spielstandreset. [Prüfbericht](reports/SYSTEM-VIEW.md).

## Verwendete Primärdokumentation

- [SpacetimeDB 2.10.0 Release](https://github.com/clockworklabs/SpacetimeDB/releases/tag/v2.10.0)
- [TypeScript Quickstart](https://spacetimedb.com/docs/quickstarts/typescript/)
- [Schedule Tables](https://spacetimedb.com/docs/tables/schedule-tables/)
- [Private Tabellen und Zugriffsrechte](https://spacetimedb.com/docs/tables/access-permissions/)
- [Serverseitige Views](https://spacetimedb.com/docs/functions/views/)
- [TypeScript-Client und Subscriptions](https://spacetimedb.com/docs/clients/typescript/)
