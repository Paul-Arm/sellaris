import { useId, type Ref } from 'react';
import type { FlagDesign } from '../shared/flags';
import './flags.css';

function SymbolMark({ name }: { name: FlagDesign['emblem'] }) {
  switch (name) {
    case 'star':
      return (
        <path
          d="M0 -45 10 -13 42 -14 16 6 26 38 0 19 -26 38 -16 6 -42 -14 -10 -13Z"
          fill="currentColor"
          stroke="none"
        />
      );
    case 'hexagon':
      return (
        <>
          <path d="M0 -42 36 -21 36 21 0 42 -36 21 -36 -21Z" />
          <path d="M0 -25 21 -12 21 12 0 25 -21 12 -21 -12Z" />
          <path d="M0 -25V25M-21 -12 21 12M21 -12 -21 12" />
        </>
      );
    case 'diamond':
      return (
        <>
          <path d="M0 -44 31 0 0 44 -31 0Z" />
          <path d="M0 -24 17 0 0 24 -17 0Z" fill="currentColor" stroke="none" />
        </>
      );
    case 'wings':
      return (
        <>
          <path
            d="M0 -20 12 -6 44 -27 35 1 17 9 34 10 26 22 10 21 0 42 -10 21 -26 22 -34 10 -17 9 -35 1 -44 -27 -12 -6Z"
            fill="currentColor"
            stroke="none"
          />
          <path d="M-8 -30 0 -40 8 -30 0 -19Z" fill="currentColor" stroke="none" />
        </>
      );
    case 'nexus':
      return (
        <>
          <path d="M0 -31 28 17H-28ZM0 0V-31M0 0 28 17M0 0 -28 17" />
          <circle cy="-31" r="9" />
          <circle cx="28" cy="17" r="9" />
          <circle cx="-28" cy="17" r="9" />
          <circle r="6" fill="currentColor" />
        </>
      );
    default:
      return (
        <>
          <circle r="22" />
          <ellipse rx="46" ry="15" transform="rotate(-32)" />
          <circle cx="26" cy="-27" r="7" fill="currentColor" stroke="none" />
          <circle r="5" fill="currentColor" stroke="none" />
        </>
      );
  }
}
/** The same bounded SVG renders the editor, small badges, game flags and downloadable artwork. */
export function EmpireFlag({
  flag,
  width = 72,
  title,
  svgRef,
  className = '',
}: {
  flag: FlagDesign;
  width?: number;
  title?: string;
  svgRef?: Ref<SVGSVGElement>;
  className?: string;
}) {
  const clip = `flag-${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`;
  const x = flag.position === 'hoist' ? 82 : 150;
  const radius = (flag.size / 45) * (flag.frame === 'hexagon' ? 57 : flag.frame === 'circle' ? 53 : 49);
  const y = flag.position === 'upper' ? Math.max(65, radius + 12) : 100;
  return (
    <svg
      ref={svgRef}
      className={`empire-flag ${className}`}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 300 200"
      width={width}
      height={(width * 2) / 3}
      role={title ? 'img' : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
      focusable="false"
    >
      {title && <title>{title}</title>}
      <defs>
        <clipPath id={clip}>
          <rect width="300" height="200" />
        </clipPath>
      </defs>
      <g clipPath={`url(#${clip})`}>
        <rect width="300" height="200" fill={flag.primary} />
        <g fill={flag.secondary}>
          {flag.pattern === 'horizontal' && <rect y="100" width="300" height="100" />}
          {flag.pattern === 'vertical' && <rect x="150" width="150" height="200" />}
          {flag.pattern === 'diagonal' && <path d="M0 200 300 0V200Z" />}
          {flag.pattern === 'triband' && <rect y="65" width="300" height="70" />}
          {flag.pattern === 'cross' && <path d="M68 0H112V78H300V122H112V200H68V122H0V78H68Z" />}
          {flag.pattern === 'saltire' && (
            <path d="M0 0H35L300 176V200H265L0 24ZM265 0H300V24L35 200H0V176Z" />
          )}
          {flag.pattern === 'chevron' && <path d="M0 0 163 100 0 200Z" />}
          {flag.pattern === 'canton' && <rect width="135" height="100" />}
          {flag.pattern === 'quarters' && (
            <>
              <rect width="150" height="100" />
              <rect x="150" y="100" width="150" height="100" />
            </>
          )}
          {flag.pattern === 'diamond' && <path d="M150 0 300 100 150 200 0 100Z" />}
          {flag.pattern === 'stripes' && (
            <>
              <rect y="28" width="300" height="29" />
              <rect y="85" width="300" height="30" />
              <rect y="143" width="300" height="29" />
            </>
          )}
        </g>
        {flag.border !== 'none' && (
          <g fill="none" stroke={flag.symbolColor} strokeWidth="2">
            <rect x="7" y="7" width="286" height="186" />
            {flag.border === 'double' && <rect x="13" y="13" width="274" height="174" />}
          </g>
        )}
        <g
          transform={`translate(${x} ${y}) scale(${flag.size / 45})`}
          fill="none"
          color={flag.symbolColor}
          stroke={flag.symbolColor}
          strokeWidth="3"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          {flag.frame === 'circle' && <circle r="53" strokeWidth="1.8" />}
          {flag.frame === 'hexagon' && (
            <path d="M0 -57 49 -28.5 49 28.5 0 57 -49 28.5 -49 -28.5Z" strokeWidth="1.8" />
          )}
          <g transform={`rotate(${flag.rotation})`}>
            <SymbolMark name={flag.emblem} />
          </g>
        </g>
      </g>
    </svg>
  );
}
