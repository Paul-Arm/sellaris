import { GALAXY_QUERIES, type Client } from './client';
import { gameTimeAt, progressAt } from './domain';
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
  ].map((t) => `SELECT * FROM ${t}`),
];
/** Project authorized subscription rows into the existing presentation model.
 * Local time advances bars and strategic fleet positions, never authoritative resources. */
export function gameView(client: Client): GameView | null {
  const db = client.conn.db,
    config = [...db.gameSettings.iter()][0],
    p = [...db.myGamePlayer.iter()][0],
    e = [...db.myEmpire.iter()][0],
    clock = [...db.clock.iter()][0];
  if (!config || !p || !e || !clock) return null;
  const at = gameTimeAt(clock, Date.now() / 1000);
  const atlas = new Map([...db.gameAtlas.iter()].map((s) => [s.id, s])),
    players = new Map([...db.gamePlayers.iter()].map((p) => [p.id, p]));
  const summary = new Map([...db.empireSummary.iter()].map((p) => [p.id, p])),
    presence = new Map([...db.gamePresence.iter()].map((p) => [p.id, p]));
  const intel = new Map([...db.gameIntel.iter()].map((s) => [s.id, s])),
    infos = new Map([...db.gameFleetInfo.iter()].map((f) => [f.id, f]));
  const jobs = [...db.myJobs.iter()]
    .filter((j) => ['active', 'queued', 'blocked'].includes(j.status))
    .sort((a, b) => a.id - b.id);
  const remaining = (j: (typeof jobs)[number]) =>
    Math.max(0, j.workTotal - (j.status === 'active' ? progressAt(j, at) : j.workDone));
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
  const sites: BodySite[] = [...db.visibleGameSites.iter()].map((site) => ({
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
      db.star.id.find(site.systemId)?.kind === 'star' &&
      db.star.id.find(site.systemId)?.ownerId !== site.empireId,
  }));
  const installationIncome = { energy: 0, minerals: 0, science: 0 };
  for (const site of sites)
    if (site.owner === p.externalId && !site.suspended) {
      const rate = facilityYield(site.facility, site.level, factor);
      installationIncome.energy += rate.energy;
      installationIncome.minerals += rate.minerals;
      installationIncome.science += rate.science;
    }
  const systems = [...db.star.iter()].flatMap((s) => {
    const m = atlas.get(s.id);
    if (!m) return [];
    const i = intel.get(s.id),
      colony: Colony | null = i?.colonyJson ? JSON.parse(i.colonyJson) : null;
    const upgrade = jobs.find((j) => j.kind === 'game_upgrade' && j.targetId === s.id);
    if (colony?.construction && upgrade) colony.construction.remaining = remaining(upgrade);
    const descriptor = {
      id: m.externalId,
      kind: s.kind as 'star' | 'rift' | 'blackhole',
      class: m.starClass,
      color: m.color,
    };
    const starClass = stellarClass(descriptor);
    return [
      {
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
      },
    ];
  });
  const research = jobs.find((j) => j.kind === 'game_research'),
    identity = summary.get(p.id)!;
  const me: Player = {
    id: p.externalId,
    name: identity.name,
    color: `#${identity.color.toString(16).padStart(6, '0')}`,
    home: systemId(p.homeId),
    resources: { energy: e.energy, minerals: e.minerals, science: e.science },
    techs: p.techs as TechId[],
    surveyed: p.surveyed.map(systemId),
    discovered: p.discovered.map(systemId),
    installationIncome,
    empire: JSON.parse(p.empireJson),
    online: true,
    research: research
      ? { id: research.topic as TechId, total: research.workTotal, remaining: remaining(research) }
      : null,
    queue: jobs
      .filter((j) => j.kind === 'game_build')
      .map((j) => ({
        type: j.topic as ShipType,
        systemId: systemId(j.targetId),
        remaining: remaining(j),
        total: j.workTotal,
      })),
  };
  const tasks = new Map(
    jobs.filter((j) => ['game_scan', 'game_colonize'].includes(j.kind)).map((j) => [j.targetId, j]),
  );
  return {
    version: 1,
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
    links: [...db.gameLane.iter()].map((l) => [systemId(l.a), systemId(l.b)]),
    me,
    players: [...players.values()].map((p) => {
      const s = summary.get(p.id)!;
      return {
        id: p.externalId,
        name: s.name,
        color: `#${s.color.toString(16).padStart(6, '0')}`,
        online: presence.get(p.id)?.online || false,
        colonies: p.colonies,
        ai: s.ai,
        flag: JSON.parse(p.flagJson),
      };
    }),
    fleets: [...db.galaxyFleets.iter()].flatMap((f) => {
      const m = infos.get(f.id);
      if (!m) return [];
      const task = tasks.get(f.id),
        duration = f.arrivesAt - f.departedAt;
      return [
        {
          id: m.externalId,
          nativeId: f.id,
          owner: players.get(f.empireId)?.externalId || '',
          name: f.name,
          type: m.kind as ShipType,
          systemId: systemId(f.systemId || m.lastSystemId),
          route: m.route.map(systemId),
          duration,
          progress: m.route.length
            ? Math.min(1, Math.max(0, (at - f.departedAt) / Math.max(0.001, duration)))
            : 0,
          hp: m.maxHull ? (100 * m.hull) / m.maxHull : 0,
          shipCount: f.shipCount,
          battleId: f.battleId,
          task: task
            ? {
                type: task.kind === 'game_scan' ? ('scan' as const) : ('colonize' as const),
                total: task.workTotal,
                remaining: remaining(task),
                blocked: task.status === 'blocked',
              }
            : null,
        },
      ];
    }),
    log: [...db.myGameEvents.iter()]
      .sort((a, b) => b.id - a.id)
      .map((l) => ({ id: l.id, tick: l.tick, text: l.text, tone: l.tone as 'info' | 'success' | 'warning' })),
    nextId: 0,
  };
}
