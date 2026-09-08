export { mySituations } from './game-situations';
import { db } from './tables';
export { sampleClock } from './clock';
export default db;
export { myResearch } from './game-research';
export { visibleStellarWeather } from './game-stellar-weather';
export { renameBody, focusSystemObjects, focusedSystemObjects, focusedObjectSystems } from './game-objects';
export { startTerraforming, cancelTerraforming, myTerraformProjects } from './game-terraforming';
export { visibleGameSites } from './game-views';
export {
  initializeGame,
  reserveGameSeat,
  redeemGameSeat,
  gameConnected,
  gameDisconnected,
} from './game-world';
export { gameCommand } from './game-commands';
export { myPlanetColonies } from './game-planet-colonies';
export { administerGame } from './game-admin';
export { myCrisisPledges } from './game-views';
export { myGameOffers } from './game-views';
export { myGamePlayer, gameAtlas, gamePlayers, gameIntel, gameFleetInfo, myGameEvents } from './game-views';
export const init = db.init((ctx) => {
  ctx.db.administrator.insert({ id: 1, identity: ctx.sender });
});
export { configure, seedShips, activate } from './seed';
export {
  joinEmpire,
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
  visibleBattleSummaries,
  focusedBattle,
  battleRoster,
  battleMotion,
  battleVitals,
  myTreaties,
  myDecisions,
  myTrade,
  diagnostics,
} from './views';
