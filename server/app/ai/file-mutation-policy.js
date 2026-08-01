/**
 * Shell 文件变更意图。
 *
 * safety.js 只负责汇总风险；命令参数中“哪些是写入/删除目标”的知识集中
 * 放在这里，避免为 rm、mv、重定向等分别维护互相漂移的保护文件正则。
 */

import path from 'node:path'
import { isSensitiveDataPath } from './data-policy.js'

const PROTECTED_PATHS = [
  /^\/etc\/(?:passwd|group)(?:-|$)/,
  /^\/etc\/(?:shadow|gshadow)(?:-|$)/,
  /^\/etc\/sudoers(?:$|\.d(?:\/|$))/,
  /^\/etc\/fstab$/
]

const SENSITIVE_PREFIXES = [
  '/bin', '/sbin', '/lib', '/lib64', '/usr', '/boot', '/etc',
  '/var/lib', '/var/www', '/var/backups', '/var/log', '/var/spool',
  '/opt', '/srv', '/data', '/home', '/root', '/mnt', '/media'
]

const CRITICAL_TREE_ROOTS = new Set([
  '/', '/bin', '/sbin', '/lib', '/lib64', '/usr', '/boot', '/etc'
])
const classificationCache = new WeakMap()

export function normalizeMutationPath(value) {
  const raw = String(value || '').trim().replace(/\\/g, '/')
  if (!raw || raw === '-') return ''
  if (!path.posix.isAbsolute(raw)) return raw.replace(/\/+$/, '') || '.'
  const normalized = path.posix.normalize(raw)
  return normalized.length > 1 ? normalized.replace(/\/+$/, '') : normalized
}

export function isProtectedMutationPath(value) {
  const normalized = normalizeMutationPath(value)
  return path.posix.isAbsolute(normalized)
    && PROTECTED_PATHS.some((pattern) => pattern.test(normalized))
}

export function isSensitiveMutationPath(value) {
  const normalized = normalizeMutationPath(value)
  if (isSensitiveDataPath(normalized)) return true
  if (!path.posix.isAbsolute(normalized)) return false
  return SENSITIVE_PREFIXES.some((prefix) => normalized === prefix || normalized.startsWith(`${ prefix }/`))
}

function pushMutation(output, action, target, extra = {}) {
  const normalized = normalizeMutationPath(target)
  if (!normalized || normalized.startsWith('&')) return
  output.push({ action, path: normalized, ...extra })
}

function optionValue(args, shortName, longName) {
  const longPrefix = `${ longName }=`
  const inline = args.find((arg) => arg.startsWith(longPrefix))
  if (inline) return inline.slice(longPrefix.length)
  const index = args.findIndex((arg) => arg === shortName || arg === longName)
  if (index !== -1) return args[index + 1] || ''
  const shortInline = args.find((arg) => arg.startsWith(shortName) && arg.length > shortName.length)
  return shortInline ? shortInline.slice(shortName.length) : ''
}

function pushCopyTargets(output, ctx, action) {
  const targetDirectory = optionValue(ctx.args, '-t', '--target-directory')
  if (targetDirectory) {
    const normalizedDirectory = normalizeMutationPath(targetDirectory)
    const sources = ctx.positionals.filter((item) => normalizeMutationPath(item) !== normalizedDirectory)
    for (const source of sources) {
      pushMutation(output, action, path.posix.join(normalizedDirectory, path.posix.basename(normalizeMutationPath(source))))
    }
    return
  }
  if (ctx.positionals.length >= 2) {
    const target = ctx.positionals.at(-1)
    pushMutation(output, action, target)
    // 静态分析无法知道目标当前是不是目录；同时检查“复制进目录后”的
    // 实际候选路径，避免 `cp /tmp/passwd /etc` 漏掉 /etc/passwd。
    for (const source of ctx.positionals.slice(0, -1)) {
      pushMutation(output, action, path.posix.join(normalizeMutationPath(target), path.posix.basename(normalizeMutationPath(source))))
    }
  }
}

/**
 * 从 safety.js 的单段上下文提取所有文件变更目标。
 */
export function extractFileMutations(ctx) {
  const output = []

  for (const redirect of ctx.redirects || []) {
    if (redirect.duplicate || !['>', '>>'].includes(redirect.op)) continue
    pushMutation(output, redirect.op === '>>' ? 'append' : 'overwrite', redirect.target)
  }

  switch (ctx.cmd) {
    case 'rm':
    case 'unlink':
      for (const target of ctx.positionals) {
        pushMutation(output, 'delete', target, { recursive: ctx.flags.has('-r') || ctx.flags.has('-R') || ctx.flags.has('--recursive') })
      }
      break

    case 'mv': {
      const targetDirectory = optionValue(ctx.args, '-t', '--target-directory')
      if (targetDirectory) {
        const normalizedDirectory = normalizeMutationPath(targetDirectory)
        const sources = ctx.positionals.filter((item) => normalizeMutationPath(item) !== normalizedDirectory)
        for (const source of sources) {
          pushMutation(output, 'move-source', source)
          pushMutation(output, 'move-target', path.posix.join(normalizedDirectory, path.posix.basename(normalizeMutationPath(source))))
        }
        break
      }
      if (ctx.positionals.length < 2) break
      const target = ctx.positionals.at(-1)
      for (const source of ctx.positionals.slice(0, -1)) {
        pushMutation(output, 'move-source', source)
        pushMutation(output, 'move-target', path.posix.join(normalizeMutationPath(target), path.posix.basename(normalizeMutationPath(source))))
      }
      pushMutation(output, 'move-target', target)
      break
    }

    case 'cp':
    case 'install':
      pushCopyTargets(output, ctx, 'overwrite')
      break

    case 'chmod':
    case 'chown':
    case 'chgrp':
      for (const target of ctx.positionals.slice(ctx.args.some((arg) => arg.startsWith('--reference')) ? 0 : 1)) {
        pushMutation(output, ctx.cmd, target)
      }
      break

    case 'truncate':
      if (ctx.positionals.length) pushMutation(output, 'truncate', ctx.positionals.at(-1))
      break

    case 'ssh-keygen': {
      const target = optionValue(ctx.args, '-f', '--filename')
      if (target) pushMutation(output, 'overwrite', target)
      break
    }

    case 'openssl': {
      const target = optionValue(ctx.args, '-out', '--out')
      if (target) pushMutation(output, 'overwrite', target)
      break
    }

    case 'tee':
      for (const target of ctx.positionals) pushMutation(output, 'overwrite', target)
      break

    case 'sed': {
      const inPlace = ctx.args.some((arg) => arg === '--in-place' || arg.startsWith('--in-place=') || /^-i/.test(arg))
      if (inPlace) {
        for (const target of ctx.positionals.slice(1)) pushMutation(output, 'overwrite', target)
      }
      break
    }

    case 'find':
      if (ctx.flags.has('-delete') || ctx.args.includes('-delete')) {
        pushMutation(output, 'bulk-delete', ctx.positionals[0])
      }
      break

    case 'dd':
      for (const arg of ctx.args) {
        const match = /^of=(.+)$/.exec(arg)
        if (match) pushMutation(output, 'overwrite', match[1])
      }
      break

    case 'shred':
      for (const target of ctx.positionals) pushMutation(output, 'overwrite', target)
      break

    default:
      break
  }

  return output
}

/**
 * @returns {{ protected: object[], sensitive: object[], unresolved: object[], catastrophic: object[] }}
 */
export function classifyFileMutations(ctx) {
  const cached = classificationCache.get(ctx)
  if (cached) return cached
  const mutations = extractFileMutations(ctx)
  const result = { protected: [], sensitive: [], unresolved: [], catastrophic: [] }

  for (const mutation of mutations) {
    if (!path.posix.isAbsolute(mutation.path)) {
      if (isSensitiveMutationPath(mutation.path)) result.sensitive.push(mutation)
      else if (mutation.path.split('/').includes('..')) result.unresolved.push(mutation)
      continue
    }
    if (isProtectedMutationPath(mutation.path)) {
      result.protected.push(mutation)
      continue
    }
    if ((mutation.action === 'bulk-delete' || mutation.action === 'move-source'
      || (mutation.action === 'delete' && mutation.recursive))
      && CRITICAL_TREE_ROOTS.has(mutation.path)) {
      result.catastrophic.push(mutation)
      continue
    }
    if (isSensitiveMutationPath(mutation.path)) result.sensitive.push(mutation)
  }

  classificationCache.set(ctx, result)
  return result
}
