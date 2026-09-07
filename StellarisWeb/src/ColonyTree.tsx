import { useEffect, useMemo, useState } from 'react';
import { ChevronDown, ChevronRight, Globe2, GripVertical, Search, X } from 'lucide-react';
import type { GameView } from '../shared/game';
import { VirtualList } from './VirtualList';
import { InventoryControls } from './InventoryControls';
import { colonyInventory, colonyTree, filterColonies, reorderInventory, type ColonyEntry, type ColonySort, type ColonyTreeRow } from './inventory-model';
import { useInventoryOrder } from './inventory-preferences';
import './inventory.css';

const number = (n: number) => n.toLocaleString('de', { maximumFractionDigits: 1 });
export function ColonyTree({ game, selected, onSelect, onOpen, entries: supplied }: {
  game: GameView;
  selected: string | null;
  onSelect: (world: ColonyEntry) => void;
  onOpen?: (world: ColonyEntry) => void;
  entries?: ColonyEntry[];
}) {
  const entries = useMemo(() => supplied || colonyInventory(game), [supplied, game.systems, game.planetColonies, game.me.id, game.me.empire]);
  const current = entries.find((entry) => entry.id === selected);
  const [query, setQuery] = useState(''), [tier, setTier] = useState('all'), [status, setStatus] = useState('all');
  const [flat, setFlat] = useState(false);
  const [expanded, setExpanded] = useState(() => new Set([current?.systemId || entries[0]?.systemId || '']));
  const [order, setOrder] = useInventoryOrder(`singularity.inventory:${game.code}:${game.me.id}:colonies`);
  const [sort, setSort] = useState<ColonySort>(() => order.length ? 'manual' : 'name');
  const [notice, setNotice] = useState('');
  useEffect(() => {
    if (current) setExpanded((previous) => new Set(previous).add(current.systemId));
  }, [selected, current?.systemId]);
  const visible = useMemo(() => filterColonies(entries, { query, tier, status, sort, order }), [entries, query, tier, status, sort, order]);
  const open = useMemo(() => query.trim() ? new Set(visible.map((entry) => entry.systemId)) : expanded, [query, visible, expanded]);
  const rows = useMemo(() => colonyTree(entries, visible, open, sort, flat), [entries, visible, open, sort, flat]);
  const systems = useMemo(() => new Set(entries.map((entry) => entry.systemId)), [entries]);
  function toggle(id: string) {
    setExpanded((previous) => { const next = new Set(previous); if (next.has(id)) next.delete(id); else next.add(id); return next; });
  }
  function move(source: ColonyTreeRow, target: ColonyTreeRow) {
    if (source.kind !== 'colony' || target.kind !== 'colony' || (!flat && source.colony.systemId !== target.colony.systemId)) return;
    const all = filterColonies(entries, { query: '', tier: 'all', status: 'all', sort, order }).map((entry) => entry.id);
    setOrder(reorderInventory(all, source.colony.id, target.colony.id));
    setSort('manual');
    setNotice(`${source.colony.name}: Reihenfolge geändert.`);
  }
  const metric = sort === 'population' ? 'population' : sort === 'tier' ? 'tier' : sort === 'vacancies' ? 'vacancies' : 'workers';
  const metricName = { population: 'Pops', tier: 'Tier', vacancies: 'Jobs frei', workers: 'Arbeiter frei' }[metric];
  const rowKeys = useMemo(() => {
    const systemRows = rows.filter((row) => row.kind === 'system');
    return new Map(systemRows.map((row, index) => [row.id, index + 1]));
  }, [rows]);
  return <section className="inventory-list colony-tree" aria-label="Kolonien">
    <div className="inventory-search"><Search size={13} /><input type="search" aria-label="Kolonien suchen" placeholder="Kolonie oder System …" value={query} onChange={(event) => setQuery(event.target.value)} />
      {query && <button aria-label="Koloniesuche löschen" onClick={() => setQuery('')}><X size={12} /></button>}</div>
    <InventoryControls filterCount={Number(tier !== 'all') + Number(status !== 'all')} sortLabel={{ name: 'Name A–Z', workers: 'Arbeitskräfte ↓', vacancies: 'Freie Jobs ↓', population: 'Bevölkerung ↓', tier: 'Tier ↓', manual: 'Eigene Reihenfolge' }[sort]} filters={<>
      <select aria-label="Kolonien nach Ausbau-Tier filtern" title="Ausbau-Tier: höchste Distriktstufe der Kolonie" value={tier} onChange={(event) => setTier(event.target.value)}>
        <option value="all">Alle Tiers</option>{[0, 1, 2, 3].map((n) => <option value={n} key={n}>Tier {n}</option>)}
      </select>
      <select aria-label="Koloniestatus filtern" value={status} onChange={(event) => setStatus(event.target.value)}>
        <option value="all">Alle Kolonien</option><option value="workers">Freie Arbeitskräfte</option><option value="vacancies">Unbesetzte Jobs</option><option value="building">Im Ausbau</option>
      </select>
    </>} sorting={
      <select aria-label="Kolonien sortieren" value={sort} onChange={(event) => setSort(event.target.value as ColonySort)}>
        <option value="name">Name A–Z</option><option value="workers">Arbeitskräfte ↓</option><option value="vacancies">Freie Jobs ↓</option><option value="population">Bevölkerung ↓</option><option value="tier">Tier ↓</option><option value="manual">Eigene Reihenfolge</option>
      </select>
    }>
      <button aria-pressed={flat} onClick={() => setFlat(!flat)} title="Zwischen Systembaum und flacher Kolonieliste wechseln">{flat ? 'Liste' : 'Systembaum'}</button>
    </InventoryControls>
    {!flat && <div className="inventory-tree-actions"><button disabled={!!query.trim()} onClick={() => setExpanded(new Set(systems))}>Alle auf</button><button disabled={!!query.trim()} onClick={() => setExpanded(new Set())}>Alle zu</button><span>{visible.length} / {entries.length}</span></div>}
    <div className="inventory-column-head"><span>{flat ? `Kolonie · ${visible.length} / ${entries.length}` : 'System / Kolonie'}</span><span title={metric === 'workers' ? 'Unbeschäftigte Bevölkerung; Systemsummen berücksichtigen die aktuellen Filter' : metric === 'tier' ? 'Höchste Distriktstufe' : metricName}>{metricName}</span></div>
    <VirtualList items={rows} getKey={(row) => row.id} label="Koloniebaum" role="tree" selectedKey={selected ? `colony:${selected}` : null}
      resetKey={`${query}:${tier}:${status}:${flat}`} rowHeight={34}
      onActivate={(row) => row.kind === 'system' ? toggle(row.systemId) : onSelect(row.colony)}
      onArrow={(row, direction) => {
        if (row.kind === 'system') {
          if (direction === 'right' && !open.has(row.systemId)) toggle(row.systemId);
          else if (direction === 'right') return `colony:${row.worlds[0]?.id}`;
          else if (direction === 'left' && open.has(row.systemId)) toggle(row.systemId);
        } else if (direction === 'left') return row.parentId;
      }}
      onReorder={move} canDrop={(a, b) => a.kind === 'colony' && b.kind === 'colony' && (flat || a.colony.systemId === b.colony.systemId)}
      rowAttributes={(row) => row.kind === 'system'
        ? { 'aria-level': 1, 'aria-expanded': open.has(row.systemId), 'aria-posinset': rowKeys.get(row.id), 'aria-setsize': rowKeys.size, 'aria-label': `${row.name}, ${row.worlds.length} Kolonien, ${number(row[metric])} ${metricName}` }
        : { 'aria-level': flat ? 1 : 2, 'aria-label': `${row.colony.name}, Tier ${row.colony.tier}, ${number(row.colony.workers)} freie Arbeitskräfte`, 'aria-posinset': flat ? visible.indexOf(row.colony) + 1 : (rows.find((r) => r.kind === 'system' && r.id === row.parentId) as Extract<ColonyTreeRow, {kind:'system'}>)?.worlds.indexOf(row.colony)! + 1, 'aria-setsize': flat ? visible.length : (rows.find((r) => r.kind === 'system' && r.id === row.parentId) as Extract<ColonyTreeRow, {kind:'system'}>)?.worlds.length }}>
      {(row) => row.kind === 'system' ? <>
        {open.has(row.systemId) ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <strong className="inventory-name" title={row.name}>{row.name}</strong><small className="inventory-count">{row.worlds.length === row.total ? row.total : `${row.worlds.length}/${row.total}`}</small><span className="inventory-metric">{number(row[metric])}</span>
      </> : <>
        {!flat && <span className="inventory-indent" />}<GripVertical size={11} className="inventory-grip" aria-hidden="true" />
        <span className="inventory-name" title={`${row.colony.name} · ${row.colony.systemName}`}>{row.colony.name}</span>
        <small className="inventory-tier" title="Höchste Distriktstufe">T{row.colony.tier}</small><span className={`inventory-metric ${row.colony.workers > 0.001 && metric === 'workers' ? 'attention' : ''}`}>{number(row.colony[metric])}</span>
      </>}
    </VirtualList>
    {!rows.length && <p className="inventory-empty">{entries.length ? 'Keine Treffer.' : 'Keine Kolonien.'}</p>}
    {onOpen && current && <footer className="inventory-list-footer"><button onClick={() => onOpen(current)} title={`${current.name} verwalten`}><Globe2 size={12} /> Verwalten</button></footer>}
    <span className="inventory-sr" role="status">{notice}</span>
  </section>;
}
