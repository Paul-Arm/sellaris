import { useId, useMemo, useState } from 'react';
import { Globe2, Rocket } from 'lucide-react';
import type { Fleet, GameView } from '../shared/game';
import { ColonyTree } from './ColonyTree';
import { FleetInventory } from './FleetInventory';
import { colonyInventory, fleetCategories, type ColonyEntry } from './inventory-model';
import './inventory.css';

const icons = { colonies: Globe2, ships: Rocket };
export function EmpireInventory({ game, selectedColony, selectedFleet, onColony, onFleet, onOpenColony, onOpenFleet, section, onSection }: {
  game: GameView; selectedColony: string | null; selectedFleet: string | null;
  onColony: (colony: ColonyEntry) => void; onFleet: (fleet: Fleet) => void;
  onOpenColony?: (colony: ColonyEntry) => void; onOpenFleet?: (fleet: Fleet) => void;
  section: 'colonies' | 'ships'; onSection: (section: 'colonies' | 'ships') => void;
}) {
  const id = useId();
  const tab = section, setTab = onSection;
  const [shipTab, setShipTab] = useState<'civil' | 'research' | 'military'>('civil');
  const colonies = useMemo(() => colonyInventory(game), [game.systems, game.planetColonies, game.me.id, game.me.empire]);
  const totals = useMemo(() => {
    const counts = { civil: 0, research: 0, military: 0 };
    for (const fleet of game.fleets) {
      if (fleet.owner !== game.me.id) continue;
      counts[fleet.type === 'colony' ? 'civil' : fleet.type === 'scout' ? 'research' : 'military'] += fleet.shipCount || 1;
    }
    return { ...counts, colonies: colonies.length, ships: counts.civil + counts.research + counts.military };
  }, [game.fleets, game.me.id, colonies]);
  const categories = [{ id: 'colonies' as const, name: 'Kolonien' }, { id: 'ships' as const, name: 'Schiffe' }];
  return <div className="empire-inventory">
    <div className="inventory-tabbar"><div className="inventory-tabs" role="tablist" aria-label="Reichsbesitz">{categories.map((category, index) => {
      const Icon = icons[category.id];
      return <button key={category.id} role="tab" id={`${id}-tab-${category.id}`} aria-controls={`${id}-${category.id}`} aria-selected={tab === category.id} tabIndex={tab === category.id ? 0 : -1}
        onClick={() => setTab(category.id)} onKeyDown={(event) => {
          const delta = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 0;
          if (!delta && event.key !== 'Home' && event.key !== 'End') return;
          event.preventDefault();
          const next = categories[event.key === 'Home' ? 0 : event.key === 'End' ? categories.length - 1 : (index + delta + categories.length) % categories.length];
          setTab(next.id); document.getElementById(`${id}-tab-${next.id}`)?.focus();
        }}><Icon size={13} /><span>{category.name}</span><b>{totals[category.id]}</b></button>;
    })}</div></div>
    <div className="inventory-columns">
      <div id={`${id}-colonies`} role="tabpanel" aria-labelledby={`${id}-tab-colonies`} hidden={tab !== 'colonies'}>
        <ColonyTree game={game} entries={colonies} selected={selectedColony} onSelect={onColony} onOpen={onOpenColony} />
      </div>
      <div id={`${id}-ships`} className="inventory-ships" role="tabpanel" aria-labelledby={`${id}-tab-ships`} hidden={tab !== 'ships'}>
        <div className="inventory-tabs inventory-ship-tabs" role="tablist" aria-label="Schiffstyp">{fleetCategories.map((category, index) => {
          return <button key={category.id} role="tab" id={`${id}-tab-${category.id}`} aria-controls={`${id}-${category.id}`} aria-selected={shipTab === category.id} tabIndex={shipTab === category.id ? 0 : -1} onClick={() => setShipTab(category.id)} onKeyDown={(event) => {
            const delta = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
            if (!delta && event.key !== 'Home' && event.key !== 'End') return;
            event.preventDefault();
            const next = fleetCategories[event.key === 'Home' ? 0 : event.key === 'End' ? 2 : (index + delta + 3) % 3];
            setShipTab(next.id); document.getElementById(`${id}-tab-${next.id}`)?.focus();
          }} title={category.name}><span>{category.name}</span><b>{totals[category.id]}</b></button>;
        })}</div>
        <div className="inventory-columns">{fleetCategories.map((category) => <div key={category.id} id={`${id}-${category.id}`} role="tabpanel" aria-labelledby={`${id}-tab-${category.id}`} hidden={shipTab !== category.id}>
        <FleetInventory game={game} type={category.type} label={category.name} selected={selectedFleet} onSelect={onFleet} onOpen={onOpenFleet} />
        </div>)}</div>
      </div>
    </div>
  </div>;
}
