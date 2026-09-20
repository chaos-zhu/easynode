import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const testDirectory = dirname(fileURLToPath(import.meta.url))
const webDirectory = resolve(testDirectory, '..')
const testFiles = [
  'test-terminal-appearance.mjs',
  'test-agent-messages.js',
  'test-sticky-bottom.js',
  'test-host-sort.js',
  'test-ip-access.js',
  'test-order.js'
]

for (const testFile of testFiles) {
  const result = spawnSync(process.execPath, [
    '--experimental-default-type=module',
    resolve(testDirectory, testFile)
  ], {
    cwd: webDirectory,
    env: process.env,
    stdio: 'inherit'
  })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}
