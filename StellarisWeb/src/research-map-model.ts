export interface MapTechnology {
  field: string;
  requires: readonly string[];
}
export interface ResearchNode {
  id: string;
  x: number;
  y: number;
}
export interface ResearchLayout {
  nodes: ResearchNode[];
  edges: { from: ResearchNode; to: ResearchNode }[];
  width: number;
  height: number;
}
/** Layout depends only on revealed nodes; undiscovered branches do not leak through empty space. */
export function layoutResearch(
  catalog: Record<string, MapTechnology>,
  ids: readonly string[],
): ResearchLayout {
  const visible = new Set(ids),
    depths = new Map<string, number>();
  const depth = (id: string): number => {
    if (depths.has(id)) return depths.get(id)!;
    depths.set(id, 0);
    const parents = catalog[id].requires.filter((p) => visible.has(p));
    const value = parents.length ? 1 + Math.max(...parents.map(depth)) : 0;
    depths.set(id, value);
    return value;
  };
  const fields = [...new Set(ids.map((id) => catalog[id].field))];
  const nodes: ResearchNode[] = [];
  let offset = 0;
  for (const field of fields) {
    const groups = new Map<number, string[]>();
    for (const id of ids.filter((id) => catalog[id].field === field)) {
      const row = depth(id);
      groups.set(row, [...(groups.get(row) || []), id]);
    }
    const columns = Math.min(3, Math.max(1, ...[...groups.values()].map((g) => g.length)));
    let y = 100;
    for (const [, group] of [...groups].sort(([a], [b]) => a - b)) {
      group.forEach((id, i) =>
        nodes.push({ id, x: offset + 130 + (i % columns) * 250, y: y + Math.floor(i / columns) * 120 }),
      );
      y += Math.ceil(group.length / columns) * 120 + 40;
    }
    offset += columns * 250 + 50;
  }
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const edges = nodes.flatMap((to) =>
    catalog[to.id].requires.flatMap((id) => {
      const from = byId.get(id);
      return from ? [{ from, to }] : [];
    }),
  );
  return {
    nodes,
    edges,
    width: Math.max(600, offset),
    height: Math.max(360, ...nodes.map((n) => n.y + 110)),
  };
}
export function nodesInViewport(
  nodes: ResearchNode[],
  rect: { x: number; y: number; width: number; height: number },
  padding = 180,
) {
  return nodes.filter(
    (n) =>
      n.x >= rect.x - padding &&
      n.x <= rect.x + rect.width + padding &&
      n.y >= rect.y - padding &&
      n.y <= rect.y + rect.height + padding,
  );
}
