import { spawn } from 'node:child_process';
const args = process.argv.slice(2);
const chrome = args.some((arg, i) => arg === '-dchrome' ||
  arg === '--device-id=chrome' || (['-d', '--device-id'].includes(arg) && args[i+1] === 'chrome'));
if (chrome && args.some(arg => /user-data-dir|--release|--profile/.test(arg))) {
  console.error('Chrome fare testing requires Flutter’s isolated debug profile.');
  process.exit(1);
}

const key = process.env.SERPAPI_API_KEY || process.env.sera_api_key;
if (!key?.trim()) {
  console.error('Set SERPAPI_API_KEY in .env first.');
  process.exit(1);
}
const encoded = Buffer.from(Buffer.from(key.trim()).map((byte, index) =>
  byte ^ ((index * 31 + 93) & 255),
)).toString('base64');
const env = { ...process.env };
delete env.SERPAPI_API_KEY;
delete env.sera_api_key;
const flutter = spawn('flutter', [
  'run', `--dart-define=SERPAPI_MOBILE_CONFIG=${encoded}`,
  ...(chrome ? ['--web-browser-flag=--disable-web-security'] : []),
  ...args,
], { stdio: ['inherit', 'inherit', 'inherit'], env });
flutter.on('exit', code => process.exitCode = code ?? 1);
flutter.on('error', () => { console.error('Flutter could not be started.'); process.exitCode = 1; });
