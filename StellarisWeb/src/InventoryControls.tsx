import { useId, useState, type ReactNode } from 'react';
import { ArrowDownWideNarrow, SlidersHorizontal } from 'lucide-react';

export function InventoryControls({ filters, sorting, filterCount, sortLabel, children }: {
  filters: ReactNode;
  sorting: ReactNode;
  filterCount: number;
  sortLabel: string;
  children?: ReactNode;
}) {
  const id = useId();
  const [open, setOpen] = useState<'filter' | 'sort' | null>(null);
  return <div className="inventory-controls">
    <div className="inventory-toolbar">
      <button className={filterCount ? 'has-filter' : ''} aria-expanded={open === 'filter'} aria-controls={`${id}-filter`} onClick={() => setOpen(open === 'filter' ? null : 'filter')}>
        <SlidersHorizontal size={13} /> Filter{filterCount > 0 && <b>{filterCount}</b>}
      </button>
      <button title={sortLabel} aria-expanded={open === 'sort'} aria-controls={`${id}-sort`} onClick={() => setOpen(open === 'sort' ? null : 'sort')}>
        <ArrowDownWideNarrow size={13} /> Sortierung
      </button>
      {children}
    </div>
    <div id={`${id}-filter`} className="inventory-filters inventory-control-panel" hidden={open !== 'filter'}>{filters}</div>
    <div id={`${id}-sort`} className="inventory-filters inventory-control-panel" hidden={open !== 'sort'}>{sorting}</div>
  </div>;
}
