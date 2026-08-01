/** 敏感读取分类。审批后内容可以原样发送给当前 AI Provider。 */

import path from 'node:path'
import { Risk } from './policy.js'

export const DataRisk = {
  NORMAL: Risk.NORMAL,
  HIGH: Risk.HIGH
}

const CORE_CREDENTIAL_PATHS = [
  /^\/etc\/(?:shadow|gshadow)(?:-|$)/,
  /(?:^|\/)\.ssh\/id_(?![^/]+\.pub$)[^/]+$/i,
  /(?:^|\/)(?:private[_-]?key|client[_-]?key)(?:\.[^/]*)?$/i,
  /(?:^|\/)\.aws\/credentials$/i,
  /(?:^|\/)\.config\/gcloud\/application_default_credentials\.json$/i,
  /(?:^|\/)\.docker\/config\.json$/i
]

const SENSITIVE_PATHS = [
  /(?:^|\/)\.env(?:\.[^/]*)?$/i,
  /(?:^|\/)\.(?:pgpass|my\.cnf|netrc)$/i,
  /(?:^|\/)(?:authorized_keys|known_hosts)$/i,
  /(?:^|\/)(?:credentials?|secrets?|tokens?)(?:\.[^/]*)?$/i,
  /(?:^|\/)(?:kubeconfig|config\.json)$/i,
  /(?:^|\/)\.(?:bash|zsh|fish)_history$/i,
  /\.(?:pem|key|p12|pfx)$/i
]

function normalizeRemotePath(value) {
  const raw = String(value || '').trim().replace(/\\/g, '/')
  if (!raw) return ''
  if (raw === '~') return '~'
  if (raw.startsWith('~/')) return `~/${ path.posix.normalize(raw.slice(2)) }`
  return path.posix.normalize(raw)
}

function matches(pathname, patterns) {
  return patterns.some((pattern) => pattern.test(pathname))
}

export function classifyReadPath(value) {
  const normalized = normalizeRemotePath(value)
  if (!normalized) {
    return {
      risk: DataRisk.HIGH,
      path: normalized,
      core: false,
      category: '敏感读取',
      reason: '目标路径为空或无法识别，不能确认将读取什么内容'
    }
  }

  if (matches(normalized, CORE_CREDENTIAL_PATHS)) {
    return {
      risk: DataRisk.HIGH,
      path: normalized,
      core: true,
      category: '核心凭据读取',
      reason: '读取后真实凭据内容将发送给当前 AI Provider'
    }
  }

  if (matches(normalized, SENSITIVE_PATHS)) {
    return {
      risk: DataRisk.HIGH,
      path: normalized,
      core: false,
      category: '敏感读取',
      reason: '读取后真实敏感内容将发送给当前 AI Provider'
    }
  }

  return { risk: DataRisk.NORMAL, path: normalized, core: false }
}

export function isCoreCredentialPath(value) {
  return classifyReadPath(value).core === true
}

export function isSensitiveDataPath(value) {
  return classifyReadPath(value).risk === DataRisk.HIGH
}

export function containsCoreCredentialPath(value) {
  const text = String(value || '')
  const candidates = [
    text,
    ...(text.match(/\/[A-Za-z0-9_.~+@%:,=-]+(?:\/[A-Za-z0-9_.~+@%:,=-]+)*/g) || [])
  ]
  return candidates.some((item) => isCoreCredentialPath(item.replace(/[,:=@]+$/, '')))
}

export function stricterDataRisk(...results) {
  const values = results.filter(Boolean)
  return values.find((item) => item.risk === DataRisk.HIGH) || values[0] || null
}
