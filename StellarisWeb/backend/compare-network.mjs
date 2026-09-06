import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Run serially: these clients and the native database share the test machine.
const seconds = Number(process.argv[2] || 60);
if (!Number.isInteger(seconds) || seconds < 10 || seconds > 3600) throw new Error('Duration must be 10..3600 seconds');
const cwd = fileURLToPath(new URL('..', import.meta.url));
const heavy = ['--scenario=backend/scenarios/battle-heavy.json', '--profile=network-heavy'];
const runs = [
  [...heavy, '--detail=legacy', '--compression=none'],
  [...heavy, '--detail=compact', '--compression=none'],
  [...heavy, '--detail=compact', '--compression=gzip'],
  [...heavy, '--detail=compact', '--compression=gzip', '--battle-copies=10'],
  ['--profile=large', '--detail=compact', '--compression=gzip'],
];
for (const args of runs) {
  console.log(`\nNetwork comparison: ${args.join(' ')}`);
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--import=tsx', 'backend/benchmark.ts', ...args, `--seconds=${seconds}`], {
      cwd, windowsHide: true, stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`Benchmark stopped: ${signal || code}`)));
  });
}
