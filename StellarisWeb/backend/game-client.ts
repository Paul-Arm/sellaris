import { GALAXY_QUERIES, type Client } from './client';
import { isShipSet } from '../shared/shipSets';
import { progressAt } from './domain';
import { ProjectionCache, watchTables, type ReadTable } from './projection-cache';
import { gameDay, travelProgress } from '../shared/time';
import type { GameView, Player, ShipType, TechId } from '../shared/game';
import type { Colony } from '../shared/colonies';
import type { TreatyOffer, Relation } from '../shared/diplomacy';
import { crisisProductionFactor, type CrisisView, type StoryKind } from '../shared/stories';
import { facilityYield, type Facility, type BodySite } from '../shared/celestial';
import { stellarClass, stellarProfile } from '../shared/stellar';

export const GAME_QUERIES = [
  ...GALAXY_QUERIES,
  ...[
    'game_settings',
    'game_lane',
    'game_presence',
    'game_atlas',
    'game_players',
    'my_game_player',
    'game_intel',
    'game_fleet_info',
    'my_game_events',
    'game_relation',
    'my_game_offers',
    'my_game_stories',
    'game_crisis',
    'my_crisis_pledges',
    'visible_game_sites',
    'my_terraform_projects',
  ].map((t) => `SELECT * FROM ${t}`),
];
/** Project authorized subscription rows into the existing presentation model.
 * Local time advances bars and strategic fleet positions, never authoritative resources. */
const caches = new WeakMap<Client, ProjectionCache>();
export function gameView(client: Client): GameView | null {
  let cache = caches.get(client);
  if (!cache) caches.set(client, (cache = new ProjectionCache()));
  const memo = cache.get.bind(cache);
  const read = <R extends { id: unknown }>(_key: string, table: ReadTable<R>) => cache.table(table);
  const db = client.conn.db,
    config = [...db.gameSettings.iter()][0],
    p = [...db.myGamePlayer.iter()][0],
    e = [...db.myEmpire.iter()][0],
    clock = [...db.clock.iter()][0];
  if (!config || !p || !e || !clock) return null;
  const at = gameDay(client.clock.now());
  const index = <R extends { id: number }>(key: string, table: ReadTable<R>) => {
    const rows = read(key, table);
    return memo(`${key}-index`, [rows], () => new Map(rows.map((r) => [r.id, r])));
  };
  const atlas = index('atlas', db.gameAtlas),
    players = index('players', db.gamePlayers);
  const summary = index('summary', db.empireSummary),
    presence = index('presence', db.gamePresence);
  const intel = index('intel', db.gameIntel),
    infos = index('infos', db.gameFleetInfo);
  const stars = index('stars', db.star);
  const jobs = memo('jobs', [read('jobRows', db.myJobs)], () =>
    [...db.myJobs.iter()]
      .filter((j) => ['active', 'queued', 'blocked'].includes(j.status))
      .sort((a, b) => a.id - b.id),
  );
  const remaining = (j: (typeof jobs)[number]) =>
    Math.max(0, j.workTotal - (j.status === 'active' ? progressAt(j, client.clock.now()) : j.workDone));
  const systemId = (id: number) => atlas.get(id)?.externalId || '';
  const crises: CrisisView[] = [...db.gameCrisis.iter()].flatMap((meta) => {
    const crisis = db.crisis.id.find(meta.id);
    if (!crisis) return [];
    const pledge = [...db.myCrisisPledges.iter()].find((v) => v.crisisId === meta.id);
    return [
      {
        ...meta,
        systemId: systemId(crisis.systemId),
        phase: crisis.phase as CrisisView['phase'],
        nextPhaseAt: crisis.nextPhaseAt,
        contributions: pledge?.contributions || 0,
        shielded: pledge?.shielded || false,
      },
    ];
  });
  const factor = Math.min(1, ...crises.map((c) => crisisProductionFactor(c.phase, c.shielded)));
  const sites: BodySite[] = memo(
    'sites',
    [read('siteRows', db.visibleGameSites), atlas, players, stars],
    () =>
      [...db.visibleGameSites.iter()].map((site) =>
        memo(site, [atlas, players, stars.get(site.systemId)], () => ({
          id: site.id,
          systemId: systemId(site.systemId),
          bodySlot: site.bodySlot,
          owner: players.get(site.empireId)?.externalId || '',
          facility: site.facility as Facility,
          level: site.level,
          building: site.building,
          startedAt: site.startedAt,
          finishAt: site.finishAt,
          suspended:
            stars.get(site.systemId)?.kind === 'star' && stars.get(site.systemId)?.ownerId !== site.empireId,
        })),
      ),
  );
  const installationIncome = { energy: 0, minerals: 0, science: 0 };
  for (const site of sites)
    if (site.owner === p.externalId && !site.suspended) {
      const rate = facilityYield(site.facility, site.level, factor);
      installationIncome.energy += rate.energy;
      installationIncome.minerals += rate.minerals;
      installationIncome.science += rate.science;
    }
  const systems = memo('systems', [stars, atlas, intel, players, jobs, factor, p.id], () =>
    [...stars.values()].flatMap((s) => {
      const m = atlas.get(s.id);
      if (!m) return [];
      const upgrade = jobs.find((j) => j.kind === 'game_upgrade' && j.targetId === s.id);
      return [
        memo(s, [m, intel.get(s.id), upgrade, players, factor, p.id], () => {
          const i = intel.get(s.id),
            colony: Colony | null = i?.colonyJson ? JSON.parse(i.colonyJson) : null;
          if (colony?.construction && upgrade)
            Object.defineProperty(colony.construction, 'remaining', {
              enumerable: true,
              get: () => remaining(upgrade),
            });
          const descriptor = {
            id: m.externalId,
            kind: s.kind as 'star' | 'rift' | 'blackhole',
            class: m.starClass,
            color: m.color,
          };
          const starClass = stellarClass(descriptor);
          return {
            id: m.externalId,
            name: s.name,
            x: s.x,
            y: s.y,
            color: starClass === m.starClass ? m.color : stellarProfile(descriptor).color,
            kind: s.kind as 'star' | 'rift' | 'blackhole',
            class: starClass,
            planet: m.planet,
            owner: s.ownerId ? players.get(s.ownerId)?.externalId || null : null,
            resources: { energy: i?.energy || 0, minerals: i?.minerals || 0, science: i?.science || 0 },
            productionFactor: s.ownerId === p.id ? factor : 1,
            defense: i?.defense || 0,
            mined: i?.mined || false,
            anomaly: m.anomaly,
            studied: i?.studied || false,
            colony,
            colonyName: i?.colonyName || undefined,
          };
        }),
      ];
    }),
  );
  const research = jobs.find((j) => j.kind === 'game_research'),
    identity = summary.get(p.id)!;
  const me: Player = memo('me', [p, e, research, jobs, identity, factor, sites, atlas], () => ({
    id: p.externalId,
    name: identity.name,
    color: `#${identity.color.toString(16).padStart(6, '0')}`,
    home: systemId(p.homeId),
    resources: { energy: e.energy, minerals: e.minerals, science: e.science },
    techs: p.techs as TechId[],
    surveyed: p.surveyed.map(systemId),
    discovered: p.discovered.map(systemId),
    installationIncome,
    empire: memo('empireJson', [p.empireJson], () => JSON.parse(p.empireJson)),
    online: true,
    research: research
      ? {
          id: research.topic as TechId,
          total: research.workTotal,
          get remaining() {
            return remaining(research);
          },
        }
      : null,
    queue: jobs
      .filter((j) => j.kind === 'game_build')
      .map((j) => ({
        type: j.topic as ShipType,
        systemId: systemId(j.targetId),
        get remaining() {
          return remaining(j);
        },
        total: j.workTotal,
      })),
  }));
  const tasks = new Map(
    jobs.filter((j) => ['game_scan', 'game_colonize'].includes(j.kind)).map((j) => [j.targetId, j]),
  );
  return {
    version: 1,
    displayClock: client.clock,
    code: config.code,
    tick: at,
    speed: clock.speed,
    paused: clock.paused,
    hostId: players.get(config.hostId)?.externalId || '',
    winner: config.winnerId ? players.get(config.winnerId)?.externalId || null : null,
    capacity: config.capacity,
    backend: 'spacetimedb',
    crises,
    sites,
    decisions: [...db.myDecisions.iter()].flatMap((d) => {
      const story = db.myGameStories.id.find(d.id);
      return story
        ? [
            {
              ...d,
              kind: d.kind as StoryKind,
              systemId: systemId(story.systemId),
              createdAt: story.createdAt,
              resolvedAt: story.resolvedAt,
              result: story.result,
            },
          ]
        : [];
    }),
    relations: [...db.gameRelation.iter()].map((r) => ({
      ...r,
      empireA: players.get(r.empireA)?.externalId || '',
      empireB: players.get(r.empireB)?.externalId || '',
      state: r.state as Relation['state'],
    })),
    offers: [...db.myTreaties.iter()].flatMap((t) => {
      const o = db.myGameOffers.id.find(t.id);
      return o
        ? [
            {
              ...t,
              give: o.give,
              receive: o.receive,
              empireA: players.get(t.empireA)?.externalId || '',
              empireB: players.get(t.empireB)?.externalId || '',
              kind: t.kind as TreatyOffer['kind'],
              status: t.status as TreatyOffer['status'],
            },
          ]
        : [];
    }),
    systems,
    links: memo('links', [read('lanes', db.gameLane), atlas], () =>
      [...db.gameLane.iter()].map((l): [string, string] => [systemId(l.a), systemId(l.b)]),
    ),
    me,
    players: memo('publicPlayers', [players, summary, presence], () =>
      [...players.values()].map((p) =>
        memo(p, [summary.get(p.id), presence.get(p.id)], () => {
          const s = summary.get(p.id)!;
          return {
            id: p.externalId,
            name: s.name,
            color: `#${s.color.toString(16).padStart(6, '0')}`,
            online: presence.get(p.id)?.online || false,
            colonies: p.colonies,
            ai: s.ai,
            flag: JSON.parse(p.flagJson),
            shipSet: isShipSet(p.shipSet) ? p.shipSet : 'prisma',
          };
        }),
      ),
    ),
    fleets: memo('fleets', [read('fleetRows', db.galaxyFleets), infos, players, atlas, jobs], () =>
      [...db.galaxyFleets.iter()].flatMap((f) => {
        const m = infos.get(f.id);
        if (!m) return [];
        const task = tasks.get(f.id),
          duration = f.arrivesAt - f.departedAt;
        return [
          memo(f, [m, task, players, atlas], () => ({
            id: m.externalId,
            nativeId: f.id,
            navigation: m.navigationJson ? JSON.parse(m.navigationJson) : undefined,
            owner: players.get(f.empireId)?.externalId || '',
            name: f.name,
            type: m.kind as ShipType,
            systemId: systemId(f.systemId || m.lastSystemId),
            route: m.route.map(systemId),
            duration,
            journey: {
              fromX: f.fromX,
              fromY: f.fromY,
              toX: f.toX,
              toY: f.toY,
              departedAt: f.departedAt,
              arrivesAt: f.arrivesAt,
            },
            get progress() {
              return m.route.length ? travelProgress(f, client.clock.now()) : 0;
            },
            hp: m.maxHull ? (100 * m.hull) / m.maxHull : 0,
            shipCount: f.shipCount,
            battleId: f.battleId,
            task: task
              ? {
                  type: task.kind === 'game_scan' ? ('scan' as const) : ('colonize' as const),
                  total: task.workTotal,
                  get remaining() {
                    return remaining(task);
                  },
                  blocked: task.status === 'blocked',
                }
              : null,
          })),
        ];
      }),
    ),
    log: memo('log', [read('eventRows', db.myGameEvents)], () =>
      [...db.myGameEvents.iter()]
        .sort((a, b) => b.id - a.id)
        .map((l) => ({
          id: l.id,
          tick: l.tick,
          text: l.text,
          tone: l.tone as 'info' | 'success' | 'warning',
        })),
    ),
    nextId: 0,
  };
}

/** One publication per completed subscription transaction, no projection timer. */
export function observeGame(client: Client, publish: (view: GameView | null) => void) {
  const db = client.conn.db;
  const unwatch = watchTables(
    [
      db.gameSettings,
      db.myGamePlayer,
      db.myEmpire,
      db.gameAtlas,
      db.gamePlayers,
      db.empireSummary,
      db.gamePresence,
      db.gameIntel,
      db.gameFleetInfo,
      db.myJobs,
      db.star,
      db.visibleGameSites,
      db.gameCrisis,
      db.crisis,
      db.myCrisisPledges,
      db.myDecisions,
      db.myGameStories,
      db.gameRelation,
      db.myTreaties,
      db.myGameOffers,
      db.gameLane,
      db.galaxyFleets,
      db.myGameEvents,
      db.visibleBattleSummaries,
    ],
    () => publish(gameView(client)),
  );
  publish(gameView(client));
  return () => {
    unwatch();
    caches.get(client)?.dispose();
    caches.delete(client);
  };
}
