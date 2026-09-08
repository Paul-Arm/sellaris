import type { ReactNode } from 'react';
import { ArrowUpRight, MapPin, MessageSquare } from 'lucide-react';
import type { GameView } from '../shared/game';
import type { EventBlock, Situation } from '../shared/events/types';
import { RESOURCE_IDS, RESOURCE_NAMES, type Resources } from '../shared/resources';

export const canAfford = (funds: Resources, cost: Resources = {}) =>
  RESOURCE_IDS.every((r) => funds[r] >= (cost[r] ?? 0));
export function EventCosts({ cost = {} }: { cost?: Resources }) {
  const values = RESOURCE_IDS.filter((r) => (cost[r] ?? 0) > 0);
  return (
    <span className="event-costs">
      {values.length
        ? values.map((r) => (
            <span key={r}>
              {cost[r]} {RESOURCE_NAMES[r]}
            </span>
          ))
        : 'Keine Kosten'}
    </span>
  );
}
export function EventProgress({
  value,
  max,
  rate,
  paused = false,
}: {
  value: number;
  max: number;
  rate?: number;
  paused?: boolean;
}) {
  const percent = Math.min(100, Math.max(0, (value / max) * 100));
  return (
    <div className="event-progress">
      <div>
        <strong>
          {percent.toFixed(1)} <small>%</small>
        </strong>
        <span>
          {paused
            ? 'Pausiert'
            : rate === undefined
              ? 'Fortschritt'
              : `${rate >= 0 ? '+' : ''}${rate.toFixed(2)} / Tag`}
        </span>
      </div>
      <progress value={value} max={max} aria-label="Projektfortschritt" />
    </div>
  );
}
export function EventLocationMap({
  game,
  systemId,
  onFocus,
}: {
  game: GameView;
  systemId: string;
  onFocus: (id: string) => void;
}) {
  const center = game.systems.find((s) => s.id === systemId);
  if (!center) return <p className="event-muted">Reichsweites Vorhaben · kein einzelner Fundort</p>;
  const neighborIds = game.links.flatMap(([a, b]) => (a === systemId ? [b] : b === systemId ? [a] : []));
  const nodes = [center, ...game.systems.filter((s) => neighborIds.includes(s.id)).slice(0, 6)];
  const minX = Math.min(...nodes.map((n) => n.x)),
    maxX = Math.max(...nodes.map((n) => n.x));
  const minY = Math.min(...nodes.map((n) => n.y)),
    maxY = Math.max(...nodes.map((n) => n.y));
  const x = (v: number) => 60 + ((v - minX) / Math.max(1, maxX - minX)) * 440;
  const y = (v: number) => 35 + ((v - minY) / Math.max(1, maxY - minY)) * 140;
  return (
    <div className="event-location">
      <svg viewBox="0 0 560 220" role="img" aria-label={`Sternkarte um ${center.name}`}>
        {nodes.slice(1).map((n) => (
          <line key={n.id} x1={x(center.x)} y1={y(center.y)} x2={x(n.x)} y2={y(n.y)} />
        ))}
        {nodes.map((n) => (
          <g key={n.id}>
            <circle
              cx={x(n.x)}
              cy={y(n.y)}
              r={n.id === systemId ? 7 : 4}
              className={n.id === systemId ? 'selected' : ''}
            />
            <text x={x(n.x)} y={y(n.y) + 23} textAnchor="middle">
              {n.name}
            </text>
          </g>
        ))}
      </svg>
      <button onClick={() => onFocus(systemId)}>
        <MapPin size={14} />
        {center.name}
        <ArrowUpRight size={14} />
      </button>
    </div>
  );
}
function NarrativeBlock({
  block,
  game,
  item,
  onFocus,
}: {
  block: EventBlock;
  game: GameView;
  item: Situation;
  onFocus: (id: string) => void;
}) {
  const text = (value: string) =>
    value
      .replaceAll(
        '{{system}}',
        game.systems.find((s) => s.id === item.systemId)?.name ?? 'unbekanntes System',
      )
      .replaceAll(
        '{{species}}',
        game.me.empire.species.find((s) => s.id === item.state.speciesId)?.name ?? 'unsere Spezies',
      )
      .replaceAll('{{empire}}', game.me.name);
  if (block.type === 'text') return <p className="event-prose">{text(block.text)}</p>;
  if (block.type === 'dialogue')
    return (
      <blockquote className="event-dialogue">
        <div>
          {block.portrait ? <img src={block.portrait} alt="" /> : <MessageSquare size={21} />}
          <span>
            <strong>{block.speaker}</strong>
            <small>{block.role}</small>
          </span>
        </div>
        <p>„{text(block.text)}“</p>
      </blockquote>
    );
  if (block.type === 'image')
    return (
      <figure className="event-figure">
        <img src={block.src} alt={block.alt} />
        {block.caption && <figcaption>{block.caption}</figcaption>}
      </figure>
    );
  if (block.type === 'map')
    return (
      <figure className="event-map">
        <figcaption>{block.caption}</figcaption>
        <EventLocationMap game={game} systemId={item.systemId} onFocus={onFocus} />
      </figure>
    );
  return (
    <aside className={`event-callout ${block.tone ?? 'info'}`}>
      <strong>{block.title}</strong>
      <p>{text(block.text)}</p>
    </aside>
  );
}
export function EventContent({
  blocks,
  ...props
}: {
  blocks: EventBlock[];
  game: GameView;
  item: Situation;
  onFocus: (id: string) => void;
}) {
  return (
    <div className="event-content">
      {blocks.map((block, index) => (
        <NarrativeBlock key={index} block={block} {...props} />
      ))}
    </div>
  );
}
export function EventPanel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="event-panel">
      <h3>{title}</h3>
      {children}
    </section>
  );
}
