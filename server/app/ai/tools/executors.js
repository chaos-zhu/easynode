/**
 * 工具实现
 *
 * 约定：
 *   - 每个 executor 返回 { ok, data } 或 { ok: false, error }，由 index.js 统一
 *     序列化成模型可读的文本，executor 自己不关心格式
 *   - Runtime 已完成分类和审批，executor 消费同一次分析结果
 *   - 只有模型提供的命令才需要过 safety，本文件内部固定的探测脚本不需要
 */

import { createHash } from 'node:crypto'
import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { HostListDB, GroupDB, ScriptGroupDB } from '../../utils/db-class.js'
import { getScriptById, listScripts } from '../../script-library.js'
import { execCommand, withSftp, DEFAULT_TIMEOUT_MS } from '../ssh.js'
import { fit, read as readOutput } from '../output-store.js'
import { writeAudit, ACTION } from '../audit.js'
import { DEFAULT_HOST_POLICY } from '../policy.js'
import { resolveHostAccess } from '../host-access.js'
import { classifyReadPath, DataRisk, stricterDataRisk } from '../data-policy.js'
import { Effect } from '../policy.js'
import decryptAndExecuteAsync from '../../utils/decrypt-file.js'

const hostListDB = new HostListDB().getInstance()
const groupDB = new GroupDB().getInstance()
const scriptGroupDB = new ScriptGroupDB().getInstance()
const currentDir = dirname(fileURLToPath(import.meta.url))
const restrictedToolPath = path.join(currentDir, '../plus.js')

const DEFAULT_READ_BYTES = 64 * 1024
const PLUS_REQUIRED_CODE = 'PLUS_REQUIRED'
const PLUS_REQUIRED_MESSAGE = '非读取操作需激活 [Plus] 使用(解锁完整AI能力)'

function fail(error, code) {
  return { ok: false, error, ...(code ? { code } : {}) }
}

function ok(data) {
  return { ok: true, data }
}

function preparedOperation(ctx, toolCallId) {
  const operation = toolCallId ? ctx.toolMeta?.[toolCallId] : null
  return operation?.effect && operation?.risk ? operation : null
}

/**
 * 取得目标主机，同时执行主机级权限判定。
 *
 * 判定逻辑集中在 host-access.js，这里只是调用点 —— 每个碰主机的工具
 * 都必须走这一步，否则主机分级策略就有缺口。
 */
async function requireHost(ctx, hostId, effect) {
  const { host } = await resolveHostAccess(hostId, ctx, effect)
  return host
}

function emitPlusRequired(ctx, tool, effect, toolCallId) {
  ctx.emit?.({
    type: 'tool_requires_plus',
    toolCallId,
    tool,
    effect,
    code: PLUS_REQUIRED_CODE,
    message: PLUS_REQUIRED_MESSAGE,
    activationPath: '/setting?tabKey=plus'
  })
}

async function loadRestrictedToolModule(ctx, tool, effect, toolCallId) {
  const plusModule = await decryptAndExecuteAsync(restrictedToolPath)
  if (plusModule?.assertPlusAccess && plusModule?.executeRestrictedTool) {
    try {
      plusModule.assertPlusAccess()
      return plusModule
    } catch {
      // 授权可能刚好在模块加载后失效，统一按 Plus 不可用处理。
    }
  }
  emitPlusRequired(ctx, tool, effect, toolCallId)
  return null
}

/** 在弹出审批前校验，避免让未激活用户确认一个必然无法执行的操作。 */
export async function checkRestrictedToolAccess(ctx, tool, effect, toolCallId) {
  if (effect === Effect.READ) return { ok: true }
  const plusModule = await loadRestrictedToolModule(ctx, tool, effect, toolCallId)
  return plusModule
    ? { ok: true }
    : fail(PLUS_REQUIRED_MESSAGE, PLUS_REQUIRED_CODE)
}

/** 审批完成后再次加载并校验，防止等待期间 Plus 状态发生变化。 */
async function executeRestrictedTool(tool, ctx, input, options) {
  const effect = preparedOperation(ctx, options?.toolCallId)?.effect || Effect.WRITE
  const plusModule = await loadRestrictedToolModule(ctx, tool, effect, options?.toolCallId)
  if (!plusModule) return fail(PLUS_REQUIRED_MESSAGE, PLUS_REQUIRED_CODE)
  try {
    return await plusModule.executeRestrictedTool(tool, ctx, input, options)
  } catch (error) {
    return fail(error?.message || String(error))
  }
}

// ---------------------------------------------------------------- host_list

export async function hostList(ctx, input) {
  const allowedHostIds = ctx.allowedHostIds instanceof Set ? [...ctx.allowedHostIds] : []
  if (!allowedHostIds.length) return ok({ total: 0, hosts: [] })

  const [hosts, groups] = await Promise.all([
    hostListDB.findAsync({ _id: { $in: allowedHostIds } }),
    groupDB.findAsync({})
  ])
  const groupName = new Map(groups.map((group) => [group._id, group.name]))

  const keyword = (input.keyword || '').trim().toLowerCase()
  const items = hosts
    .filter((host) => {
      if (!keyword) return true
      const group = groupName.get(host.group) || ''
      return [host.name, host.host, group].some((field) => String(field || '').toLowerCase().includes(keyword))
    })
    .map((host) => {
      const policy = { ...DEFAULT_HOST_POLICY, ...(host.aiPolicy || {}) }
      return {
        hostId: host._id,
        name: host.name,
        host: host.host,
        port: host.port,
        username: host.username,
        group: groupName.get(host.group) || 'default',
        aiEnabled: policy.enabled !== false,
        maxEffect: policy.maxEffect,
        maxMode: policy.maxMode
      }
    })

  return ok({ total: items.length, hosts: items })
}

// -------------------------------------------------------------- host_status

// 固定探测脚本：由本模块生成，不经过 safety 判定
const STATUS_PROBE = [
  'echo "@@os@@"; grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null || uname -s',
  'echo "@@kernel@@"; uname -r',
  'echo "@@arch@@"; uname -m',
  'echo "@@hostname@@"; hostname',
  'echo "@@uptime@@"; cat /proc/uptime 2>/dev/null || uptime',
  'echo "@@load@@"; cat /proc/loadavg 2>/dev/null || uptime',
  'echo "@@cpucount@@"; nproc 2>/dev/null || grep -c processor /proc/cpuinfo',
  'echo "@@mem@@"; free -m 2>/dev/null | head -3',
  'echo "@@disk@@"; df -h 2>/dev/null | grep -vE "^(tmpfs|devtmpfs|overlay)" | head -15',
  'echo "@@topproc@@"; ps -eo pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6'
].join('; ')

function parseProbe(stdout) {
  const sections = {}
  const parts = stdout.split(/@@([a-z]+)@@\r?\n?/)
  for (let i = 1; i < parts.length; i += 2) {
    sections[parts[i]] = (parts[i + 1] || '').trim()
  }
  return sections
}

function formatUptime(raw) {
  const seconds = Number.parseFloat(raw)
  if (!Number.isFinite(seconds)) return raw
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  return `${ days } 天 ${ hours } 小时 ${ minutes } 分`
}

function parseMemory(raw) {
  // free -m 的第二行：Mem: total used free shared buff/cache available
  const line = raw.split('\n').find((item) => /^Mem:/i.test(item.trim()))
  if (!line) return null
  const columns = line.trim().split(/\s+/)
  return {
    totalMB: Number(columns[1]) || null,
    usedMB: Number(columns[2]) || null,
    freeMB: Number(columns[3]) || null,
    availableMB: Number(columns[6]) || null
  }
}

export async function hostStatus(ctx, input) {
  const host = await requireHost(ctx, input.hostId, Effect.READ)
  const result = await execCommand(host._id, STATUS_PROBE, {
    timeoutMs: 20 * 1000,
    signal: ctx.signal,
    nonInteractive: false
  })

  if (result.timedOut) return fail(`获取「${ host.name }」状态超时`)

  const sections = parseProbe(result.stdout)
  const loadParts = (sections.load || '').split(/\s+/)

  return ok({
    hostId: host._id,
    name: host.name,
    address: `${ host.host }:${ host.port }`,
    os: (sections.os || '').replace(/^PRETTY_NAME=/, '').replace(/"/g, ''),
    kernel: sections.kernel,
    arch: sections.arch,
    hostname: sections.hostname,
    uptime: formatUptime(sections.uptime),
    load: loadParts.length >= 3 ? { '1m': loadParts[0], '5m': loadParts[1], '15m': loadParts[2] } : sections.load,
    cpuCount: Number(sections.cpucount) || sections.cpucount,
    memory: parseMemory(sections.mem || ''),
    disk: sections.disk,
    topProcesses: sections.topproc
  })
}

// ------------------------------------------------------------ script library

export async function scriptList(_ctx, input) {
  const keyword = String(input.keyword || '').trim().toLowerCase()
  const [scripts, groups] = await Promise.all([listScripts(), scriptGroupDB.findAsync({})])
  const groupName = new Map(groups.map((group) => [group._id, group.name]))
  const items = scripts
    .filter((script) => !keyword || [script.name, script.description, script.group, groupName.get(script.group)]
      .some((field) => String(field || '').toLowerCase().includes(keyword)))
    .map((script) => ({
      scriptId: script.id,
      name: script.name,
      description: script.description || '',
      group: groupName.get(script.group) || script.group || 'default',
      builtin: script.builtin === true,
      useBase64: script.useBase64 === true
    }))

  return ok({ total: items.length, scripts: items })
}

export async function runScript(ctx, input, options = {}) {
  const script = await getScriptById(input.scriptId)
  if (!script) return fail('脚本不存在，可能已被删除；请先调用 script_list 刷新脚本库')

  const command = String(script.command || '').trim()
  if (!command) return fail(`脚本「${ script.name || input.scriptId }」没有可执行内容`)
  const operation = preparedOperation(ctx, options.toolCallId)
  if (!operation) return fail('缺少本次脚本对应的有效分析结果')
  if (operation.effect !== Effect.READ) {
    return executeRestrictedTool('run_script', ctx, input, options)
  }
  const expectedHash = options.toolCallId ? ctx.authorizedScripts?.get(options.toolCallId) : null
  if (options.toolCallId) ctx.authorizedScripts?.delete(options.toolCallId)
  const currentHash = createHash('sha256').update(command).digest('hex')
  if (!expectedHash || expectedHash !== currentHash) return fail('脚本内容已变化或缺少本次调用的有效授权，请重新执行')
  const host = await requireHost(ctx, input.hostId, operation.effect)

  const timeoutMs = input.timeoutSeconds ? input.timeoutSeconds * 1000 : DEFAULT_TIMEOUT_MS
  let result
  try {
    result = await execCommand(host._id, command, {
      timeoutMs,
      signal: ctx.signal
    })
  } catch (error) {
    writeAudit({
      action: ACTION.EXEC,
      sessionId: ctx.sessionId,
      userId: ctx.userId,
      hostId: host._id,
      hostName: host.name,
      tool: 'run_script',
      command,
      reason: error.message
    })
    return fail(`脚本执行失败: ${ error.message }`)
  }

  writeAudit({
    action: ACTION.EXEC,
    sessionId: ctx.sessionId,
    userId: ctx.userId,
    hostId: host._id,
    hostName: host.name,
    tool: 'run_script',
    command,
    mode: ctx.policy?.mode,
    effect: operation.effect,
    risk: operation.risk,
    exitCode: result.exitCode,
    durationMs: result.durationMs
  })

  const meta = { sessionId: ctx.sessionId, hostId: host._id, command }
  const outputOptions = { allowSensitive: options.allowSensitiveOutput }
  const stdout = fit(result.stdout, meta, outputOptions)
  const stderr = fit(result.stderr, meta, outputOptions)
  return ok({
    scriptId: script.id,
    scriptName: script.name,
    hostName: host.name,
    exitCode: result.timedOut ? null : result.exitCode,
    timedOut: result.timedOut || undefined,
    aborted: result.signal === 'ABORTED' || undefined,
    durationMs: result.durationMs,
    stdout: stdout.text,
    stderr: stderr.text,
    stdoutHandle: stdout.handle || undefined,
    stderrHandle: stderr.handle || undefined,
    note: result.timedOut
      ? `脚本在 ${ Math.round(timeoutMs / 1000) } 秒后超时被终止，以上是超时前的输出`
      : undefined
  })
}

// ------------------------------------------------------------ exec_command

export async function execCommandTool(ctx, input, options = {}) {
  const command = String(input.command || '').trim()
  if (!command) return fail('command 不能为空')
  const operation = preparedOperation(ctx, options.toolCallId)
  if (!operation) return fail('缺少本次命令对应的有效分析结果')
  if (operation.effect !== Effect.READ) {
    return executeRestrictedTool('exec_command', ctx, input, options)
  }
  const host = await requireHost(ctx, input.hostId, operation.effect)

  const timeoutMs = input.timeoutSeconds ? input.timeoutSeconds * 1000 : DEFAULT_TIMEOUT_MS

  let result
  try {
    result = await execCommand(host._id, command, {
      timeoutMs,
      cwd: input.cwd,
      signal: ctx.signal
    })
  } catch (error) {
    writeAudit({
      action: ACTION.EXEC,
      sessionId: ctx.sessionId,
      userId: ctx.userId,
      hostId: host._id,
      hostName: host.name,
      tool: 'exec_command',
      command,
      reason: error.message
    })
    return fail(`执行失败: ${ error.message }`)
  }

  writeAudit({
    action: ACTION.EXEC,
    sessionId: ctx.sessionId,
    userId: ctx.userId,
    hostId: host._id,
    hostName: host.name,
    tool: 'exec_command',
    command,
    executed: result.executed,
    mode: ctx.policy?.mode,
    effect: operation.effect,
    risk: operation.risk,
    exitCode: result.exitCode,
    durationMs: result.durationMs
  })

  const meta = { sessionId: ctx.sessionId, hostId: host._id, command }
  const outputOptions = { allowSensitive: options.allowSensitiveOutput }
  const stdout = fit(result.stdout, meta, outputOptions)
  const stderr = fit(result.stderr, meta, outputOptions)

  return ok({
    hostName: host.name,
    exitCode: result.timedOut ? null : result.exitCode,
    timedOut: result.timedOut || undefined,
    aborted: result.signal === 'ABORTED' || undefined,
    durationMs: result.durationMs,
    stdout: stdout.text,
    stderr: stderr.text,
    stdoutHandle: stdout.handle || undefined,
    stderrHandle: stderr.handle || undefined,
    note: result.timedOut
      ? `命令在 ${ Math.round(timeoutMs / 1000) } 秒后超时被终止，以上是超时前的输出`
      : undefined
  })
}

// ---------------------------------------------------------------- SFTP 工具

function sftpStat(sftp, path) {
  return new Promise((resolve, reject) => {
    sftp.stat(path, (err, stats) => (err ? reject(err) : resolve(stats)))
  })
}

function sftpReaddir(sftp, path) {
  return new Promise((resolve, reject) => {
    sftp.readdir(path, (err, list) => (err ? reject(err) : resolve(list)))
  })
}

function readStreamRange(sftp, path, start, end) {
  return new Promise((resolve, reject) => {
    const chunks = []
    const stream = sftp.createReadStream(path, { start, end })
    stream.on('data', (chunk) => chunks.push(chunk))
    stream.on('error', reject)
    stream.on('end', () => resolve(Buffer.concat(chunks)))
  })
}

export async function readFile(ctx, input, options = {}) {
  const host = await requireHost(ctx, input.hostId, Effect.READ)
  const maxBytes = input.maxBytes || DEFAULT_READ_BYTES

  return withSftp(host._id, async (sftp) => {
    const realPath = await new Promise((resolve) => {
      sftp.realpath(input.path, (error, resolved) => resolve(error || !resolved ? input.path : resolved))
    })
    const dataRisk = stricterDataRisk(classifyReadPath(input.path), classifyReadPath(realPath))
    if (dataRisk.risk === DataRisk.HIGH) {
      const toolCallId = options.toolCallId
      const approvedPath = toolCallId ? ctx.approvedReads?.get(toolCallId) : null
      if (toolCallId) ctx.approvedReads?.delete(toolCallId)
      if (!approvedPath || approvedPath !== realPath) {
        return fail('敏感文件缺少与当前真实路径匹配的有效审批，请重新确认')
      }
    }

    let stats
    try {
      stats = await sftpStat(sftp, input.path)
    } catch (error) {
      return fail(`无法读取 ${ input.path }: ${ error.message }`)
    }

    if (stats.isDirectory()) return fail(`${ input.path } 是目录，请用 list_dir`)
    if (stats.size === 0) return ok({ path: input.path, size: 0, content: '', note: '文件为空' })

    const end = Math.min(stats.size, maxBytes) - 1
    let buffer
    try {
      buffer = await readStreamRange(sftp, input.path, 0, end)
    } catch (error) {
      return fail(`读取 ${ input.path } 失败: ${ error.message }`)
    }

    const fitted = fit(
      buffer.toString('utf8'),
      { sessionId: ctx.sessionId, hostId: host._id, path: input.path },
      { allowSensitive: options.allowSensitiveOutput }
    )
    return ok({
      path: input.path,
      size: stats.size,
      content: fitted.text,
      handle: fitted.handle || undefined,
      note: stats.size > maxBytes
        ? `文件共 ${ stats.size } 字节，仅读取了前 ${ maxBytes } 字节`
        : undefined
    })
  })
}

export async function writeFile(ctx, input, options = {}) {
  return executeRestrictedTool('write_file', ctx, input, options)
}

function formatMode(mode) {
  return (mode & 0o777).toString(8).padStart(3, '0')
}

export async function listDir(ctx, input) {
  const host = await requireHost(ctx, input.hostId, Effect.READ)

  return withSftp(host._id, async (sftp) => {
    let entries
    try {
      entries = await sftpReaddir(sftp, input.path)
    } catch (error) {
      return fail(`无法列出 ${ input.path }: ${ error.message }`)
    }

    const items = entries.map((entry) => ({
      name: entry.filename,
      type: entry.attrs.isDirectory() ? 'dir' : entry.attrs.isSymbolicLink() ? 'link' : 'file',
      size: entry.attrs.size,
      mode: formatMode(entry.attrs.mode),
      modifiedAt: new Date(entry.attrs.mtime * 1000).toISOString()
    })).sort((a, b) => {
      if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
      return a.name.localeCompare(b.name)
    })

    return ok({ path: input.path, total: items.length, entries: items })
  })
}

// ------------------------------------------------------------- read_output

export async function readOutputTool(ctx, input) {
  const result = readOutput(input.handle, { ...input, sessionId: ctx.sessionId })
  if (!result.ok) return fail(result.error)
  return ok(result)
}

// ---------------------------------------------------------- Web 终端命令

export async function terminalCommand(ctx, input, options = {}) {
  if (ctx.scope !== 'terminal' || !ctx.requestTerminalDispatch) {
    return fail('当前会话不支持向 Web 终端提交命令')
  }
  if (input.hostId !== ctx.terminalHostId) {
    return fail('命令目标与当前终端主机不一致')
  }
  const operation = preparedOperation(ctx, options.toolCallId)
  if (!operation) return fail('缺少本次命令对应的有效分析结果')
  if (operation.effect !== Effect.READ) {
    return executeRestrictedTool('terminal_command', ctx, input, options)
  }
  await resolveHostAccess(input.hostId, ctx, operation.effect)

  const result = await ctx.requestTerminalDispatch({ ...input, toolCallId: options.toolCallId })
  if (!result.ok) return fail(result.error || '终端未能接收命令')

  writeAudit({
    action: ACTION.EXEC,
    sessionId: ctx.sessionId,
    userId: ctx.userId,
    hostId: ctx.terminalHostId,
    hostName: ctx.hosts[0]?.name,
    tool: 'terminal_command',
    command: input.command,
    mode: ctx.terminalPermission,
    effect: operation.effect,
    risk: operation.risk
  })

  const stdout = fit(result.output || '', {
    sessionId: ctx.sessionId,
    hostId: ctx.terminalHostId,
    command: input.command
  }, { allowSensitive: options.allowSensitiveOutput })

  return ok({
    submitted: true,
    hostName: ctx.hosts[0]?.name,
    command: input.command,
    stdout: stdout.text,
    stdoutHandle: stdout.handle || undefined,
    outputTruncated: stdout.truncated || undefined,
    capturedAt: result.capturedAt,
    durationMs: result.durationMs,
    exitCode: result.exitCode,
    note: '命令已在当前 Web 终端完成；以下内容仅包含本次命令的输出。'
  })
}

export const EXECUTORS = {
  host_list: hostList,
  host_status: hostStatus,
  script_list: scriptList,
  run_script: runScript,
  exec_command: execCommandTool,
  read_file: readFile,
  write_file: writeFile,
  list_dir: listDir,
  read_output: readOutputTool,
  terminal_command: terminalCommand
}
