import { db } from './tables';
export default db;
export { visibleGameSites } from './game-views';
export {
  initializeGame,
  reserveGameSeat,
  redeemGameSeat,
  gameConnected,
  gameDisconnected,
} from './game-world';
export { gameCommand } from './game-commands';
export { initializeDiplomacy } from './game-diplomacy';
export { initializeStories } from './game-stories';
export { myGameStories, myCrisisPledges } from './game-views';
export { myGameOffers } from './game-views';
export { myGamePlayer, gameAtlas, gamePlayers, gameIntel, gameFleetInfo, myGameEvents } from './game-views';
export const init = db.init((ctx) => {
  ctx.db.administrator.insert({ id: 1, identity: ctx.sender });
});
export { configure, seedShips, activate } from './seed';
export {
  joinEmpire,
  initializeBattleReports,
  setFocus,
  setAutomation,
  moveFleet,
  splitFleet,
  mergeFleets,
  withdrawFleet,
  setClock,
  startJob,
  cancelJob,
} from './commands';
export { strategicTick, economyTick, combatTick, aiTick } from './simulation';
export {
  myEmpire,
  galaxyFleets,
  fleetShips,
  myColonies,
  myCohorts,
  myJobs,
  visibleBattles,
  visibleBattleSummaries,
  focusedBattle,
  battleParticipants,
  battleRoster,
  battleMotion,
  battleVitals,
  myTreaties,
  myDecisions,
  myTrade,
  diagnostics,
} from './views';
