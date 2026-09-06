# Lebende Welten — Kolonien als räumliche Pop-Wirtschaft

Status: Konzept und interaktiver Mockup, keine Integration in die Simulation. Alle Mockup-Zahlen sind illustrative Entwurfswerte. Branch: `codex/planetary-regions-mockups`. Der Worktree startet vom vorhandenen HEAD; die laufenden Änderungen im Hauptarbeitsverzeichnis wurden nicht kopiert oder geändert.

## Die Spielerfantasie

Du kolonisiert keine Liste von Bauplätzen, sondern eine Landschaft. Aus einem Landesteg wird eine Küstenstadt; sie erschließt ein Gebirge, dessen Minen eine Vulkanindustrie versorgen. Ein uralter lebender Wald steht der kürzesten Verbindung im Weg. Ihn erhalten, erforschen oder roden verändert diese Welt dauerhaft.

## Drei räumliche Ebenen

1. **Planet / Regionen:** 9–16 große, unregelmäßige Regionen nach Planetengröße. Kontinente, Meere, Hochland, Krater und Untergrund bestimmen ihre Nachbarschaft. Die Gesamtzahl hängt nicht von Pops ab. Anfangs sind nur der Landeplatz und die Nachbarn erschließbar; Forschung öffnet Ozean, Tiefen und andere Extremräume. Die Karte ist eine abstrahierte vollständige Planetenoberfläche, kein Stadtbau-Straßennetz.
2. **Region / Distrikte:** Jede Region hat 2–4 Geländesegmente. Ein Distrikt belegt eines, Großprojekte zwei benachbarte Segmente. Wohnen, Gewinnung, Energie, Forschung, Ökologie und Industrie sind tatsächliche Nutzungen vor Ort. Größere Stadtbezirke gehen in die Höhe; so bleibt eine alte Hauptstadt anders als ein neuer Außenposten.
3. **Distrikt / Gebäude:** Distrikte schaffen Jobs und gegebenenfalls Wohnungen. Ein bis zwei Gebäudemodule verändern die dortige Tätigkeit: z. B. Tiefenbohrer für eine Mine, Materiallabor im Industriebezirk oder ein Klimagehäuse für eine fremde Spezies. Gebäude sind Spezialisierungen, keine identischen globalen Multiplikatoren.

## Pops sind die Wirtschaft

- Ein Pop ist eine abstrahierte Bevölkerungseinheit; die Darstellung muss bei Umsetzung einmal konsistent auf die bisherigen Milliarden-Einheiten abgebildet werden. Für den Entwurf werden ganze Pops angezeigt, Wachstum intern als Fortschritt geführt.
- Jeder Pop gehört zu einer Spezies, wohnt in einer Region und besetzt höchstens einen Job. Arbeitslose produzieren keinen Jobertrag. Ein leeres Gebäude erzeugt nichts, verursacht aber einen klar sichtbaren Bereitschaftsunterhalt; Stilllegen hebt diesen auf.
- Arbeitsplatz-Ertrag = besetzte Jobs × Grundproduktion × Spezies-/Bewohnbarkeitsfaktor × begrenzter Standortbonus. Beispiel: zwei Forscher mit je 3 Forschung und +25 % vom Krater ergeben 7,5 Forschung pro Wirtschaftszyklus vor Unterhalt.
- Zum Einstieg bleiben die drei vorhandenen Reichsressourcen Energie, Mineralien und Forschung erhalten. Energie betreibt Gebäude, Mineralien finanzieren Bau und Flotte, Forschung treibt Technologien. Keine zusätzliche Legierungs-/Konsumgüterkette im ersten Schritt.
- Nahrung/Lebenserhaltung, Wohnen und Versorgung sind lokale Kapazitäten statt neuer globaler Lager. Organische, synthetische und lithoide Pops können unterschiedliche Versorgungskosten verursachen. Überschüsse verbessern Wachstum bis zu einer Grenze, Defizite senken es und erzeugen verständliche Auswanderungswarnungen. Kein plötzlicher Tod ohne Reaktionsfenster.
- Bevölkerungswachstum hängt von Wohnraum, Versorgung, Bewohnbarkeit und Zuzug ab. Rekrutierung/Produktion weiterer Spezies folgt ihren eigenen Voraussetzungen; kein kostenloses Wachstum durch Arbeitslosigkeit.

## Raum soll Entscheidungen schaffen

- Jobs sind in der Wohnregion und über das zusammenhängende planetare Verkehrsnetz erreichbar. Unverbundene neue Außenposten starten mit eigener minimaler Lebenserhaltung. Häfen/Tunnel verbinden besondere Geländetypen; der Spieler baut keine einzelnen Straßen.
- Der Netzwerkgraph verbindet die tatsächlich angrenzenden Regionen, einschließlich der Planetenkarten-Naht. Gebäude-Nachbarschaft gilt nur unmittelbar, Transportzugang entlang des Netzes. Die spätere Datenstruktur hält beides auseinander.
- Wenige benannte Wechselwirkungen statt einer Stapelorgie: ein benachbartes Habitat versorgt den Campus; eine aktive Mine liefert einen Industrievorteil; Industrie neben einem lebenden Wald kostet Ökologie. Jeder Bonus gilt einmal, aggregierte Standortboni sind begrenzt.
- Umweltbelastung ist regional. Ein Industrieband kann effizient sein, verdrängt aber empfindliche Spezies aus angrenzenden Wohnbezirken. Ökologieprojekte schaffen Schutzkorridore. Eine Welt kann sich so zu Metropole, Forschungsreservat oder Industriekranz entwickeln.
- Merkmale sind Entscheidungen: **Glaswald** erhalten (Versorgung), erforschen (Forschung, weniger Versorgung), erschließen (zwei neue Bauflächen, dauerhafter Verlust). **Geothermische Naht** gibt Energie, **fossiler Ozean** schafft Fossilienforschung, **schwebende Plateaus** erlauben späte Spezialhabitate. Im Mockup ist die Waldentscheidung eine reversible Vorschau; im Spiel erfordert irreversible Rodung eine klare Bestätigung.

## RTS-taugliche Bedienung

- Der Gouverneur besetzt Arbeitsplätze automatisch nach gewählter Priorität und Eignung. Kein manuelles Ziehen einzelner Pops nötig. Eine optionale Regionspriorität erlaubt Eingriffe bei Engpässen.
- Besetzung wird nur bei Änderungen von Pops, Jobs, Prioritäten oder Verbindungen neu berechnet. Deterministische Zuordnung mit Hysterese verhindert dauerndes Jobwechseln; Produktion läuft im bestehenden Wirtschaftsintervall.
- Ein planetarer Bauauftrag gleichzeitig als erste Ausbaustufe; weitere Aufträge in einer editierbaren Warteschlange. Vor Bau zeigt die UI Kosten, Zeit, Jobs, notwendige Pops, Betriebsunterhalt und tatsächlich erwarteten Mehrertrag.
- Bei vielen Kolonien: Entwicklungspläne wie „Forschungswelt“, Budgetgrenzen und Meldungen nur bei Wohnungsmangel, Versorgungslücken oder blockierter Entwicklung. Kein Zwang, alle Planeten ständig zu öffnen.

## Mockup zum Besprechen

`mockup.html` ist ein eigenständiges HTML-Fragment. Es zeigt zwei Ansichten und zwei Welten:

- **Oberfläche:** Auswahl organischer Regionen, lokale Distriktnutzung, Verkehrsnetz, Vorschau eines Forschungscampus und die drei Waldentscheidungen.
- **Bevölkerung:** 24 Pops, ihre Jobs und Kapazitäten, Arbeitsplatzprioritäten sowie Zuordnung nach Spezies. Das einfache lokale Zahlenmodell illustriert fehlende Besetzung und Betriebsunterhalt, ist kein Balancingmodell und keine implementierte Spielsimulation.
- **Nacre:** Küstenwelt mit Glaswald und Kraterarchiv. **Khepri:** Vulkanwelt mit geothermischen Regionen und unterirdischen Lebensräumen. Die Layout-Silhouette wird im Mockup wiederverwendet; echte Welten sollen aus ihrer Geologie generiert werden.

## Anschließende Umsetzung, erst nach Designfeedback

1. Regionen und Merkmale deterministisch pro tatsächlichem Planetenobjekt erzeugen; eine Kolonie verweist auf dessen ID statt nur das Sternsystem. Aktuelle uncommittete Objekt-/Terraforming-Arbeit vor Integration erneut prüfen.
2. Gemeinsames Wirtschaftsmodell für Pop-Gruppen, Jobs, Unterhalt und regionale Kapazitäten; vorhandene pauschale Gebäudeproduktion ersetzen.
3. Serverautoritative Befehle für Erschließen, Bauen, Priorität und Merkmalsentscheidungen; Zeitticks, Befehlsvalidierung und persistente Daten konsistent ergänzen.
4. Echte Oberfläche und Pop-Ansicht anbinden; KI und Gouverneur benutzen dieselben Regeln.
5. Dann gezielt prüfen: Pop-Erhaltung, kein Ertrag aus leeren Jobs, korrekter Unterhalt, abgeschaltete Distrikte, Verkehrsnetz, deterministische Generierung, laufende Bauaufträge und viele Kolonien unter Last.

Keine Migration oder eingefrorenen Generatoren für alte Galaxien. Inkompatible Änderungen verwenden neue Testpartien; Reichs- und Speziesvorlagen bleiben erhalten.
