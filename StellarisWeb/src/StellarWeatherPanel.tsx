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
  const weather = system.stellarWeather;
  if (!weather) return null;
  const active = stellarWeatherFactor('solar', weather, tick) < 1;
  const warning = weather.phase !== 'cancelled' && tick < weather.startsAt;
  const remaining = Math.max(0, Math.ceil((warning ? weather.startsAt : weather.endsAt) - tick));
  return (
    <section className={`stellar-weather ${active ? 'active' : ''}`} aria-label="Sternensturm">
      <span className="eyebrow">NATÜRLICHES STERNEREIGNIS</span>
      <h3>
        {active
          ? 'Sternensturm aktiv'
          : warning
            ? 'Sternensturm vorhergesagt'
            : weather.phase === 'cancelled'
              ? 'Sturm durch Sternveränderung beendet'
              : 'Sternensturm abgeklungen'}
      </h3>
      {active || warning ? (
        <>
          <p>
            {warning ? 'Ausbruch' : 'Erholung'} in <b>{remaining} Tagen</b>
            {paused ? ' · pausiert' : ''}.
          </p>
          <progress
            aria-label={warning ? 'Zeit bis zum Sternensturm' : 'Dauer des Sternensturms'}
            max={warning ? STELLAR_STORM.warningDays : STELLAR_STORM.activeDays}
            value={(warning ? STELLAR_STORM.warningDays : STELLAR_STORM.activeDays) - remaining}
          />
          <p>
            Sonnenkollektoren und Dyson-Anlagen liefern{' '}
            {active ? 'derzeit' : `für ${STELLAR_STORM.activeDays} Tage`} nur 25 % ihrer Energie. Andere
            Anlagen und Kolonien arbeiten weiter.
          </p>
        </>
      ) : (
        <p>Die solare Produktion ist wiederhergestellt.</p>
      )}
    </section>
  );
}
