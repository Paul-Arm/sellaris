# Reiche, Spezies und Vorlagen

Die persönliche Bibliothek ist über **Reiche und Spezies** in der linken Navigation erreichbar. Reichs- und Speziesvorlagen lassen sich erstellen, bearbeiten, duplizieren und löschen. Ein gespeichertes Reich wird über **Für Expedition wählen** im Multiplayer-Dialog für eine neue Partie oder einen Beitritt ausgewählt. Bestehende Sitzungen werden weiterhin wiederaufgenommen; der erste Seitenaufruf erzeugt nicht mehr automatisch eine Partie.

## Modell und Lebenszyklus

Die gemeinsamen Rechenregeln für Eigenschaften, Traits, Voraussetzungen und Modifikatoren sind in [RULES.md](./RULES.md) beschrieben. Reiche und Spezies verwenden sie bereits über einen kompatiblen Adapter; Planeten, Anführer und Sektoren behalten ihre eigenen Fachmodelle.

```text
Persönliches Bibliotheksprofil (unabhängig von einer Partie)
  ├─ SpeciesTemplate [id, revision, version, Merkmale, Klima, Namen, Lore]
  └─ EmpireTemplate  [id, revision, version, speciesTemplateId, Regierung, Ursprung, Identität]
                         │ validieren + vollständig kopieren
                         ▼
Spieler einer Partie → EmpireState
  ├─ founding: unveränderte Reichs- und Speziesvorlage samt Revision
  ├─ design: aktuelle Identität und Regierung
  ├─ species[]: lokale Speziesinstanzen und abstammende Varianten
  ├─ primarySpeciesId: Gründungsspezies für reichsweite Effekte und neue Kolonien
  ├─ revision, Reformsperre, Modifikationssperre, Chronik
  └─ Kolonien → populations[] mit lokalen speciesId und Bevölkerungsanteilen
```

Reichsvorlagen referenzieren Speziesvorlagen in derselben privaten Bibliothek. Eine gültige Speziesänderung wirkt auf zukünftige Gründungen aller referenzierenden Reichsvorlagen. Würde die Änderung ein solches Reich ungültig machen, wird sie vollständig zurückgewiesen. Verwendete Speziesvorlagen lassen sich erst löschen, nachdem ihre Reichsvorlagen entfernt oder auf eine andere Spezies umgestellt wurden.

Beim Gründen entstehen vollständige Kopien. Weder Änderungen noch Löschungen in der Bibliothek verändern eine vorhandene Partie. Zwei Partien teilen keine veränderlichen Spezies- oder Regierungsobjekte. Eine Reform aktualisiert ausschließlich `EmpireState.design.government`. Eine Speziesmodifikation erzeugt eine neue lokale Spezies mit `parentId`, `generation`, `sourceTemplateId` und `sourceRevision`; sie ersetzt ausschließlich die betroffene Ausgangsbevölkerung in ausgewählten eigenen Kolonien. `founding` wird bei diesen Vorgängen niemals überschrieben. Vorlagen werden auch beim Spielende nicht automatisch zurückgeschrieben.

## Spielregeln

- Vier Reichstypen: souveränes Reich, Megakorporation, Schwarmbewusstsein und Maschinenintelligenz. Sie haben unterschiedliche Regierungsformen und Staatselemente. Maschinenintelligenzen verwenden synthetische Gründungsspezies; die anderen Typen biologische oder lithoide Spezies.
- Sieben Regierungsformen, acht Ethiken mit vier Gegensatzpaaren und 13 Staatselemente. Individuelle Gesellschaften verteilen genau drei Ethikpunkte; fanatische Ethiken kosten zwei. Kollektive haben keine individuellen Ethiken. Genau zwei kompatible Staatselemente sind erforderlich.
- Sieben Ursprünge mit eigenen Ressourcen-/Bevölkerungsstarts oder dauerhaften Effekten. Ursprungsboni werden **einmal beim Gründen** angewendet. Es gibt derzeit keine ursprungsabhängigen Ereignisketten.
- Drei Lebensformen, acht kosmetische Erscheinungsbilder, neun Heimatklimata und 15 Merkmale. Startvorlagen haben zwei Merkmalspunkte und höchstens fünf Merkmale. Negative Merkmale finanzieren positive, widersprüchliche Merkmale sind ausgeschlossen. Portraits sind derzeit Erscheinungsbild-Kategorien, keine individuellen Illustrationen.
- Namen, Farbe, Emblem, Schiffspräfix, Herrschername/-titel, Heimatsystem/-welt, Beschreibung und Lore werden gespeichert. Farbe, Emblem, Reichs-/Heimatnamen und Schiffspräfix erscheinen im Spiel. Sie geben keine Boni. Herrscher sind bisher Identitätsdaten, kein separates Lebenslauf-/Wahlsystem.
- Feste Katalogeffekte werden addiert; frei übermittelte Client-Modifikatoren werden nicht übernommen. Regierungs-, Ursprungs- und Speziesmerkmale beeinflussen Kolonieproduktion, Wachstum, Forschungs-/Bautempo, Reisegeschwindigkeit und Waffenschaden.
- Bewohnbarkeit: 100 % auf dem bevorzugten Klima, 80 % im selben Klimabereich, sonst 60 %. Maschinen starten bei 90 % auf allen Planeten. Boni werden als Prozentpunkte hinzugefügt; das Ergebnis wird auf 20–100 % begrenzt. Wachstum wird mit der Bewohnbarkeit multipliziert; Kolonieproduktion verliert die Hälfte der fehlenden Bewohnbarkeit. Unterschiedliche Spezies werden nach ihrem Bevölkerungsanteil gewichtet.
- Die Reichsgrundversorgung bleibt konstant; Produktionsboni gelten für die Kolonien. Reichsweite Forschung, Bau, Reise und Waffen verwenden die Gründungsspezies. Neu gegründete Kolonien beginnen ebenfalls mit der Gründungsspezies. Bevölkerungsvarianten verändern Produktion und Wachstum in den jeweils betroffenen Kolonien.
- Regierungsreform: 100 Energie + 150 Forschung, anschließend 120 **Spielsekunden** Wartezeit. Regierung, Ethiken und Staatselemente sind veränderbar; Reichstyp und Ursprung bleiben erhalten. Bereits geleistete Forschungs-/Bauarbeit bleibt beim Ratenwechsel erhalten. Bereits begonnene Flugabschnitte behalten ihre berechnete Dauer.
- Speziesmodifikation: Quantenextraktion erforderlich, 120 Mineralien + 300 Forschung, anschließend 240 Spielsekunden Wartezeit. Varianten haben vier Merkmalspunkte und höchstens fünf Merkmale. Neue Namen, Klima und Merkmale sind möglich; die grundlegende Lebensform bleibt erhalten. Maximal 32 lokale Spezies je Reich, einschließlich der Gründungsspezies. Die Modifikation wird unmittelbar als ein atomarer Spielbefehl angewendet, noch nicht als zeitlich laufendes Forschungsprojekt.

## Speicherung und Identität

### Flaggeneditor

Im Reichseditor führt **Flagge** zu einem eigenen Bannereditor. Er bietet zwölf Flächenmuster, drei unabhängig wählbare Farben, sechs Embleme, Größe und Drehung, drei Emblempositionen, Kreis-/Sechseckrahmen und einen einfachen oder doppelten Rand. Vier Startvorlagen und ein Zufallsentwurf helfen beim Entwerfen. Die Vorschau zeigt sowohl das große Banner im Verhältnis 3:2 als auch seine Darstellung als kleines Spielerabzeichen. **Zurücksetzen** stellt den Stand beim Öffnen dieses Editorbereichs wieder her; **Vorlage speichern** speichert den Entwurf mit der Reichsvorlage. **SVG exportieren** lädt die gleiche Grafik als skalierbare Datei herunter.

Die Flagge liegt als versioniertes `FlagDesign` in `EmpireTemplate.flag` und wird mit dem restlichen Reich in `EmpireState.design` sowie den Gründungssnapshot kopiert. `shared/flags.ts` validiert ausschließlich bekannte Muster, numerisch begrenzte Transformationen und Hex-Farben; beliebige SVG-/HTML-Eingaben werden nicht gespeichert. Alte Vorlagen ohne Flagge erhalten ein Standardbanner aus ihrer bisherigen Farbe und ihrem Emblem. Alte Spielinstanzen werden bei der Darstellung ebenfalls unterstützt, ohne den Gründungssnapshot umzuschreiben. Die Flagge verändert keine Spielwerte; die strategische Reichsfarbe bleibt eine eigene Einstellung unter **Identität**.

`src/EmpireFlag.tsx` zeichnet alle Vorschauen, Spielabzeichen und Exporte mit demselben SVG-Renderer. Die Flagge erscheint in der Vorlagenliste, im Reichsprofil, am Reich im Spiel, in der Multiplayer-Liste und in der Reichsrangliste. Nur die kosmetische Flagge wird zusätzlich in `PublicPlayer` veröffentlicht; Regierung, Lore und private Speziesdaten bleiben privat. Spätere Vorlagenänderungen beeinflussen die Flagge einer bereits gegründeten Partie nicht. Die neuen Flaggenprüfungen stehen in `tests/flags.test.ts`; der WebSocket-Neustarttest prüft ebenfalls die erhaltene Flagge.

`server/empireLibrary.ts` speichert private Profile in `DATA_DIR/empire-libraries.json`, separat von `sectors.json`. Der Browser erhält einen zufälligen 256-Bit-Zugangsschlüssel in `localStorage` unter `singularity.library-token`. Auf dem Server wird nur dessen SHA-256-Hash gespeichert. Profilzugang und Raum-Wiederaufnahmetoken sind unabhängig. Bibliotheken sind damit browsergebunden; ein Konto-Login, Wiederherstellung und geräteübergreifende Synchronisierung sind noch nicht implementiert. Löschen des Browserspeichers verliert diesen Zugang.

Speichern wird erst nach erfolgreichem temporärem Schreiben und atomarem Umbenennen bestätigt. Änderungen sind pro Store serialisiert. Vorlagenrevisionen verhindern verlorene Änderungen zwischen mehreren Tabs; bestätigte Änderungen werden nur an dieselbe Profilidentität verteilt. Beim Konflikt bleibt der lokale Entwurf erhalten und die aktuelle Fassung kann geladen werden. Das Speziesreferenzmodell wird innerhalb derselben Transaktion geprüft.

Grenzen: 64 Reichs- und 64 Speziesvorlagen pro Profil, 500 Profile pro Server, 240 Zeichen Beschreibung, je 4.000 Zeichen Lore, WebSocket-Eingaben maximal 64 KiB. Diese Grenzen betreffen den bisherigen Prototyp und können zentral angepasst werden. Eine beschädigte Bibliotheksdatei verhindert den Serverstart, statt Daten durch eine leere Datei zu ersetzen.

Alte Spielstände erhalten additiv eine als `legacy` markierte Reichsinstanz und Bevölkerungsgruppen. IDs, Ressourcen, Eigentum, Aufträge, Sitzungstoken und Bevölkerung bleiben erhalten. Diese Partien behalten ihre bisherigen Wirtschaftswerte; die vollständigen neuen Boni gelten bei einer Gründung aus einer Vorlage. Auch ein erneutes Laden spielt keine Startboni erneut ab.

## Transportschnittstelle

Bibliotheksnachrichten laufen über den bestehenden WebSocket `/ws`:

| Clientnachricht                                                        | Serververhalten                                                                                                                                            |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{ type: 'library_open', token?, requestId? }`                         | Bestehendes privates Profil öffnen oder ein neues anlegen. Antwort `library` mit Schlüssel und Bibliothek.                                                 |
| `{ type: 'library_mutate', mutation, requestId }`                      | Validieren, dauerhaft speichern, an eigene Profilverbindungen verteilen. Antwort `library`; bei Fehler `error` mit derselben `requestId`.                  |
| `mutation: { type: 'save_empire' / 'save_species', template }`         | Neue Vorlage mit Revision 0; bestehende Vorlage mit erwarteter Revision. Der Server erhöht die Revision.                                                   |
| `mutation: { type: 'delete_empire' / 'delete_species', id, revision }` | Löschen mit Revision und Referenzprüfung.                                                                                                                  |
| `{ type: 'create' / 'join', templateId, code? }`                       | Vorlage ausschließlich aus der authentifizierten eigenen Bibliothek auflösen, validieren und kopieren. Raum erst nach erfolgreicher Gründung registrieren. |
| Spielbefehl `empire_reform`                                            | `{ government, revision }`; eigene Ressourcen, erwartete Reichsrevision und Spielzeit prüfen.                                                              |
| Spielbefehl `species_modify`                                           | `{ sourceId, design, colonyIds, revision }`; eigene Spezies und eigene bewohnte Kolonien prüfen, Ressourcen und Populationen atomar ändern.                |

Alte Clients ohne `templateId` bleiben mit ihrem bisherigen neutralen Start kompatibel. Gegner erhalten weiterhin nur öffentliche Spielernamen/-farben; private Reichsinstanzen, Geschichte, Spezies und Bevölkerungsdaten werden nicht in fremde Ansichten kopiert.

## Übergabe an SpacetimeDB

Die normale Spieloberfläche verwendet inzwischen den SpacetimeDB-Adapter. Die private Vorlagenbibliothek bleibt im Node-Gateway. Eine geprüfte Bibliotheksvorlage wird serverseitig in einen Gründungssnapshot kopiert; der Client erhält ein einmaliges Ticket zum Binden seiner nativen Identität an das Reich. Aktive Reichsinstanzen, Spezies und Populationen sind privat in der jeweiligen Galaxie gespeichert. Öffentliche Flaggen werden separat projiziert.

Transportfreie Bausteine:

| Modul                                  | Verantwortung                                                                                            |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `shared/empireCatalog.ts`              | Stabile Regel-IDs, Kompatibilitäten, Kosten und Effekte.                                                 |
| `shared/empires.ts`                    | Kanonische Eingabevalidierung, Vorlagen, Bibliothekstransaktionen, Gründungssnapshots und Bewohnbarkeit. |
| `shared/empireState.ts`                | Spielinstanzen, Abstammung und reine Berechnungen/Planung für Reformen und Varianten.                    |
| `shared/game.ts`, `shared/colonies.ts` | Autoritative Anwendung auf Ressourcen, Uhr, Spieler und Kolonien des bisherigen Spiels.                  |

`gameCommand` führt Reformen und Modifikationen als native Transaktionen mit Ressourcenabzug, Spielzeitsperre und Revision aus. Speziesvarianten aktualisieren die betroffenen Pop-Kohorten und Produktionsraten; Gründungssnapshots bleiben unverändert. Private Views leiten den Besitzer aus der geprüften nativen Identität ab. Der Gateway prüft weiterhin den privaten Bibliotheksschlüssel; eine kontenbasierte Anmeldung ist ein späterer Schritt. Die Vorlagenbibliothek gehört nicht zu Kampf- oder Bewegungsabonnements.

## Verifikation

`npm test` prüft die vorhandenen Spieltests und die neuen `tests/empires.test.ts` / `tests/empire-server.test.ts`. Die neuen Tests decken ungültige Kombinationen, manipulierte IDs, Trait-Budgets, Vorlagenrevisionen, private Profile, konkurrierende Änderungen, Referenzschutz, getrennte Partien, Startboni, tatsächliche Produktion/Arbeitsraten, Reformen, Abstammung, Populationstransfer und Serverneustart ab. Der neue WebSocket-Test verwendet einen automatisch zugewiesenen eigenen Port und ein eigenes temporäres Datenverzeichnis; er startet und beendet ausschließlich seine eigenen Prozesse.

Browserprüfung in einer separaten Instanz: Reich duplizieren/benennen/speichern, Ursprung/Gesellschaft ansehen, Partie aus Vorlage gründen, Regierungsreform ausführen, Spezies duplizieren/speichern, Neuladen und Wiederaufnahme, Desktop und 390 px mobile Ansicht ohne horizontalen Überlauf oder Konsolenfehler.
