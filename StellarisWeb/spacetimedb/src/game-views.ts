import { t } from 'spacetimedb/server';
import { db } from './tables';
import { gamePlayer, gameEvent, gameOffer, gameStory, gameCrisisPledge, gameSite } from './game-tables';
import { visibleSystems } from './rules';
import { flagForEmpire } from '../../shared/flags';
import { shipSetFor } from '../../shared/shipSets';

export const visibleGameSites = db.view(
  { name: 'visible_game_sites', public: true },
  t.array(gameSite.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const visible = visibleSystems(ctx, m.empireId);
    const rows = [...ctx.db.gameSite.empireId.filter(m.empireId)];
    for (const id of visible)
      for (const site of ctx.db.gameSite.systemId.filter(id)) {
        if (site.empireId === m.empireId || !site.level) continue;
        rows.push({
          ...site,
          building: false,
          startedAt: 0,
          finishAt: 0,
          finishTick: 0n,
          paidEnergy: 0,
          paidMinerals: 0,
          lastProducedAt: 0,
        });
      }
    return rows;
  },
);
export const myGameStories = db.view(
  { name: 'my_game_stories', public: true },
  t.array(gameStory.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    return m
      ? [...ctx.db.decision.empireId.filter(m.empireId)].flatMap((d) => {
          const story = ctx.db.gameStory.id.find(d.id);
          return story ? [story] : [];
        })
      : [];
  },
);
export const myCrisisPledges = db.view(
  { name: 'my_crisis_pledges', public: true },
  t.array(gameCrisisPledge.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    return m ? [...ctx.db.gameCrisisPledge.empireId.filter(m.empireId)] : [];
  },
);

export const myGameOffers = db.view(
  { name: 'my_game_offers', public: true },
  t.array(gameOffer.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    return [...ctx.db.treaty.empireA.filter(m.empireId), ...ctx.db.treaty.empireB.filter(m.empireId)].flatMap(
      (t) => {
        const o = ctx.db.gameOffer.id.find(t.id);
        return o ? [o] : [];
      },
    );
  },
);

export const myGamePlayer = db.view(
  { name: 'my_game_player', public: true },
  t.option(gamePlayer.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    return m ? (ctx.db.gamePlayer.id.find(m.empireId) ?? undefined) : undefined;
  },
);
export const gameAtlas = db.view(
  { name: 'game_atlas', public: true },
  t.array(
    t.row('GameAtlasRow', {
      id: t.u32().primaryKey(),
      externalId: t.string(),
      color: t.string(),
      starClass: t.string(),
      planet: t.string(),
      anomaly: t.bool(),
    }),
  ),
  (ctx) =>
    [...ctx.db.gameSystem.iter()].map(({ id, externalId, color, starClass, planet, anomaly }) => ({
      id,
      externalId,
      color,
      starClass,
      planet,
      anomaly,
    })),
);
export const gamePlayers = db.view(
  { name: 'game_players', public: true },
  t.array(
    t.row('GamePlayerSummary', {
      id: t.u32().primaryKey(),
      externalId: t.string(),
      homeId: t.u32(),
      colonies: t.u32(),
      flagJson: t.string(),
      shipSet: t.string(),
    }),
  ),
  (ctx) =>
    [...ctx.db.gamePlayer.iter()].map((p) => ({
      id: p.id,
      externalId: p.externalId,
      homeId: p.homeId,
      colonies: [...ctx.db.colony.empireId.filter(p.id)].length,
      flagJson: JSON.stringify(flagForEmpire(JSON.parse(p.empireJson).design)),
      shipSet: shipSetFor(JSON.parse(p.empireJson).design),
    })),
);
export const gameIntel = db.view(
  { name: 'game_intel', public: true },
  t.array(
    t.row('GameIntelRow', {
      id: t.u32().primaryKey(),
      energy: t.f64(),
      minerals: t.f64(),
      data: t.f64(),
      defense: t.f64(),
      mined: t.bool(),
      studied: t.bool(),
      colonyName: t.string(),
      colonyJson: t.string(),
    }),
  ),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const p = ctx.db.gamePlayer.id.find(m.empireId);
    if (!p) return [];
    const visible = visibleSystems(ctx, m.empireId),
      ids = new Set([...p.surveyed, ...visible]);
    return [...ids].flatMap((id) => {
      const s = ctx.db.star.id.find(id),
        r = ctx.db.gameSystem.id.find(id);
      if (!s || !r) return [];
      return [
        {
          id,
          energy: r.energy,
          minerals: r.minerals,
          data: r.data,
          defense: visible.has(id) ? r.defense : 0,
          mined: r.mined,
          studied: r.studied,
          colonyName: r.colonyName,
          colonyJson: s.ownerId === m.empireId ? r.colonyJson : '',
        },
      ];
    });
  },
);
export const gameFleetInfo = db.view(
  { name: 'game_fleet_info', public: true },
  t.array(
    t.row('GameFleetInfoRow', {
      navigationJson: t.string(),
      id: t.u32().primaryKey(),
      externalId: t.string(),
      kind: t.string(),
      lastSystemId: t.u32(),
      route: t.array(t.u32()),
      hull: t.f64(),
      maxHull: t.f64(),
      shield: t.f64(),
    }),
  ),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const visible = visibleSystems(ctx, m.empireId),
      fleets = new Map([...ctx.db.fleet.empireId.filter(m.empireId)].map((f) => [f.id, f]));
    for (const id of visible) for (const f of ctx.db.fleet.systemId.filter(id)) fleets.set(f.id, f);
    return [...fleets.values()].flatMap((f) => {
      const r = ctx.db.gameFleet.id.find(f.id);
      if (!r) return [];
      const condition = ctx.db.gameFleetCondition.id.find(f.id);
      const nav = ctx.db.gameNavigation.id.find(f.id);
      return [
        {
          id: f.id,
          navigationJson: nav
            ? JSON.stringify({
                motion: JSON.parse(nav.motionJson),
                orders: f.empireId === m.empireId ? JSON.parse(nav.ordersJson) : [],
                phase: f.empireId === m.empireId ? nav.phase : '',
                visited: f.empireId === m.empireId ? nav.visited : [],
                targetSlot: f.empireId === m.empireId ? nav.targetSlot : 0,
                totalBodies: f.empireId === m.empireId ? nav.totalBodies : 0,
              })
            : '',
          externalId: r.externalId,
          kind: r.kind,
          lastSystemId: r.lastSystemId,
          route: f.empireId === m.empireId ? f.route : [],
          hull: condition?.hull ?? f.shipCount * 100,
          maxHull: condition?.maxHull ?? f.shipCount * 100,
          shield: condition?.shield ?? 0,
        },
      ];
    });
  },
);
export const myGameEvents = db.view(
  { name: 'my_game_events', public: true },
  t.array(gameEvent.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    return [...ctx.db.gameEvent.empireId.filter(0), ...ctx.db.gameEvent.empireId.filter(m.empireId)]
      .sort((a, b) => a.id - b.id)
      .slice(-64);
  },
);
