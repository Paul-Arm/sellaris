# Ereignisse und Spezialprojekte erweitern

`types.ts` definiert Inhalte und Zustand, `engine.ts` Auswahl und Fortschritt, `catalog.ts` den gemeinsamen Pool. Ein neuer Eintrag im Pool benötigt keinen eigenen Reducer oder Screen. Bei umfangreicheren Inhaltsgruppen können Definitionen in separate Dateien ausgelagert und im Pool zusammengeführt werden.

## Auslöser und Auswahl

Das Backend ruft `triggerSituation(ctx, owner, trigger, stableKey, systemId, extraFacts)` auf. Aktuell angeschlossen: `founded`, `survey`, `colony`, `ownership`, `technology`, `species`, `modification`, `time`, `crisis`, `stellar-weather`. Zusätzliche Auslöser sind frei benennbar. Der Schlüssel muss denselben logischen Vorgang eindeutig bezeichnen; erneute Zustellung darf keinen neuen Schlüssel erzeugen.

Der Director prüft Bedingungen, Wiederholungen, Abklingzeit und Chance, dann wählt er gewichtet einen passenden Inhalt. `weights` verändert das relative Gewicht anhand weiterer Bedingungen. Zufall ist durch Welt, Reich und Auslöserschlüssel reproduzierbar. Normale Funde haben ein Limit von acht offenen Vorgängen; kritische Meldungen umgehen dieses Limit. Explizite Folgeprojekte können ebenfalls geöffnet werden. Der periodische Pool wird alle 30 Spieltage geprüft.

`repeat: 'once'` gilt pro Reich, `'system'` pro Reich und Fundort; `'repeat'` erlaubt Wiederholung nach `cooldownDays`. Ereignisse werden privat gespeichert. Wiederholungsverlauf und Flags überleben auch das Entfernen älterer Archiveinträge.

## Bedingungen

`all`, `any`, `not` verknüpfen Bedingungen; `is`, `has`, `gte`, `lte` vergleichen Fakten. Fehlende Fakten erfüllen keine positive Bedingung.

Verfügbare Fakten: `day`, `techs`, `speciesKinds`, `speciesCount`, `speciesGeneration`, `traits`, `modifiers`, `modifierCount`, `ownedSystems`, `surveyedSystems`, `colonies`, `systemId`, `systemKind`, `anomaly`, `systemOwned`, `crisis`, `sourceCrisisActive`, `sourceCrisisShielded`. Dazu `modifier.<Regelschlüssel>` für aggregierte Reichsmodifikatoren und `flag.<Name>` für gesetzte Ereignisflags. Produzenten können beim Auslösen weitere Fakten übergeben; Entscheidungsbedingungen und laufende Raten müssen Fakten verwenden, die `situationContext` dauerhaft bereitstellt.

## Beispiel

```ts
const expedition: EventDefinition = {
  id: 'echo-expedition', kind: 'project',
  title: 'Ein Echo hinter dem Horizont', subtitle: 'Forschungsauftrag',
  summary: 'Ein wiederkehrendes Signal verlangt eine längere Untersuchung.',
  theme: 'signal', artwork: '/events/signal.svg',
  triggers: ['survey'],
  when: { fact: 'surveyedSystems', op: 'gte', value: 3 },
  chance: 0.35, weight: 2, repeat: 'system', cooldownDays: 180,
  startCost: { energy: 40, data: 20 },
  progress: { target: 100, rate: 0.6, volatility: 1.2 },
  stages: [
    {
      id: 'measure', title: 'Das Signal vermessen', threshold: 100,
      blocks: [
        { type: 'dialogue', speaker: 'Forschungsleitung', text: 'Das Signal aus {{system}} verändert sich.' },
        { type: 'map', caption: 'Unser Untersuchungsgebiet' },
      ],
      effects: [{ type: 'resources', amounts: { data: 100 } }],
    },
  ],
};
```

## Phasen, Entscheidungen und Effekte

Projekte beginnen als `available` und werden gegen `startCost` gestartet. Ereignisse beginnen direkt in ihrer ersten Arbeits- oder Entscheidungsphase. Arbeitsphasen benötigen Fortschritt und einen `threshold`; beim Erreichen werden ihre Effekte einmalig angewandt und die nächste Phase betreten. Fortschritt wird täglich deterministisch integriert: `rate + rateBonus + passende rates + Zufall innerhalb ±volatility`. Negative Tage sind möglich; bei `failAtZero` kann ein Vorhaben scheitern. Pausen frieren den Fortschritt ein.

Phasen mit `choices` halten die Arbeit an. Optionen können Kosten, Bedingungen, Effekte, Fortschrittsänderungen, dauerhafte Ratenänderungen, eine benannte Folgephase (`next`) oder einen Endzustand (`finish`) enthalten. Ohne `next` folgt die nächste Phase. `timeoutDays` erfordert eine bedingungslose kostenlose `fallback`-Option. Ohne Frist bleibt die Entscheidung offen. Der Pool wird beim Laden auf grundlegende Strukturfehler geprüft.

Effekte buchen Ressourcen, setzen Flags, installieren Reichs-/Speziesmodifikatoren, erhöhen eine Speziesgeneration, öffnen Folgeprojekte oder verwenden vorhandene Krisenaktionen. Die Zielspezies wird bei Projektanlage gespeichert. Kosten und Effekte laufen gemeinsam in einer autoritativen Transaktion; alte Revisionen und fremde Vorgänge werden zurückgewiesen. Lesebestätigungen beziehen sich separat auf die Meldungsnummer und sind idempotent.

## Präsentation

Die Bausteine `text`, `dialogue` (optional mit Portrait), `image`, `map` und `callout` lassen sich je Phase frei kombinieren. Texte unterstützen `{{system}}`, `{{species}}` und `{{empire}}`. Medien liegen beispielsweise unter `public/events/`; Referenzen sind normale Asset-Pfade. Die Fundortkarte verwendet echte System- und Hyperlanedaten.

`EventContent`, `EventProgress`, `EventCosts`, `EventLocationMap` und `EventPanel` sind wiederverwendbare Komponenten. `EventWorkspace` ergänzt Übersicht, Suche, Filter, Archiv und Details; `EventAnnouncement` meldet Funde und Phasenwechsel. Neue Block- oder Effekttypen werden zentral in Typdefinition, Renderer beziehungsweise Effektverarbeitung ergänzt.

Tests gehören zur Zustandsmaschine, Rechteprüfung, Kostenbuchung und Persistenz. Einzelne neue Geschichten brauchen keine eigene Testsuite.
