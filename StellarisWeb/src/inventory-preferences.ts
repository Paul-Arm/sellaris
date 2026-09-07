import { useEffect, useState } from 'react';

function readOrder(key: string): string[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(key) || '[]');
    return Array.isArray(value) ? [...new Set(value.filter((id): id is string => typeof id === 'string'))] : [];
  } catch { return []; }
}
export function useInventoryOrder(key: string) {
  const [order, setOrder] = useState(() => readOrder(key));
  useEffect(() => {
    const update = (event: Event) => {
      if (event instanceof StorageEvent ? event.key === key : (event as CustomEvent).detail === key) setOrder(readOrder(key));
    };
    window.addEventListener('storage', update);
    window.addEventListener('inventory-order', update);
    return () => { window.removeEventListener('storage', update); window.removeEventListener('inventory-order', update); };
  }, [key]);
  return [order, (next: string[]) => {
    setOrder(next);
    try {
      localStorage.setItem(key, JSON.stringify(next));
      window.dispatchEvent(new CustomEvent('inventory-order', { detail: key }));
    } catch { /* Session ordering remains usable if local storage is unavailable. */ }
  }] as const;
}
