import { useMemo, useState } from 'react';
import { GripVertical, Search, X } from 'lucide-react';
import type { Fleet, GameView, ShipType } from '../shared/game';
import { VirtualList } from './VirtualList';
import { InventoryControls } from './InventoryControls';
import { fleetAvailable, fleetInventoryStatus, inventoryCollator, matchesInventory, reorderInventory } from './inventory-model';
import { useInventoryOrder } from './inventory-preferences';
import './inventory.css';

export function FleetInventory({ game, type, label, selected, onSelect, onOpen }: {
  game: GameView; type: ShipType; label: string; selected: string | null;
  onSelect: (fleet: Fleet) => void; onOpen?: (fleet: Fleet) => void;
}) {
  const fleets = useMemo(() => game.fleets.filter((fleet) => fleet.owner === game.me.id && fleet.type === type), [game.fleets, game.me.id, type]);
  const systems = useMemo(() => new Map(game.systems.map((system) => [system.id, system.name])), [game.systems]);
  const [query, setQuery] = useState(''), [status, setStatus] = useState('all');
  const [order, setOrder] = useInventoryOrder(`singularity.inventory:${game.code}:${game.me.id}:${type}`);
  const [sort, setSort] = useState(() => order.length ? 'manual' : 'name');
  const [notice, setNotice] = useState('');
  const ranked = useMemo(() => {
    const rank = new Map(order.map((id, i) => [id, i]));
    return [...fleets].sort((a, b) => {
      const delta = sort === 'manual' ? (rank.get(a.id) ?? Infinity) - (rank.get(b.id) ?? Infinity)
        : sort === 'available' ? Number(fleetAvailable(b)) - Number(fleetAvailable(a))
        : sort === 'size' ? (b.shipCount || 1) - (a.shipCount || 1)
        : sort === 'hull' ? a.hp - b.hp
        : sort === 'system' ? inventoryCollator.compare(systems.get(a.systemId) || '', systems.get(b.systemId) || '') : 0;
      return delta || inventoryCollator.compare(a.name, b.name) || inventoryCollator.compare(a.id, b.id);
    });
  }, [fleets, order, sort, systems]);
  const visible = useMemo(() => ranked.filter((fleet) =>
    matchesInventory(query, `${fleet.name} ${systems.get(fleet.systemId) || ''} ${fleetInventoryStatus(fleet)}`) &&
    (status === 'all' || (status === 'available' && fleetAvailable(fleet)) || (status === 'busy' && !fleetAvailable(fleet)) || (status === 'battle' && !!fleet.battleId)),
  ), [ranked, query, status, systems]);
  const count = fleets.reduce((n, fleet) => n + (fleet.shipCount || 1), 0);
  const available = fleets.filter(fleetAvailable).reduce((n, fleet) => n + (fleet.shipCount || 1), 0);
  const current = fleets.find((fleet) => fleet.id === selected);
  return <section className="inventory-list fleet-inventory" aria-label={label === 'Forschung' ? 'Forschungsschiffe' : `${label}schiffe`}>
    <div className="inventory-search"><Search size={13} /><input type="search" aria-label={`${label} suchen`} placeholder="Name oder System …" value={query} onChange={(event) => setQuery(event.target.value)} />
      {query && <button aria-label={`${label}suche löschen`} onClick={() => setQuery('')}><X size={12} /></button>}</div>
    <InventoryControls filterCount={Number(status !== 'all')} sortLabel={sort === 'name' ? 'Name A–Z' : sort === 'available' ? 'Verfügbare zuerst' : sort === 'system' ? 'System A–Z' : sort === 'size' ? 'Schiffsanzahl ↓' : sort === 'hull' ? 'Hülle ↑' : 'Eigene Reihenfolge'} filters={
      <select aria-label={`${label}status filtern`} value={status} onChange={(event) => setStatus(event.target.value)}><option value="all">Alle · {count}</option><option value="available">Verfügbar · {available}</option><option value="busy">Beschäftigt</option><option value="battle">Im Gefecht</option></select>
    } sorting={
      <select aria-label={`${label} sortieren`} value={sort} onChange={(event) => setSort(event.target.value)}><option value="name">Name A–Z</option><option value="available">Verfügbare zuerst</option><option value="system">System A–Z</option><option value="size">Schiffsanzahl ↓</option><option value="hull">Hülle ↑</option><option value="manual">Eigene Reihenfolge</option></select>
    } />
    <div className="inventory-column-head"><span>Verband · {visible.length} / {fleets.length}</span><span>Schiffe</span></div>
    <VirtualList items={visible} getKey={(fleet) => fleet.id} label={`${label}: Verbände`} selectedKey={selected} rowHeight={38}
      resetKey={`${query}:${status}`} onActivate={onSelect}
      rowAttributes={(fleet) => ({ 'aria-label': `${fleet.name}, ${systems.get(fleet.systemId) || fleet.systemId}, ${fleet.shipCount || 1} Schiffe, ${fleetInventoryStatus(fleet)}` })}
      onReorder={(source, target) => {
        setOrder(reorderInventory(ranked.map((fleet) => fleet.id), source.id, target.id)); setSort('manual');
        setNotice(`${source.name}: Reihenfolge geändert.`);
      }}>
      {(fleet) => <><GripVertical className="inventory-grip" size={11} aria-hidden="true" /><span className="inventory-name" title={fleet.name}><strong>{fleet.name}</strong><small>{systems.get(fleet.systemId) || fleet.systemId} · {fleetInventoryStatus(fleet)}</small></span><span className="inventory-metric">{fleet.shipCount || 1}</span><i className={`inventory-status ${fleetAvailable(fleet) ? 'available' : fleet.battleId ? 'battle' : 'busy'}`} /></>}
    </VirtualList>
    {!visible.length && <p className="inventory-empty">{fleets.length ? 'Keine Treffer.' : 'Keine Schiffe.'}</p>}
    {current && onOpen && <footer className="inventory-list-footer"><button onClick={() => onOpen(current)}>Verwalten</button></footer>}
    <span className="inventory-sr" role="status">{notice}</span>
  </section>;
}
