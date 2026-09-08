import { gameIndices } from './game-indices';
import type { GameView, ShipType } from '../shared/game';
import type { BodySite, CelestialBody } from '../shared/celestial';
import { type ShipSet } from '../shared/shipSets';

export const SHIP_MODEL: Record<ShipType, string> = {
  corvette: '01_korvette',
  scout: '08_forschung',
  colony: '07_arbeiter',
};
export const STATION_MODELS = ['01_aussenposten', '02_sternenbasis', '03_festung', '04_zitadelle'];
export function playerShipSet(game: GameView, owner: string | null): ShipSet {
  if (!owner) return 'prisma'; // Neutral stations have their own default visual identity.
  return owner === game.me.id ? game.me.empire.design.shipSet : gameIndices(game).players.get(owner)!.shipSet;
}
export function facilityModel(site: BodySite, body: CelestialBody) {
  const level = site.level;
  if (site.facility === 'decompressor')
    return {
      id: level === 0 ? '05_construction_level_0' : level === 1 ? '01_mining_station' : '02_mining_ring',
      span: body.radius * (level >= 3 ? 6.5 : level >= 2 ? 4.5 : 1.8),
      centered: true,
      height: body.radius * (level < 2 ? 2.6 : 1.5),
    };
  if (site.facility === 'dyson')
    return {
      id: level < 2 ? '05_construction_level_0' : '03_dyson_swarm',
      span: body.radius * (level >= 3 ? 7 : level >= 2 ? 5 : 3),
      centered: true,
    };
  if (body.kind === 'station')
    return {
      id: level ? STATION_MODELS[Math.min(3, level - 1)] : '05_construction_level_0',
      span: 30 + level * 6,
      centered: true,
    };
  if (!level && site.building) return { id: '05_construction_level_0', span: 30, centered: false };
  if (site.facility === 'solar') return { id: '03_dyson_swarm', span: body.radius * 5, centered: true };
  if (site.facility === 'habitat' && level >= 3)
    return { id: 'orbital_ring', span: body.radius * 4, centered: true, planetRadius: body.radius * 1.05 };
  if (site.facility === 'mine' && level >= 2)
    return { id: '02_mining_ring', span: body.radius * 3.8, centered: true };
  if (site.facility === 'mine' || site.facility === 'gas')
    return { id: '01_mining_station', span: 25 + level * 3, centered: false };
  return { id: STATION_MODELS[Math.max(0, Math.min(3, level - 1))], span: 24 + level * 6, centered: false };
}
