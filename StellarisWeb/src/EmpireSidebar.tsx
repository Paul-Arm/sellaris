import { Radio } from 'lucide-react';
import type { Fleet, GameView } from '../shared/game';
import { EmpireInventory } from './EmpireInventory';
import type { ColonyEntry } from './inventory-model';
import './inventory.css';

export function EmpireSidebar({ game, open, selectedColony, selectedFleet, onColony, onFleet, onOpenColony, onOpenFleet, section, onSection, onStories, onLog }: {
  game: GameView; open: boolean; selectedColony: string | null; selectedFleet: string | null;
  onColony: (colony: ColonyEntry) => void; onFleet: (fleet: Fleet) => void;
  onOpenColony: (colony: ColonyEntry) => void; onOpenFleet: (fleet: Fleet) => void;
  section: 'colonies' | 'ships'; onSection: (section: 'colonies' | 'ships') => void; onStories: () => void; onLog: () => void;
}) {
  const pending = game.decisions?.filter((decision) => decision.phase === 'pending').length || 0;
  const crisis = game.crises?.find((c) => c.phase !== 'contained' && c.phase !== 'dormant');
  return <aside className={`left-panel inventory-sidebar ${open ? 'mobile-open' : ''}`}>
    <EmpireInventory key={`${game.code}:${game.me.id}`} game={game} selectedColony={selectedColony} selectedFleet={selectedFleet} onColony={onColony} onFleet={onFleet} onOpenColony={onOpenColony} onOpenFleet={onOpenFleet} section={section} onSection={onSection} />
    <footer className="inventory-sidebar-footer">
      <div><button onClick={onStories}><Radio size={13} /> Lage <b>{pending || (crisis ? '!' : 0)}</b></button><button onClick={onLog}>Protokoll</button></div>
    </footer>
  </aside>;
}
