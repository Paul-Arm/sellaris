import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const directory = resolve('backend/reports');
const names = [
  'network-heavy-legacy-none-1x', 'network-heavy-compact-none-1x',
  'network-heavy-compact-gzip-1x', 'network-heavy-compact-gzip-10x', 'large-compact-gzip-1x',
];
const reports = names.map(name => JSON.parse(readFileSync(resolve(directory, `${name}.json`), 'utf8')));
const [baseline, compact, gzip, fanout, multiple] = reports;
if (new Set(reports.map(r => r.clientSha256)).size !== 1 || new Set(reports.map(r => r.simulationSha256)).size !== 1)
  throw new Error('Comparison requires identical simulation and client versions');
if (reports.some(r => r.assertions.errors.length)) throw new Error('A load run failed integrity checks');
const f = (value, decimals = 1) => value == null ? '—' : value.toLocaleString('de-DE', {maximumFractionDigits: decimals, minimumFractionDigits: decimals});
const battleClients = r => r.network.perClient.filter(c => c.mode === 'battle');
const average = list => list.reduce((sum, value) => sum + value, 0) / list.length;
const rate = r => average(battleClients(r).map(c => c.downstreamKiBPerSecond));
const combat = r => r.nativeReducers.find(m => m.reducer === 'combat_tick');
const joins = (r, kind) => r.joins.samples.filter(j => j.mode === 'battle' && j.kind === kind).map(j => j.ms);
const drop = 100 * (1 - rate(gzip) / rate(baseline));
const totalSnapshots = reports.reduce((sum, r) => sum + r.assertions.snapshotsChecked, 0);
const totalReconnects = reports.reduce((sum, r) => sum + r.joins.reconnectMs.count, 0);
const columns = [baseline, compact, gzip];
const row = (label, fn) => `| ${label} | ${columns.map(fn).join(' | ')} |`;
const text = `# Gefechtstransport: kompakte Ansichten und Gzip

**${f(drop)} % weniger empfangene Daten je Gefechtsansicht im lokalen Vergleich:** von **${f(rate(baseline))} auf ${f(rate(gzip))} KiB/s** bei 3.000 gleichzeitig simulierten Kampfteilnehmern. Die Simulationsgenauigkeit und Taktung wurden nicht reduziert.

## Was geändert wurde

- Drei berechtigte Views trennen Zugehörigkeit, Bewegung und Kampfstatus. Unveränderte Zugehörigkeit wird nicht bei jedem Bewegungsschritt erneut gesendet. Der vollständige dauerhafte Kampfzustand bleibt erhalten.
- Gzip komprimiert SpacetimeDB-Nachrichten. Der Client entpackt alle Nachrichten strikt in Empfangsreihenfolge, auch wenn komprimierte Initialsnapshots und kleine unkomprimierte Folgeupdates abwechseln.
- Der Renderer hält die Zugehörigkeit in einer Map aktuell. SDK 2.10 durchsucht bei **index.find()** derzeit den lokalen Cache; eine solche Suche für jedes Schiff in jedem Frame wäre quadratisch. Auch die Snapshot-Prüfung des Lastclients verwendet jetzt Maps.
- Die neuen Views sind additiv. Die vorhandenen Labordatenbanken wurden ohne Löschung oder erneutes Seeden aktualisiert; der spielbare Alpha-Server bleibt getrennt.

## Vergleich unter gleichen Szenariobedingungen

${baseline.hardware.cpu}, ${baseline.hardware.logicalCpus} logische CPUs, ${f(baseline.hardware.ramGiB)} GiB RAM, Windows ${baseline.hardware.osRelease}, Node ${baseline.hardware.node}, SpacetimeDB ${baseline.spacetimedbVersion}. Loopback: Server und Lastclients teilen denselben Rechner. Gewöhnliche Desktop-Hintergrundlast ist nicht ausgeschlossen.

Je Lauf: 1.000 Systeme, 25 verschiedene Spieleridentitäten/Autopiloten, 1.250 anfängliche Flotten, 75.000 anfängliche Schiffe, 250 Kolonien, 1.000 Pop-Kohorten und 100.000 Pops. 50 Flotten bilden eine Schlacht mit 3.000 Teilnehmern. Eine Verbindung beobachtet die Schlacht und ihre eigene ausgewählte Flotte, 24 erhalten Galaxiedaten. Drei Sekunden Aufwärmphase; je ${columns.map(r => f(r.measuredSeconds)).join(' / ')} Sekunden Messzeit. Wiederverbindungen alle 2,5 Sekunden.

| Messwert | Vollansicht, unkomprimiert | Kompakte Views, unkomprimiert | Kompakte Views, Gzip |
|---|---:|---:|---:|
${row('Empfang je Gefechtsclient, KiB/s', r => f(rate(r)))}
${row('Alle 25 Clients, KiB/s', r => f(r.network.downstreamKiBPerSecond))}
${row('Initialer Gefechtsbeitritt, ms', r => f(joins(r, 'hot-join')[0]))}
${row('Gefechts-Reconnect, ms (ein Messpunkt)', r => f(joins(r, 'reconnect')[0]))}
${row('Reconnect p95 über alle 24 Wiederverbindungen, ms', r => f(r.joins.reconnectMs.p95))}
${row('Maximaler Reconnect über alle Verbindungen, ms', r => f(r.joins.reconnectMs.max))}
${row('Kampf-Reducer inkl. Subscription-Auswertung, Mittel ms', r => f(combat(r).meanExecutionAndSubscriptionMs, 2))}
${row('Kampf-Reducer p95, Histogrammobergrenze ms', r => '≤' + f(combat(r).p95UpperBoundMs, 0))}
${row('Kampfrückstand p95, ms', r => f(r.schedulerLagMs.combat.p95))}
${row('Maximal abgetasteter Kampfrückstand, ms', r => f(r.schedulerLagMs.combat.max))}
${row('Konsistente Beitritts-/Reconnect-Snapshots', r => f(r.assertions.snapshotsChecked, 0))}

Die Aufteilung allein spart **${f(100 * (1 - rate(compact) / rate(baseline)))} %**; Gzip spart gegenüber dem bereits kompakten Format weitere **${f(100 * (1 - rate(gzip) / rate(compact)))} %**. Es handelt sich um fünf 200-ms-Kampfschritte je Spielsekunde und weiterhin f32-Positionen/Geschwindigkeiten. Aufrufe des Kampf-Reducers erfolgen alle 100 ms und können ohne fälligen Schritt enden; deren Zeitmittel sind deshalb keine reinen Kosten eines vollständigen Kampfschritts.

Gemessen werden tatsächliche binäre WebSocket-Nachrichtenbytes **vor** dem Entpacken, einschließlich der Reconnect-Snapshots, ohne HTTP-Authentifizierung und TCP/TLS/WebSocket-Framing. Die Gzip-Gefechtsverbindung verarbeitete ${f(battleClients(gzip)[0].compressedFrames, 0)} komprimierte Nachrichten; ihr Spitzenwert an noch nicht fertig verarbeiteten Nachrichtenbytes betrug ${f(battleClients(gzip)[0].peakPendingBytes / 1024)} KiB. Die Summe der Entpack-Wandzeiten lag bei ${f(battleClients(gzip)[0].decodeMs)} ms über den Messlauf; das ist keine isolierte CPU-Zeit. Native Reducer-Histogramme ersetzen keine separate Messung des Kompressions-/Netzwerkdienstes.

## Mehrere gleichzeitige Empfänger

| Last | Zehn Ansichten derselben großen Schlacht | Fünf verschiedene Gefechte |
|---|---:|---:|
| Spieleridentitäten / Verbindungen | ${fanout.workload.connectedIdentities} / ${fanout.workload.connectedClients} | ${multiple.workload.connectedIdentities} / ${multiple.workload.connectedClients} |
| Gefechte × Teilnehmer beim Start | 1 × 3.000 | 5 × 600 |
| Verbindungen mit Gefechtsdetails | ${fanout.workload.detailedBattleClients} | ${multiple.workload.detailedBattleClients} |
| Empfang je Gefechtsclient, Mittel KiB/s | ${f(rate(fanout))} | ${f(rate(multiple))} |
| Empfang aller Clients, KiB/s | ${f(fanout.network.downstreamKiBPerSecond)} | ${f(multiple.network.downstreamKiBPerSecond)} |
| Kampf-Reducer inkl. Subscriptions, Mittel ms | ${f(combat(fanout).meanExecutionAndSubscriptionMs, 2)} | ${f(combat(multiple).meanExecutionAndSubscriptionMs, 2)} |
| Kampfrückstand p95 / maximal, ms | ${f(fanout.schedulerLagMs.combat.p95)} / ${f(fanout.schedulerLagMs.combat.max)} | ${f(multiple.schedulerLagMs.combat.p95)} / ${f(multiple.schedulerLagMs.combat.max)} |
| Reconnect p95 / maximal, ms | ${f(fanout.joins.reconnectMs.p95)} / ${f(fanout.joins.reconnectMs.max)} | ${f(multiple.joins.reconnectMs.p95)} / ${f(multiple.joins.reconnectMs.max)} |
| Geprüfte Snapshots | ${fanout.assertions.snapshotsChecked} | ${multiple.assertions.snapshotsChecked} |
| Dauer, Sekunden | ${f(fanout.measuredSeconds)} | ${f(multiple.measuredSeconds)} |

Die zusätzlichen neun Verbindungen zur großen Schlacht verwenden dieselbe berechtigte Spieleridentität wie der erste Gefechtsclient. Sie testen Übertragungsvervielfachung und Wiederverwendung der View, **nicht zehn unabhängige Zuschaueridentitäten**. Es wird keine Sichtbarkeitsregel umgangen oder erweitert. Unterschiedliche Zuschaueridentitäten, Allianzen und eine produktive Zuschauerregel brauchen einen weiteren Test. Bei den fünf getrennten Gefechten hat jeder Beobachter eine eigene Spieleridentität.

## Integrität und Browserprüfung

Über die fünf abschließenden Lastläufe: **${totalSnapshots} konsistente Initial-/Reconnect-Snapshots**, davon **${totalReconnects} Wiederverbindungen**, keine gemeldeten Integritätsfehler oder unerwarteten Verbindungsabbrüche.

**27 Spiel-/Domänen-/Transporttests und 12 native SpacetimeDB-Testfälle bestanden; TypeScript und Produktionsbuild erfolgreich.** Neue Prüfungen vergleichen die kompakten Views mit dem vollständigen Teilnehmerzustand, auch innerhalb von Transaktionscallbacks. Sie prüfen leere SQL-/Subscription-Ergebnisse für unberechtigte Identitäten, Fokuswechsel, unveränderte Zugehörigkeit bei Bewegung, atomaren Rückzug und Kampfabschluss sowie Rekonstruktion nach erzwungenem Serverneustart. Transporttests prüfen Nachrichtenreihenfolge, beschädigte Gzip-Daten, Verbindungsabbruch und Empfangsüberlast.

Im integrierten Browser wurden 1.000 Sterne/75.000 ursprüngliche Schiffe, eine Live-Ansicht mit 3.000 Kampfteilnehmern, Fokuswechsel, Wiederverbindung mit demselben Imperium und die Rückkehr zum normalen Spiel geprüft. Keine Browserwarnungen/-fehler wurden dabei erfasst. Die Datenanzeige verwendet KiB/s und den komprimierten Empfang. Das war eine Funktionsprüfung in einem anderen Browserkontext als der frühere FPS-Test; **kein neuer vergleichbarer FPS-Benchmark**. Die frühere Angabe von 165 FPS bleibt als vom Nutzer bestätigter Refresh-Cap dokumentiert und erlaubt keine Aussage über Leistungsreserven.

## Grenzen und nächste Schritte

Das Format spart Netzwerkvolumen, aber die simulierten Bewegungen werden weiterhin als einzelne persistente Zeilen geschrieben. Log-Wachstum und Server-Dauerlast wurden mit diesen kurzen Läufen nicht abschließend bewertet. WAN-Latenz/Paketverlust, längere Last- und Ausfalltests, Uhrabgleich, Wiederherstellung nach langen Ausfällen und komplexere Kampfregeln bleiben vor der Spielmigration offen.

Rohdaten: ${names.map((name, i) => '[' + ['Vollansicht', 'kompakt', 'kompakt + Gzip', 'zehn Empfänger', 'fünf Gefechte'][i] + '](' + name + '.json)').join(', ')}. Alle fünf Reports enthalten denselben Simulations- und Client-Fingerprint. Frühere Diagnoseläufe mit quadratischer Clientprüfung sind separat unter [diagnostic-pre-index](diagnostic-pre-index/README.md) erhalten und nicht Grundlage der obigen Vergleichswerte.

Reproduktion nach Backendbuild und Start: **node backend/compare-network.mjs 60**, anschließend **node backend/report-network.mjs**. Alle fünf Läufe werden nacheinander ausgeführt; währenddessen keine Builds oder weiteren Lasttests starten. Details zum Start und zu Einzeloptionen: [Backend-Anleitung](../README.md). Die aktuellen Views unterstützen weiterhin **--detail=legacy --compression=none** für Vergleiche.
`;
writeFileSync(resolve(directory, 'NETWORK.md'), text);
console.log(JSON.stringify({ report: resolve(directory, 'NETWORK.md'), reductionPercent: drop, baselineKiBs: rate(baseline), optimizedKiBs: rate(gzip), snapshots: totalSnapshots }, null, 2));
