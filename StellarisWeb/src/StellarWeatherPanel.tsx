import type { StarSystem } from '../shared/game';
import { STELLAR_STORM, stellarWeatherFactor } from '../shared/stellarWeather';
import './stellar-weather.css';
export function StellarWeatherPanel({
  system,
  tick,
  paused,
}: {
  system: StarSystem;
  tick: number;
  paused: boolean;
}) {
  const w = system.stellarWeather;
  if (!w) return null;
  const active = stellarWeatherFactor('solar', w, tick) < 1;
  const warning = w.phase === 'warning';
  const remaining = Math.max(0, Math.ceil((warning ? w.startsAt : w.endsAt) - tick));
  return (
    <section className={`stellar-weather ${active ? 'active' : ''}`} aria-label="Sternensturm">
      <span className="eyebrow">NATÜRLICHES STERNEREIGNIS</span>
      <h3>
        {active
          ? 'Sternensturm aktiv'
          : warning
            ? 'Sternensturm vorhergesagt'
            : w.phase === 'cancelled'
              ? 'Sternereignis beendet'
              : 'Sternensturm abgeklungen'}
      </h3>
      {active || warning ? (
        <>
          <p>
            {warning ? 'Ausbruch' : 'Erholung'} in <b>{remaining} Tagen</b>
            {paused ? ' · pausiert' : ''}.
          </p>
          <progress
            aria-label="Sternensturm"
            max={warning ? STELLAR_STORM.warningDays : STELLAR_STORM.activeDays}
            value={(warning ? STELLAR_STORM.warningDays : STELLAR_STORM.activeDays) - remaining}
          />
          <p>Sonnenkollektoren und Dyson-Anlagen liefern für 60 Tage nur 25 % ihrer Energie.</p>
        </>
      ) : (
        <p>
          {w.phase === 'cancelled'
            ? 'Der Stern hat sich verändert.'
            : 'Die solare Produktion ist wiederhergestellt.'}
        </p>
      )}
    </section>
  );
}
