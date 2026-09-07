import { Fragment, useEffect, useRef, useState, type ReactNode } from 'react';
import { Search, X } from 'lucide-react';
import './detail-panels.css';

const collator = new Intl.Collator('de', { numeric: true, sensitivity: 'base' });

export function DetailList<T>({
  label,
  items,
  getKey,
  getName,
  getSearchText = getName,
  selectedKey,
  children,
  tools,
  empty = 'Keine Einträge.',
  className = '',
}: {
  label: string;
  items: readonly T[];
  getKey: (item: T) => string | number;
  getName: (item: T) => string;
  getSearchText?: (item: T) => string;
  selectedKey?: string | number | null;
  children: (item: T) => ReactNode;
  tools?: ReactNode;
  empty?: string;
  className?: string;
}) {
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState('default');
  const list = useRef<HTMLDivElement>(null);
  const search = useRef<HTMLInputElement>(null);
  const terms = query.toLocaleLowerCase('de').trim().split(/\s+/).filter(Boolean);
  const visible = items.filter((item) => {
    const text = getSearchText(item).toLocaleLowerCase('de');
    return terms.every((term) => text.includes(term));
  });
  if (sort === 'name') visible.sort((a, b) => collator.compare(getName(a), getName(b)));

  useEffect(() => {
    if (list.current) list.current.scrollTop = 0;
  }, [query, sort]);
  useEffect(() => {
    const container = list.current;
    const selected = container?.querySelector<HTMLElement>('[aria-pressed="true"]');
    if (!container || !selected) return;
    const bounds = container.getBoundingClientRect(),
      row = selected.getBoundingClientRect();
    if (row.top < bounds.top) container.scrollTop += row.top - bounds.top;
    else if (row.bottom > bounds.bottom) container.scrollTop += row.bottom - bounds.bottom;
  }, [selectedKey]);

  return (
    <section className={`detail-list ${className}`} aria-label={label}>
      <header className="detail-list-heading">
        <h3>{label}</h3>
        <span aria-live="polite" aria-atomic="true">
          {terms.length ? `${visible.length} / ${items.length}` : items.length}
        </span>
      </header>
      {tools}
      <div className="detail-list-tools">
        <div className="detail-list-search">
          <Search size={13} aria-hidden="true" />
          <input
            ref={search}
            type="search"
            aria-label={`${label} durchsuchen`}
            placeholder="Suchen …"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {query && (
            <button
              type="button"
              aria-label={`${label}: Suche löschen`}
              onClick={() => {
                setQuery('');
                search.current?.focus();
              }}
            >
              <X size={12} />
            </button>
          )}
        </div>
        <select aria-label={`${label} sortieren`} value={sort} onChange={(e) => setSort(e.target.value)}>
          <option value="default">Standard</option>
          <option value="name">Name A–Z</option>
        </select>
      </div>
      <div ref={list} className="detail-list-rows" tabIndex={0} aria-label={`${label}: Einträge`}>
        {visible.map((item) => (
          <Fragment key={getKey(item)}>{children(item)}</Fragment>
        ))}
        {!visible.length && <p className="detail-list-empty">{items.length ? 'Keine Treffer.' : empty}</p>}
      </div>
    </section>
  );
}
