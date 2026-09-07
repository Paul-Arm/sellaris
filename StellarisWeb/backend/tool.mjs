import { execFile, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

export const root = resolve(import.meta.dirname, '..');
export function cliAsync(args) {
  const bundled = resolve(
    root,
    '.tools/spacetime',
    process.platform === 'win32' ? 'spacetimedb-cli.exe' : 'spacetimedb-cli',
  );
  const executable = process.env.SPACETIME_CLI || (existsSync(bundled) ? bundled : 'spacetime');
  return new Promise((resolveResult, reject) => {
    execFile(
      executable,
      ['--root-dir', resolve(root, '.spacetime'), ...args],
      {
        cwd: root,
        windowsHide: true,
        encoding: 'utf8',
        timeout: 20000,
      },
      (error, stdout) => (error ? reject(error) : resolveResult(stdout)),
    );
  });
}
export function cli(args, options = {}) {
  const bundled = resolve(
    root,
    '.tools/spacetime',
    process.platform === 'win32' ? 'spacetimedb-cli.exe' : 'spacetimedb-cli',
  );
  const executable = process.env.SPACETIME_CLI || (existsSync(bundled) ? bundled : 'spacetime');
  const result = spawnSync(executable, ['--root-dir', resolve(root, '.spacetime'), ...args], {
    cwd: root,
    windowsHide: true,
    encoding: 'utf8',
    ...options,
  });
  if (result.error)
    throw new Error(
      `SpacetimeDB CLI unavailable. Run backend/setup.ps1 or set SPACETIME_CLI. ${result.error.message}`,
    );
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || `CLI exited ${result.status}`);
  return result.stdout;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  const [action, ...args] = process.argv.slice(2);
  const server = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
  if (action === 'start')
    cli(['start', '--listen-addr', '127.0.0.1:3100', '--non-interactive', ...args], { stdio: 'inherit' });
  else if (action === 'build') {
    process.stdout.write(cli(['build', '--module-path', 'spacetimedb']));
    process.stdout.write(
      cli([
        'generate',
        '--lang',
        'typescript',
        '--js-path',
        'spacetimedb/dist/bundle.js',
        '--out-dir',
        'backend/module_bindings',
        '--yes',
      ]),
    );
  } else if (action === 'publish') {
    const name = args[0] || 'singularity-lab';
    process.stdout.write(
      cli([
        'publish',
        name,
        '--server',
        server,
        '--js-path',
        'spacetimedb/dist/bundle.js',
        '--yes=skip-login',
      ]),
    );
  } else throw new Error('Usage: node backend/tool.mjs start|build|publish [database]');
}
