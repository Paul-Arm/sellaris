import type { StarSystem } from './game';

export type StellarFamily = 'main' | 'giant' | 'neutron' | 'pulsar' | 'blackhole' | 'quasar' | 'rift';
export interface StellarProfile {
  family: StellarFamily;
  label: string;
  spectral: string;
  color: string;
  spill: string;
  radius: number;
  emission: number;
  corona: number;
  description: string;
}

/** Stable visual classifications for the original procedural atlas; no change to durable body kinds. */
export function stellarClass(s: Pick<StarSystem, 'id' | 'kind' | 'class'>): string {
  const index = /^s(\d+)$/.exec(s.id);
  const i = index ? Number(index[1]) : -1;
  const legacy = ['G2 V', 'B2 V', 'K1 III', 'A0 V'];
  if (s.kind !== 'star' || i < 30 || s.class !== legacy[i % 4]) return s.class;
  return (
    (
      { 0: 'O5 V', 1: 'NS', 2: 'PSR', 3: 'M5 V', 4: 'B0 V', 5: 'F5 V', 6: 'K5 III' } as Record<number, string>
    )[i % 64] ?? s.class
  );
}

export function stellarProfile(s: Pick<StarSystem, 'id' | 'kind' | 'class' | 'color'>): StellarProfile {
  const spectral = stellarClass(s);
  const common = { spectral, emission: 1.12, corona: 0.42 };
  if (s.kind === 'rift')
    return {
      ...common,
      family: 'rift',
      label: 'Raumzeitriss',
      color: '#ffb65f',
      spill: '#ffb65f',
      radius: 27,
      description: 'Ein leuchtender Bruch in der lokalen Raumzeit.',
    };
  if (s.kind === 'blackhole') {
    const quasar = /quasar|agn/i.test(spectral);
    return {
      ...common,
      family: quasar ? 'quasar' : 'blackhole',
      label: quasar ? 'Quasar' : 'Schwarzes Loch',
      color: quasar ? '#99dfff' : '#ffbe84',
      spill: quasar ? '#8eaaff' : '#b095ff',
      radius: quasar ? 36 : 27,
      description: quasar
        ? 'Aktiver galaktischer Kern: Materie heizt die Akkretionsscheibe auf. Zwei polare Jets durchziehen den Raum. Maßstäbe sind für die Kartografie komprimiert.'
        : 'Ein dunkler Ereignishorizont, umgeben von einer heißen Akkretionsscheibe und einem schmalen Photonenring.',
    };
  }
  if (/^PSR|pulsar/i.test(spectral))
    return {
      ...common,
      family: 'pulsar',
      label: 'Pulsar',
      color: '#a4e7ff',
      spill: '#73aaff',
      radius: 12,
      emission: 1.28,
      corona: 0.22,
      description:
        'Ein rotierender Neutronenstern. Zwei geneigte Strahlungskegel überstreichen das System wie ein Leuchtfeuer.',
    };
  if (/^NS|neutron/i.test(spectral))
    return {
      ...common,
      family: 'neutron',
      label: 'Neutronenstern',
      color: '#c4f3ff',
      spill: '#75bcde',
      radius: 14,
      emission: 1.2,
      corona: 0.25,
      description:
        'Ein kompakter Sternrest mit extremer Dichte. Magnetfeldbögen umschließen seine blauweiße Oberfläche.',
    };
  const letter = spectral.charAt(0).toUpperCase();
  const palette: Record<string, string> = {
    O: '#80baff',
    B: '#aecfff',
    A: '#d6e5ff',
    F: '#fff1d8',
    G: '#ffe0a4',
    K: '#ffb078',
    M: '#fa8661',
  };
  const color = palette[letter] ?? s.color;
  const giant = /\sI(?:a|b|I)/.test(spectral);
  return {
    ...common,
    family: giant ? 'giant' : 'main',
    label: giant ? `${letter}-Klasse · Riesenstern` : `${letter}-Klasse · Hauptreihenstern`,
    color,
    spill: letter === 'G' ? '#ff7dbb' : color,
    radius: giant ? 44 : letter === 'O' ? 42 : letter === 'M' ? 24 : 32,
    emission: letter === 'O' ? 1.3 : 1.12,
    corona: letter === 'O' ? 0.52 : 0.36,
    description:
      letter === 'O'
        ? 'Ein heißer, massereicher blauer Stern. Eine strukturierte Korona zeichnet seinen starken Sternwind nach.'
        : giant
          ? 'Ein ausgedehnter Riesenstern mit langsam wandernden Plasmazellen und einer warmen äußeren Hülle.'
          : 'Strukturierte Photosphäre und feine Plasmafilamente. Kollektoren arbeiten auf einem sicheren Sonnenorbit.',
  };
}
