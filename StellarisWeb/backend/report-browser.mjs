import { readFileSync, writeFileSync } from 'node:fs';
const samples = ['galaxy', 'battle'].map(mode => {
  const envelope = JSON.parse(readFileSync(`backend/reports/browser-${mode}.raw.json`, 'utf8').replace(/^\uFEFF/, ''));
  if (!envelope.success) throw new Error(`Browser measurement failed: ${mode}`);
  return JSON.parse(envelope.data.result);
});
const report = {
  measuredAt: new Date().toISOString(), database: 'singularity-foundation', samples,
  refreshRateCapHz: 165, capSource: 'User confirmed that 165 FPS is the monitor refresh-rate cap.',
  interpretation: 'The renderer reaches the 165-Hz/VSync cap. These are requestAnimationFrame intervals, not isolated GPU or CPU execution timings. No performance headroom or uncapped FPS can be inferred.',
  workload: 'One connected browser; 1,000 systems, 75,000 stored ships, 3,000 participants in one ongoing battle; other load-test databases paused.',
  limitations: ['Lab scene uses simple instanced geometry and a precomputed gravity field; full game effects are not included.',
    'Browser measurements run separately from the 25-client load tests.', 'Not an uncapped GPU benchmark.'],
};
writeFileSync('backend/reports/browser.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
