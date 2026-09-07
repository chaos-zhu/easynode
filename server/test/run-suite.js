import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const testDirectory = dirname(fileURLToPath(import.meta.url))
const serverDirectory = resolve(testDirectory, '..')

const suites = {
  default: [
    'test-order-service.js',
    'test-onekey-execution.js',
    'test-terminal-settings.js',
    'test-login-attempt-limiter.js',
    'test-login-ip-async.js',
    'test-auth-session.js',
    'test-ip-access.js',
    'test-ping-output.js',
    'test-sftp-cache-path.js',
    'test-rsync-command.js',
    'test-cookie-config.js',
    'test-rest-api-auth.js',
    'test-ws-comprehensive.js'
  ],
  security: [
    'test-login-attempt-limiter.js',
    'test-login-ip-async.js',
    'test-auth-session.js',
    'test-ip-access.js',
    'test-sftp-cache-path.js',
    'test-rsync-command.js',
    'test-cookie-config.js',
    'test-ssl-cert-persistence.js'
  ],
  api: ['test-rest-api-auth.js'],
  ws: ['test-ws-comprehensive.js'],
  mobile: ['test-mobile-crypto.js', 'test-mobile-ssh-payload.js'],
  ai: [
    'test-ai-config.js',
    'test-ai-session-run-lock.js',
    'test-ai-safety.js',
    'test-ai-session.js',
    'test-ai-compaction.js',
    'test-ai-access.js',
    'test-ai-data.js',
    'test-ai-mcp.js'
  ]
}

const suiteName = process.argv[2] || 'default'
const testFiles = suites[suiteName]

if (!testFiles) {
  console.error(`未知测试套件: ${ suiteName }。可用套件: ${ Object.keys(suites).join(', ') }`)
  process.exit(1)
}

for (const testFile of testFiles) {
  const result = spawnSync(process.execPath, [resolve(testDirectory, testFile)], {
    cwd: serverDirectory,
    env: process.env,
    stdio: 'inherit'
  })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}
