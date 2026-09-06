# Eigenschaften, Traits und Modifikatoren

## Entscheidung: gemeinsamer Regelkern, getrennte Fachmodelle

Spezies, Reiche, Anführer, Planeten und Sektoren teilen die Mathematik und die Sprache für Voraussetzungen. Ihre Zustände, Lebenszyklen und Spielregeln bleiben getrennt. Eine Spezies ist weder ein Planet mit anderen Tags noch eine beliebige Sammlung aller Spielwerte.

| Fachmodell    | Eigene Verantwortung                                           | Gemeinsame Regeln                                              |
| ------------- | -------------------------------------------------------------- | -------------------------------------------------------------- |
| Spezies       | Lebensform, Vererbung, Varianten, Klimaeignung, Merkmalsbudget | Lebensdauer, Produktions-/Unterhaltsmodifikatoren, Fähigkeiten |
| Reich         | Regierung, Gesetze, Diplomatie, Technologien                   | Reichsboni, Voraussetzungen, zeitlich begrenzte Beschlüsse     |
| Anführer      | Rolle, Erfahrung, Alter, Aufgaben, Ernennung                   | Rollenmerkmale, skalierende Boni, Herkunft durch Spezies       |
| Planet        | Klima, Bezirke, Gebäude, Bevölkerung, Besiedlung               | Lagerstätten, Umweltmerkmale, planetare Zustände               |
| Sektor        | Zuständigkeit, Planeten, Gouverneur, Verwaltung                | Regional wirksame Richtlinien und Gouverneursboni              |
| Flotte/Schiff | Bewegung, Gefechte, Ausrüstung, Befehle                        | Schaden, Geschwindigkeit, situationsabhängige Effekte          |

Planeten brauchen beispielsweise eigene Berechnungen für verfügbare Bezirke und Bevölkerungsverteilung. Der gemeinsame Kern ersetzt diese Berechnungen nicht; er liefert ihnen wirksame Werte. Auch Wahlen, Alterung, Vererbung, Produktion, Ressourcenabbuchungen und das Auslösen von Ereignissen gehören in die jeweiligen Fachsysteme.

## Implementierung und Stand

- `shared/rules/types.ts`: versionierte, JSON-fähige Datenverträge.
- `shared/rules/validation.ts`: Katalog-, Kontext- und Quellenvalidierung; Abhängigkeitsprüfung.
- `shared/rules/engine.ts`: reine, deterministische Auswertung, Voraussetzungen und nachvollziehbare Ergebnisse.
- `shared/rules/catalog.ts`: konkrete Definitionen für Spezies, Anführer, Planeten, Sektoren, Ereignisboni und Zustände.
- `shared/empireRules.ts`: Adapter für die bestehenden Reichs-/Speziesregeln einschließlich begrenztem Cache für die Spielschleife.
- `tests/rules.test.ts`: Rechenregeln, Geltungsbereiche, Zeitverhalten, Datenintegrität und Kompatibilität.

Die bestehende Simulation nutzt den Kern bereits über `governmentModifiers()` und `speciesModifiers()`. Der Adapter übersetzt ihre bisherigen neun additiven Bonuswerte und erhält die bisherige Balance. Herkunft und Rechenbeiträge lassen sich zusätzlich über `evaluateGovernmentRules()` und `evaluateSpeciesRules()` abfragen.

Die neuen fachlichen Beispiele sind ausführbarer, getesteter Regelinhalt. Sie sind noch keine Anführer-Alterung, Konsumgüterwirtschaft oder neue Ereignisketten im Spiel und werden nicht automatisch im bisherigen Spezieseditor angeboten. Diese Mechaniken benötigen ihre jeweiligen Fachmodelle. Es gibt keine Datenbankmigration und keinen neuen Client-Befehl, mit dem freie Effekte eingeschleust werden könnten.

## Begriffe

**Eigenschaft (`properties`)**: eine typisierte Tatsache des Fachmodells, beispielsweise `species.kind`, `leader.level`, `leader.role` oder `planet.habitable`. Textwerte können auf definierte Ausprägungen begrenzt sein. Eigenschaften sind keine Werte, auf die blind Prozentboni angewendet werden.

**Flag (`flags`)**: eine benannte Fähigkeit bzw. ein logischer Zustand, beispielsweise `capability.psionic`. Flags können angeboren sein oder durch Effekte gewährt bzw. gesperrt werden. Ereignisse prüfen diese Fähigkeit statt den lokalisierten Namen „Psionisch“ zu vergleichen.

**Wert (`stats`)**: eine numerische Größe mit Basiswert, Einheit, optionalen Grenzen, Bewertungsrichtung und optionalem Fachbereich. Für `life.expectancy` sind nur Spezies und Anführer zugelassen. Ein Planet erhält diesen Wert nicht. Ob ein Bonus gut oder schlecht ist, bestimmt `better`: Bei Unterhalt ist ein niedriger Wert besser.

**Trait**: eine stabile Definition mit Namen, Beschreibung, zulässigen Besitzertypen, optionalen Kosten, Voraussetzungen, Ausschlüssen und mehreren Effekten. Das Budget bleibt fachlich: Spezies nutzen Punkte; Planetenmerkmale brauchen nicht dasselbe Punktesystem. `validateTraits()` prüft eine vollständige Auswahl gemeinsam, unabhängig von ihrer Reihenfolge.

**Quelle**: eine konkrete Instanz einer Definition im autoritativen Spielzustand. Sie hat eine eigene ID, einen Besitzer, gegebenenfalls Stapelzahl und Aktivierungs-/Ablaufzeit. Auch Gebäude, Technologie, Gesetz, Ereignis oder Krankheit können Quellen sein. Unterschiedliche Ursachen desselben Bonus bleiben nachvollziehbar.

## Mathematik

Ein numerischer Effekt nennt Zielwert, Operation und Betrag. Alle Beträge verwenden gespeicherte Zahlen, keine lokalisierten Zeichenfolgen:

| Operation  | Bedeutung                       | Beispiel                                                                        |
| ---------- | ------------------------------- | ------------------------------------------------------------------------------- |
| `add`      | Fester Zuschlag vor Prozenten   | `40` Lebensjahre, `4` Mineralien, `0.1` Anteil = 10 Prozentpunkte Bewohnbarkeit |
| `percent`  | Additive relative Änderung      | `0.1` = +10 %, `-0.15` = −15 %                                                  |
| `multiply` | Separater Faktor                | `1.2` = zusätzlich ×1,2, `0.5` = halbieren                                      |
| `override` | Ersetzt das berechnete Ergebnis | Feste Geschwindigkeit während eines Zustands                                    |
| `floor`    | Untergrenze                     | Mindestens 10                                                                   |
| `cap`      | Obergrenze                      | Höchstens 150                                                                   |

```text
berechnet = (Basis + Summe(add)) × (1 + Summe(percent)) × Produkt(multiply)
effektiv  = clamp(gewinnende Überschreibung oder berechnet, Untergrenze, Obergrenze)
```

Die Grenzen aus dem Wertkatalog und aus Effekten gelten auch für Überschreibungen. Widersprüchliche Grenzen werden als Inhaltsfehler abgelehnt. Der Kern rundet keine Zwischenwerte; die Fachlogik entscheidet beispielsweise über ganzzahlige Baukosten, die UI über ihre Anzeige.

Beispiele mit dem neuen Katalog:

| Definition                       | Basis                                  | Ergebnis                                 |
| -------------------------------- | -------------------------------------- | ---------------------------------------- |
| `species.long_lived`             | 80 Jahre                               | 120 Jahre                                |
| `species.intelligent`            | 100 produzierte Forschung              | 110 Forschung                            |
| `species.wasteful`               | 10 Energie- und 2 Konsumgüterunterhalt | 11 Energie- und 2,2 Konsumgüterunterhalt |
| `species.psionic`                | Keine psionische Fähigkeit             | Flag `capability.psionic`                |
| `planet.mineral_rich` plus +20 % | 10 Mineralien                          | `(10 + 4) × 1.2 = 16.8`                  |

Ein relativer Bonus auf Basis 0 bleibt 0. Der Kern erfindet keine Grundkosten. Unterhaltsbeträge werden vom Wirtschaftsmodell geliefert und nach der Auswertung abgebucht. Ein +10-%-Unterhaltsmodifikator verringert niemals implizit die Produktion.

Abgeleitete Werte können andere **fertig berechnete** Werte referenzieren: `economy.net_energy` ist Energieproduktion minus Energieunterhalt und darf negativ sein. Abhängigkeiten werden beim Laden auf Zyklen und auf unpassende Fachbereiche geprüft. Ein abgeleiteter Wert kann nicht durch einen gelieferten Basiswert umgangen werden.

## Voraussetzungen und Auswertungsschritte

Voraussetzungen unterstützen verschachtelte `all`, `any`, `not`, Objekttypen, Flags, Merkmals-IDs, typisierte Eigenschaftsvergleiche, Zahlenvergleiche und Beziehungen. Numerische Ausdrücke erlauben Summen, Produkte, Minimum, Maximum und Division sowie Bezug auf Basiswerte oder numerische Eigenschaften. So kann ein Anführer pro Stufe einen Bonus erhalten, der bei 25 % gedeckelt wird.

`requires` entscheidet über den **Erwerb** eines Traits. `when` entscheidet über die **laufende Aktivität** eines einzelnen Effekts. Eine Änderung der Voraussetzung löscht einen erworbenen Trait nicht heimlich. Eine Fachregel kann einen unzulässig gewordenen Trait ausdrücklich entfernen oder deaktivieren.

Die Auswertung erfolgt bewusst in festen Schritten:

1. Fachsystem erstellt einen unveränderten Kontext aus Tatsachen und wählt erlaubte Quellen.
2. Beginn/Ablauf, Effektbedingungen und numerische Ausdrücke werden geprüft.
3. Stapelgruppen werden aufgelöst; Werte werden berechnet; Flags werden gewährt/gesperrt.
4. Ereignisse und Interaktionen können mit `engine.check(condition, context, result)` das fertige Ergebnis prüfen.

Während Schritt 2 lesen Bedingungen nur den ursprünglichen Kontext und Basiswerte. Sie lesen keine gerade erst gewährten Flags oder veränderten Endwerte. Dadurch hängen Ergebnisse nicht von der Reihenfolge der Effekte ab und können sich nicht selbst aktivieren. Gewährte Flags können anschließend Ereignisse freischalten. Für einen Trait, der einen anderen voraussetzt, wird dessen Trait-ID geprüft. Abgeleitete Werte sind der ausdrücklich vorgesehene Weg für Abhängigkeiten zwischen Endwerten.

Fehlende Eigenschaften oder uneindeutige Einzelbeziehungen ergeben „Voraussetzung nicht erfüllt / Kontext fehlt“. Das gilt auch unter `not`: Ein unbekannter Kriegszustand ist kein Beweis für Frieden. `every` über eine leere Gruppe ist ebenfalls nicht erfüllt. Ungültiger Inhalt wie Division durch null oder unbekannte IDs führt dagegen zu einem Fehler; er wird nicht still als gültiger Bonus behandelt.

## Geltungsbereich und Weitergabe

Die Engine sucht keine Weltobjekte und verbreitet keine Effekte automatisch. Der zuständige Adapter muss passende Quellen auswählen. `RuleDefinition.kinds` beschreibt den **Besitzer** einer Quelle, nicht ihre automatischen Empfänger. `when` kann Empfänger weiter beschränken.

- Ein Speziestrait wird einer Bevölkerungsgruppe ausdrücklich als Quelle gegeben. Bei gemischter Bevölkerung werden die tatsächlichen Gruppenerträge und -kosten getrennt berechnet und anschließend summiert. Ein flacher Bonus darf nicht durch eine pauschale Mittelung wie ein Prozentbonus behandelt werden.
- Ein Speziestrait zur Lebensdauer kann an einen Anführer dieser Spezies weitergegeben werden. Das Anführermodell bestimmt Vererbung und spätere Änderungen.
- Ein Gouverneur wird vom Sektormodell als mögliche Quelle ausgewählt. `leader.sector_architect` prüft zusätzlich, dass Zielplanet und Gouverneur denselben Sektor **und** Besitzer haben. Ein Gouverneur bufft weder fremde Planeten noch sämtliche Welten des Reichs.
- Ein Planetenmerkmal ist eine Quelle des Planeten. Bevölkerungsboni daraus müssen vom Koloniemodell ausdrücklich an dessen Gruppen weitergegeben werden.

`Scope` beginnt bei `target` oder `source`. Ein Pfad wie `['sector', 'owner']` folgt definierten Beziehungen. Einzelpfade verlangen genau ein Ziel. Für Gruppen gibt es `related` mit `some` oder `every`. Der Kontext enthält nur erforderliche Objekte; es gibt keine globale Datenbankabfrage im Kern.

## Stapelung, Zeit und Erklärbarkeit

Ohne benannte Gruppe addieren bzw. multiplizieren sich einzelne Quellen. Eine Quelleninstanz kann bis zu ihrer definierten `maxStacks` gestapelt sein. Bei `add`/`percent` wird der Betrag mit der Stapelzahl multipliziert, bei `multiply` potenziert. Überschreibungen und Grenzen vervielfachen sich nicht. Die Grenze gilt pro Instanz; fachliche Limits für mehrere Gebäude oder Traits kontrolliert das Fachmodell.

Benannte Effektgruppen gelten pro Ziel, Wert und Operation:

- `sum`: sämtliche Beiträge.
- `highest` / `lowest`: größter bzw. kleinster wirksamer Zahlenbeitrag.
- `unique`: höchste Priorität; bei Gleichstand stabile Definitions-, Quellen- und Effekt-ID.

Auch gleichwertige stärkste/schwächste Beiträge nutzen diese stabile Reihenfolge. Widersprüchliche Regeln innerhalb derselben Gruppe sind ungültig. Mehrere Überschreibungen verwenden Priorität und dieselben Tie-Breaker. Bei Flags gewinnt höchste Priorität; bei Gleichstand gewinnt die Sperre vor der Gewährung. Eine natürliche Fähigkeit kann somit vorübergehend unterdrückt werden.

Zeiten liegen in der **Spielzeit**, nicht in `Date.now()`: `startsAt <= tick < expiresAt`. Das passt zu Pause, Beschleunigung, Wiederaufnahme und deterministischer Simulation. Abgelaufene Quellen bleiben im übergebenen Zustand unverändert; das Fachsystem kann sie später entfernen. Ohne diese Quelle liefert die nächste Auswertung wieder den Grundwert. Ein Buff schreibt niemals direkt in den Basiswert.

`RuleResult` enthält Basis, feste Summe, Prozentsumme, Gesamtfaktor, berechneten/überschriebenen/begrenzten Wert und alle Beiträge. Jeder Beitrag trägt Quelleninstanz, Definitions-ID, Effekt-ID, Besitzer, Betrag und Aktivitätsgrund. Das ermöglicht Tooltips wie „80 Basis +40 Langlebig =120 Jahre“ und erklärt ebenso verdrängte, noch nicht aktive oder abgelaufene Effekte.

## Verwendung

```ts
import { coreRules } from './shared/rules/catalog';
import type { RuleContext } from './shared/rules/types';

const traits = ['species.long_lived', 'species.intelligent'];
const context: RuleContext = {
  target: 'species-42',
  tick: 0,
  entities: {
    'species-42': {
      id: 'species-42',
      kind: 'species',
      properties: { 'species.kind': 'biological' },
      base: { 'life.expectancy': 80, 'production.research': 100 },
      traits,
    },
  },
};
const selection = coreRules.validateTraits(context, traits, { budget: 3, maxTraits: 5 });
if (!selection.valid) throw new Error(selection.problems.join(' '));
const result = coreRules.evaluate(
  context,
  traits.map((definition) => ({
    id: `species-42:${definition}`,
    owner: 'species-42',
    definition,
  })),
);
// result.stats['life.expectancy'].value === 120
// result.stats['production.research'].value ≈ 110
```

Neue Inhalte werden durch Definitionen ergänzt. Neue Fachsysteme stellen ihre eigenen Adapter, Zustände und passende Werte bereit. Neue Rechenoperationen erfordern bewusst eine Änderung an Typen, Validierung, Engine und Tests. Beliebiger JavaScript-Code, `eval`, freie Pfadausführung oder Formeln als ausführbare Strings gehören nicht zum Inhaltsformat.

## Speicherung und Kompatibilität

Vorlagen speichern ausgewählte Definitionen und intrinsische Ausgangseigenschaften. Beim Gründen werden diese in einen unabhängigen Spielzustand kopiert. Im Spiel kommen Quelleninstanzen mit eigenen IDs und Lebenszeiten hinzu. Referenzen auf die persönliche Bibliothek sind Herkunftsinformation; laufende Spielwerte dürfen sie nicht nachladen.

Der neue Katalog und Ergebnisse haben `version: 1`. Definitionen erhalten stabile IDs; eine semantisch inkompatible Änderung braucht eine neue ID oder eine explizite Spielstandmigration. Eine vollständige Inhaltsversionierung für künftige Partien sollte den verwendeten Katalogstand pro Partie festhalten. Die Engine führt keine automatische Neuinterpretation alter Inhalte durch.

Die bestehenden Vorlagen bleiben bei ihrem bisherigen Format. `legacy.trait.wasteful` erhält deshalb die alte Wirkung −10 % Energieproduktion. Die neue Definition `species.wasteful` bedeutet dagegen +10 % tatsächlichen Unterhalt. Diese Unterscheidung verhindert eine stille Balanceänderung und verhindert, dass ein negativer Trait schon Punkte vergibt, obwohl die benötigte Unterhaltswirtschaft noch fehlt. Erst zusammen mit dieser Wirtschaft werden neue IDs, UI-Angebot und Migration freigeschaltet.

Kataloge werden beim Laden geprüft, kopiert und eingefroren. Die Engine benötigt weder Node-/Browser-APIs noch Datenbankzugriff oder Zufall. Der parallele Backend-Task nutzt die gemeinsamen Reichsberechnungen inzwischen auch in SpacetimeDB; der Adapter erhält deren bisherige Rückgabewerte. Dieses Feature verändert keine Tabellen, Reducer oder veröffentlichten Module. Neue fachliche Regeln müssen bei der jeweiligen Integration ausdrücklich angebunden werden. Der Aufrufer bleibt für Autorisierung, Besitzkontrolle, Transaktionen und Sichtbarkeit verantwortlich. Vollständige Ergebnisse können geheime Quellen enthalten und dürfen nicht ungefiltert an fremde Spieler veröffentlicht werden.
