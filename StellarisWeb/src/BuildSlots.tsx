import { useEffect, useRef, type ReactNode } from 'react';
import { Plus, LockKeyhole, X, Hammer } from 'lucide-react';
import './build-slots.css';

/** A physical place remains the primary interaction, regardless of its contents. */
export function BuildSlot({
  label,
  name,
  icon,
  state = 'empty',
  selected,
  detail,
  level,
  onClick,
}: {
  label: string;
  name: string;
  icon?: ReactNode;
  state?: 'empty' | 'occupied' | 'building' | 'locked';
  selected?: boolean;
  detail?: string;
  level?: number;
  onClick?: () => void;
}) {
  return (
    <button
      className={`build-slot ${state}`}
      aria-label={`${label}: ${name}`}
      aria-pressed={selected}
      disabled={state === 'locked'}
      onClick={onClick}
    >
      <span className="build-slot-label">{label}</span>
      <span className="build-slot-symbol">{state === 'locked' ? <LockKeyhole /> : icon || <Plus />}</span>
      <strong>{name}</strong>
      {level ? (
        <span className="build-slot-level" aria-label={`Stufe ${level} von 3`}>
          {[1, 2, 3].map((n) => (
            <i key={n} className={n <= level ? 'lit' : ''} />
          ))}
        </span>
      ) : null}
      <small>
        {state === 'building' && <Hammer size={11} />}
        {detail || (state === 'empty' ? 'Zum Belegen auswählen' : '')}
      </small>
    </button>
  );
}

export function SlotPicker({
  title,
  subtitle,
  close,
  children,
}: {
  title: string;
  subtitle: string;
  close: () => void;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current!;
    const previous = document.activeElement;
    d.showModal();
    return () => {
      d.close();
      if (previous instanceof HTMLElement && previous.isConnected) previous.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className="slot-picker"
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        e.stopPropagation();
        close();
      }}
      onKeyDown={(e) => e.stopPropagation()}
    >
      <header>
        <div>
          <span className="eyebrow">BAUPLATZ BESTÜCKEN</span>
          <h3>{title}</h3>
          <p>{subtitle}</p>
        </div>
        <button autoFocus className="icon-button" aria-label="Auswahl schließen" onClick={close}>
          <X size={19} />
        </button>
      </header>
      <div className="slot-picker-grid">{children}</div>
    </dialog>
  );
}
