import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode, type KeyboardEvent, type HTMLAttributes } from 'react';
import { virtualWindow } from './inventory-model';

export function VirtualList<T>({ items, getKey, children, label, rowHeight = 34, selectedKey,
  onActivate, onArrow, onReorder, canDrop, role = 'listbox', rowAttributes, resetKey = '',
}: {
  items: readonly T[];
  getKey: (item: T) => string;
  children: (item: T, active: boolean) => ReactNode;
  label: string;
  rowHeight?: number;
  selectedKey?: string | null;
  onActivate?: (item: T) => void;
  onArrow?: (item: T, direction: 'left' | 'right') => string | void;
  onReorder?: (source: T, target: T) => void;
  canDrop?: (source: T, target: T) => boolean;
  role?: 'tree' | 'listbox';
  rowAttributes?: (item: T) => HTMLAttributes<HTMLDivElement>;
  resetKey?: string;
}) {
  const id = useId().replaceAll(':', '');
  const viewport = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(300), [top, setTop] = useState(0);
  const [active, setActive] = useState<string | null>(selectedKey || null);
  const [drop, setDrop] = useState<string | null>(null);
  const dragging = useRef<T | null>(null);
  const pointerDrag = useRef<{ source: T; x: number; y: number; moved: boolean; target?: T } | null>(null);
  const suppressClick = useRef(false);
  const pendingFocus = useRef<string | null>(null);
  const activeIndex = items.findIndex((item) => getKey(item) === active);
  const focusIndex = activeIndex >= 0 ? activeIndex : 0;
  const window = virtualWindow(items.length, top, height, rowHeight);
  const activeMounted = focusIndex >= window.start && focusIndex < window.end;
  function reveal(index: number) {
    const el = viewport.current;
    if (!el || index < 0) return;
    const y = index * rowHeight;
    if (y < el.scrollTop) el.scrollTop = y;
    else if (y + rowHeight > el.scrollTop + el.clientHeight) el.scrollTop = y + rowHeight - el.clientHeight;
    setTop(el.scrollTop);
  }
  useLayoutEffect(() => {
    const el = viewport.current!;
    const resize = new ResizeObserver(() => setHeight(el.clientHeight));
    resize.observe(el);
    setHeight(el.clientHeight);
    return () => resize.disconnect();
  }, []);
  useLayoutEffect(() => {
    if (viewport.current) viewport.current.scrollTop = 0;
    setTop(0);
    setActive(null);
  }, [resetKey]);
  useEffect(() => {
    if (!selectedKey) return;
    setActive(selectedKey);
    const index = items.findIndex((item) => getKey(item) === selectedKey);
    pendingFocus.current = index < 0 ? selectedKey : null;
    reveal(index);
    // Selection follows map clicks, not each simulation tick or manual scroll.
  }, [selectedKey]);
  useLayoutEffect(() => {
    if (!pendingFocus.current) return;
    const index = items.findIndex((item) => getKey(item) === pendingFocus.current);
    if (index < 0) return;
    setActive(pendingFocus.current);
    pendingFocus.current = null;
    reveal(index);
  }, [items]);
  useLayoutEffect(() => {
    const el = viewport.current;
    if (!el) return;
    const max = Math.max(0, items.length * rowHeight - el.clientHeight);
    if (el.scrollTop > max) el.scrollTop = max;
    setTop(el.scrollTop);
  }, [items.length, rowHeight, height]);
  function keyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget || !items.length) return;
    const current = items[focusIndex];
    let next = focusIndex;
    if (event.altKey && onReorder && ['ArrowUp', 'ArrowDown'].includes(event.key)) {
      event.preventDefault();
      const target = items[focusIndex + (event.key === 'ArrowUp' ? -1 : 1)];
      if (target && (!canDrop || canDrop(current, target))) {
        pendingFocus.current = getKey(current);
        onReorder(current, target);
      }
      return;
    }
    if (event.key === 'ArrowDown') next++;
    else if (event.key === 'ArrowUp') next--;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = items.length - 1;
    else if (event.key === 'PageDown') next += Math.max(1, Math.floor(height / rowHeight));
    else if (event.key === 'PageUp') next -= Math.max(1, Math.floor(height / rowHeight));
    else if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onActivate?.(current); return; }
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault();
      const target = onArrow?.(current, event.key === 'ArrowLeft' ? 'left' : 'right');
      if (target) { setActive(target); reveal(items.findIndex((item) => getKey(item) === target)); }
      return;
    } else return;
    event.preventDefault();
    next = Math.max(0, Math.min(items.length - 1, next));
    setActive(getKey(items[next]));
    reveal(next);
  }
  return <div ref={viewport} className="virtual-list" role={role} aria-label={label} tabIndex={0}
    aria-activedescendant={items.length && activeMounted ? `${id}-${focusIndex}` : undefined}
    onKeyDown={keyDown} onScroll={(e) => setTop(e.currentTarget.scrollTop)}
    onPointerMove={(event) => {
      const drag = pointerDrag.current;
      if (!drag) return;
      if (!drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) < 5) return;
      drag.moved = true;
      const el = event.currentTarget, rect = el.getBoundingClientRect();
      if (event.clientY < rect.top + 24) el.scrollTop -= rowHeight;
      else if (event.clientY > rect.bottom - 24) el.scrollTop += rowHeight;
      const index = Math.floor((event.clientY - rect.top + el.scrollTop) / rowHeight);
      const target = event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom ? items[index] : undefined;
      drag.target = target && (!canDrop || canDrop(drag.source, target)) ? target : undefined;
      setDrop(drag.target ? getKey(drag.target) : null);
    }}
    onPointerUp={(event) => {
      const drag = pointerDrag.current;
      if (!drag) return;
      suppressClick.current = drag.moved;
      if (drag.moved && drag.target) { pendingFocus.current = getKey(drag.source); onReorder?.(drag.source, drag.target); }
      pointerDrag.current = null;
      setDrop(null);
      if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    }}
    onPointerCancel={() => { pointerDrag.current = null; setDrop(null); }}
    onDragOver={(event) => {
      if (!dragging.current) return;
      event.preventDefault();
      const el = event.currentTarget, rect = el.getBoundingClientRect();
      if (event.clientY < rect.top + 30) el.scrollTop -= rowHeight;
      if (event.clientY > rect.bottom - 30) el.scrollTop += rowHeight;
    }}>
    <div role="presentation" style={{ height: items.length * rowHeight, position: 'relative' }}>
      {items.slice(window.start, window.end).map((item, offset) => {
        const index = window.start + offset, key = getKey(item);
        return <div key={key} id={`${id}-${index}`} role={role === 'tree' ? 'treeitem' : 'option'}
          aria-selected={key === selectedKey} aria-posinset={index + 1} aria-setsize={items.length}
          {...rowAttributes?.(item)}
          className={`inventory-row ${key === selectedKey ? 'selected' : ''} ${index === focusIndex ? 'keyboard-active' : ''} ${drop === key ? 'drop-target' : ''}`}
          style={{ position: 'absolute', top: index * rowHeight, height: rowHeight, left: 0, right: 0 }}
          onClick={() => {
            if (suppressClick.current) { suppressClick.current = false; return; }
            setActive(key); viewport.current?.focus({ preventScroll: true }); onActivate?.(item);
          }}
          onPointerDown={(event) => {
            suppressClick.current = false;
            if (event.button !== 0 || !onReorder || (canDrop && !canDrop(item, item)) || !(event.target as Element).closest('.inventory-grip')) return;
            event.preventDefault();
            pointerDrag.current = { source: item, x: event.clientX, y: event.clientY, moved: false };
            viewport.current?.setPointerCapture(event.pointerId);
            viewport.current?.focus({ preventScroll: true });
            setActive(key);
          }}
          onDragStart={(event) => {
            dragging.current = item; setActive(key);
            event.dataTransfer.setData('application/x-singularity-inventory', key);
            event.dataTransfer.effectAllowed = 'move';
          }}
          onDragOver={(event) => {
            const source = dragging.current;
            if (!source || (canDrop && !canDrop(source, item))) return;
            event.preventDefault(); event.dataTransfer.dropEffect = 'move'; setDrop(key);
          }}
          onDrop={(event) => {
            event.preventDefault();
            const source = dragging.current;
            if (source && (!canDrop || canDrop(source, item))) onReorder?.(source, item);
            dragging.current = null; setDrop(null);
          }}
          onDragEnd={() => { dragging.current = null; setDrop(null); }}>
          {children(item, index === focusIndex)}
        </div>;
      })}
    </div>
  </div>;
}
