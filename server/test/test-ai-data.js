/**
 * Agent 敏感数据与文件审批测试
 *
 * 运行：node test/test-ai-data.js
 */

import { EventEmitter } from 'node:events'

import {
  classifyReadPath,
  containsCoreCredentialPath,
  DataRisk,
  stricterDataRisk
} from '../app/ai/data-policy.js'
import { redact } from '../app/ai/redact.js'
import { fit, read, clearBySession } from '../app/ai/output-store.js'
import {
  buildFullReplacementDiff,
  buildWriteFilePreviewWithSftp,
  MAX_WRITE_FILE_BYTES,
  validateWriteFileInput
} from '../app/ai/write-preview.js'
import {
  backupPathForAttempt,
  createUniqueBackup,
  formatBackupTimestamp
} from '../app/ai/file-backup.js'

let passed = 0
let failed = 0
const failures = []

function expect(label, actual, want) {
  if (JSON.stringify(actual) === JSON.stringify(want)) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`  ${ label }\n    期望: ${ JSON.stringify(want) }\n    实际: ${ JSON.stringify(actual) }`)
}

function assert(label, condition) {
  if (condition) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`  ${ label }\n    断言失败`)
}

function expectThrow(label, fn, matcher) {
  try {
    fn()
    failed += 1
    failures.push(`  ${ label }\n    期望抛出但成功返回了`)
  } catch (error) {
    if (matcher.test(error.message)) {
      passed += 1
      return
    }
    failed += 1
    failures.push(`  ${ label }\n    错误不符预期: ${ error.message }`)
  }
}

console.log('\n========== 敏感路径分级 ==========')

expect('/etc/shadow 高危读取', classifyReadPath('/etc/shadow').risk, DataRisk.HIGH)
expect('SSH 私钥高危读取', classifyReadPath('/root/.ssh/id_rsa').risk, DataRisk.HIGH)
expect('AWS credentials 高危读取', classifyReadPath('/root/.aws/credentials').risk, DataRisk.HIGH)
expect('大写 SSH 私钥名高危读取', classifyReadPath('/root/.SSH/ID_RSA').risk, DataRisk.HIGH)
expect('解释器表达式中的 shadow 路径可识别', containsCoreCredentialPath('open("/etc/shadow").read()'), true)
expect('普通绝对路径不误判', containsCoreCredentialPath('open("/etc/nginx/nginx.conf").read()'), false)
expect('.env 需要确认', classifyReadPath('/opt/app/.env').risk, DataRisk.HIGH)
expect('shell history 需要确认', classifyReadPath('/root/.bash_history').risk, DataRisk.HIGH)
expect('普通配置正常读取', classifyReadPath('/etc/nginx/nginx.conf').risk, DataRisk.NORMAL)
expect(
  '符号链接真实路径采用更严格分级',
  stricterDataRisk(
    classifyReadPath('/tmp/current-config'),
    classifyReadPath('/etc/shadow')
  ).risk,
  DataRisk.HIGH
)

console.log('\n========== 脱敏与输出隔离 ==========')

{
  const shadow = 'root:$6$salt$hash:19793:0:99999:7:::'
  assert('shadow 哈希被脱敏', !redact(shadow).text.includes('$6$salt$hash'))

  const quoted = 'AWS_SECRET_ACCESS_KEY = \'abc def ghi jkl\''
  assert('带空格的引号 secret 被脱敏', !redact(quoted).text.includes('abc def ghi jkl'))

  const sessionId = 'data-session'
  const secret = 'token=super-secret-value'
  const stored = fit(`${ secret }\n${ 'x'.repeat(9 * 1024) }`, { sessionId })
  assert('长输出生成回读 handle', Boolean(stored.handle))
  expect('错误会话不能回读', read(stored.handle, { sessionId: 'other' }).ok, false)
  const result = read(stored.handle, { sessionId })
  expect('当前会话可以回读', result.ok, true)
  assert('暂存内容本身已经脱敏', !result.content.includes('super-secret-value'))

  const approved = fit('token=approved-secret-value', { sessionId }, { allowSensitive: true })
  assert('批准后的敏感读取保留原始内容', approved.text.includes('approved-secret-value'))
  clearBySession(sessionId)
}

console.log('\n========== 文件写入预览 ==========')

{
  const diff = buildFullReplacementDiff('/etc/app.conf', 'a=1\nb=2\n', 'a=1\nb=3\nc=4\n', false)
  assert('diff 包含完整旧内容', diff.includes('-b=2'))
  assert('diff 包含完整新内容', diff.includes('+b=3') && diff.includes('+c=4'))
  assert('diff 标记目标路径', diff.includes('+++ /etc/app.conf (proposed)'))

  expect('合法写入参数通过', validateWriteFileInput({
    path: '/etc/app.conf',
    content: 'ok',
    mode: '0644'
  }).bytes, 2)
  expectThrow('相对路径被拒绝', () => validateWriteFileInput({
    path: 'app.conf',
    content: 'ok'
  }), /绝对路径/)
  expect('核心系统文件可进入高危审批', validateWriteFileInput({
    path: '/etc/../etc/passwd',
    content: 'root:x:0:0:root:/root:/bin/bash\n'
  }).pathname, '/etc/../etc/passwd')
  const protectedPreview = await buildWriteFilePreviewWithSftp({
    stat(_path, callback) {
      callback(null, { isDirectory: () => false, size: 0, mode: 0o100644 })
    },
    realpath(_path, callback) {
      callback(null, '/etc/passwd')
    },
    createReadStream() {
      const stream = new EventEmitter()
      queueMicrotask(() => stream.emit('end'))
      return stream
    }
  }, 'host-1', {
    path: '/tmp/config-link',
    content: 'replacement'
  })
  expect('符号链接真实路径进入预览', protectedPreview.realPath, '/etc/passwd')
  expectThrow('非法权限被拒绝', () => validateWriteFileInput({
    path: '/etc/app.conf',
    content: 'ok',
    mode: '999'
  }), /八进制/)
  expectThrow('超大内容被拒绝', () => validateWriteFileInput({
    path: '/etc/app.conf',
    content: 'x'.repeat(MAX_WRITE_FILE_BYTES + 1)
  }), /预览上限/)
  expectThrow('二进制内容被拒绝', () => validateWriteFileInput({
    path: '/etc/app.conf',
    content: 'text\0binary'
  }), /二进制/)
}

console.log('\n========== 唯一备份文件 ==========')

{
  const fixedTime = Date.parse('2026-07-31T12:34:56.789Z')
  const timestamp = formatBackupTimestamp(fixedTime)
  expect('备份时间戳不含路径非法字符', timestamp, '20260731T123456789Z')
  expect(
    '碰撞序号追加在时间戳后',
    backupPathForAttempt('/etc/app.conf', timestamp, 2),
    '/etc/app.conf.bak.20260731T123456789Z.2'
  )

  const occupied = new Set([
    '/etc/app.conf.bak.20260731T123456789Z',
    '/etc/app.conf.bak.20260731T123456789Z.1'
  ])
  const copied = []
  const backupPath = await createUniqueBackup({}, '/etc/app.conf', {
    now: () => fixedTime,
    pathExists: async (_sftp, pathname) => occupied.has(pathname),
    copy: async (_sftp, from, to) => copied.push({ from, to })
  })
  expect('既有备份不会被覆盖', backupPath, '/etc/app.conf.bak.20260731T123456789Z.2')
  expect('实际复制到选中的唯一路径', copied, [{
    from: '/etc/app.conf',
    to: '/etc/app.conf.bak.20260731T123456789Z.2'
  }])

  const raced = new Set()
  let copyAttempts = 0
  const racedPath = await createUniqueBackup({}, '/etc/race.conf', {
    now: () => fixedTime,
    pathExists: async (_sftp, pathname) => raced.has(pathname),
    copy: async (_sftp, _from, to) => {
      copyAttempts += 1
      if (copyAttempts === 1) {
        raced.add(to)
        throw Object.assign(new Error('Failure'), {
          backupOrigin: 'target',
          backupTargetOpened: false
        })
      }
    }
  })
  expect('并发创建碰撞后自动换序号', racedPath, '/etc/race.conf.bak.20260731T123456789Z.1')
}

console.log('\n==================================')
if (failed === 0) {
  console.log(`✅ 全部通过 (${ passed } 项)`)
  process.exit(0)
}
console.log(`❌ ${ failed } 项失败 / 共 ${ passed + failed } 项\n`)
console.log(failures.join('\n\n'))
process.exit(1)
