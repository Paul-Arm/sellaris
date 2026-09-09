import type { GameCommand } from './game';

export type FleetGroupOrder =
  | { type: 'local_move'; systemId: string; point: import('./navigation').Point3; append?: boolean }
  | { type: 'move'; systemId: string; append?: boolean }
  | { type: 'fleet_stop' };
export type FleetGroupCommand = { type: 'fleet_group'; fleetIds: string[]; order: FleetGroupOrder };
export const MAX_FLEET_GROUP = 128;

/** One reducer transaction, bounded work, no nested or unrelated commands. */
export function fleetGroupCommands(command: FleetGroupCommand): GameCommand[] {
  const { fleetIds, order } = command;
  if (
    !Array.isArray(fleetIds) ||
    !fleetIds.length ||
    fleetIds.length > MAX_FLEET_GROUP ||
    fleetIds.some((id) => typeof id !== 'string' || !id || id.length > 120) ||
    new Set(fleetIds).size !== fleetIds.length
  )
    throw new Error(`Wähle 1–${MAX_FLEET_GROUP} unterschiedliche Flotten.`);
  if (!order || !['local_move', 'move', 'fleet_stop'].includes(order.type))
    throw new Error('Ungültiger Gruppenbefehl.');
  return fleetIds.map((fleetId) => {
    if (order.type === 'fleet_stop') return { type: 'fleet_stop', fleetId };
    if (order.type === 'move')
      return { type: 'move', fleetId, systemId: order.systemId, append: order.append };
    return {
      type: 'local_move',
      fleetId,
      systemId: order.systemId,
      point: order.point,
      append: order.append,
    };
  });
}
