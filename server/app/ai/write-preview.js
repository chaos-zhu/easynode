/**
 * write_file 审批快照
 *
 * 用户批准的必须是“将要落盘的那一份内容”。审批前读取当前文件并生成
 * 完整替换 diff，同时把旧文件状态与新内容一起做哈希；执行前重新生成
 * 快照，任何 TOCTOU 变化都会让原审批失效。
 */

import path from 'node:path'
import { createHash } from 'node:crypto'
import { withSftp } from './ssh.js'

export const MAX_WRITE_FILE_BYTES = 256 * 1024

function sftpStat(sftp, pathname) {
  return new Promise((resolve, reject) => {
    sftp.stat(pathname, (error, stats) => (error ? reject(error) : resolve(stats)))
  })
}

function sftpRealpath(sftp, pathname) {
  return new Promise((resolve) => {
    sftp.realpath(pathname, (error, resolved) => resolve(error ? pathname : resolved))
  })
}

function readStream(sftp, pathname) {
  return new Promise((resolve, reject) => {
    const chunks = []
    const stream = sftp.createReadStream(pathname)
    stream.on('data', (chunk) => chunks.push(chunk))
    stream.on('error', reject)
    stream.on('end', () => resolve(Buffer.concat(chunks)))
  })
}

function hash(value) {
  return createHash('sha256').update(value).digest('hex')
}

function lineCount(content) {
  if (!content) return 0
  return content.endsWith('\n') ? content.split('\n').length - 1 : content.split('\n').length
}

function prefixLines(content, prefix) {
  if (!content) return []
  const trailingNewline = content.endsWith('\n')
  const lines = content.split('\n')
  if (trailingNewline) lines.pop()
  const output = lines.map((line) => `${ prefix }${ line }`)
  if (!trailingNewline) output.push('\\ No newline at end of file')
  return output
}

/**
 * 使用“完整替换”形式而非最小 diff：审批界面必须让用户看到全部旧内容和
 * 全部新内容，不能因为 diff 算法省略上下文而隐藏模型将写入的行。
 */
export function buildFullReplacementDiff(pathname, oldContent, newContent, created) {
  const oldLabel = created ? '/dev/null' : `${ pathname } (current)`
  return [
    `--- ${ oldLabel }`,
    `+++ ${ pathname } (proposed)`,
    `@@ -1,${ lineCount(oldContent) } +1,${ lineCount(newContent) } @@`,
    ...prefixLines(oldContent, '-'),
    ...prefixLines(newContent, '+')
  ].join('\n')
}

export function validateWriteFileInput(input = {}) {
  const pathname = String(input.path || '')
  if (!path.posix.isAbsolute(pathname)) {
    throw new Error('write_file 只允许绝对路径，以便准确展示和审批目标文件')
  }
  const bytes = Buffer.byteLength(String(input.content ?? ''), 'utf8')
  if (bytes > MAX_WRITE_FILE_BYTES) {
    throw new Error(`写入内容超过安全预览上限 ${ MAX_WRITE_FILE_BYTES } 字节，请改用人工上传或受审脚本`)
  }
  if (String(input.content ?? '').includes('\0')) {
    throw new Error('write_file 只支持可完整预览的文本文件，不允许写入二进制内容')
  }
  if (input.mode !== undefined && !/^[0-7]{3,4}$/.test(String(input.mode))) {
    throw new Error('文件权限必须是 3 或 4 位八进制数字，例如 644 或 0755')
  }
  return { pathname, bytes }
}

export async function buildWriteFilePreviewWithSftp(sftp, hostId, input = {}) {
  const { pathname, bytes: newBytes } = validateWriteFileInput(input)

  let stats = null
  try {
    stats = await sftpStat(sftp, pathname)
  } catch {
    // 不存在即新建
  }

  if (stats?.isDirectory()) throw new Error(`${ pathname } 是目录，无法写入`)
  if (stats?.size > MAX_WRITE_FILE_BYTES) {
    throw new Error(`原文件超过安全预览上限 ${ MAX_WRITE_FILE_BYTES } 字节，不能在未完整展示差异时覆盖`)
  }

  const realPath = await sftpRealpath(sftp, pathname)
  const oldBuffer = stats ? await readStream(sftp, pathname) : Buffer.alloc(0)
  if (oldBuffer.length > MAX_WRITE_FILE_BYTES) {
    throw new Error(`原文件超过安全预览上限 ${ MAX_WRITE_FILE_BYTES } 字节，不能在未完整展示差异时覆盖`)
  }

  let oldContent
  try {
    oldContent = new TextDecoder('utf-8', { fatal: true }).decode(oldBuffer)
  } catch {
    throw new Error('原文件不是有效的 UTF-8 文本，无法生成可信的完整差异')
  }
  if (oldContent.includes('\0')) throw new Error('原文件包含二进制内容，无法生成可信的完整差异')

  const newContent = String(input.content ?? '')
  const created = !stats
  const oldMode = stats ? (stats.mode & 0o7777).toString(8).padStart(3, '0') : null
  const newMode = input.mode ? String(input.mode) : oldMode
  const oldHash = hash(oldBuffer)
  const contentHash = hash(Buffer.from(newContent))
  const snapshotHash = hash(JSON.stringify({
    hostId,
    pathname,
    realPath,
    created,
    oldHash,
    oldMode,
    newMode,
    backup: input.backup !== false,
    contentHash
  }))

  return {
    type: 'write_file',
    path: pathname,
    realPath,
    operation: created ? 'create' : 'overwrite',
    backup: input.backup !== false,
    oldMode,
    newMode,
    oldBytes: oldBuffer.length,
    newBytes,
    oldHash,
    contentHash,
    snapshotHash,
    diff: buildFullReplacementDiff(pathname, oldContent, newContent, created)
  }
}

export function buildWriteFilePreview(hostId, input = {}) {
  return withSftp(hostId, (sftp) => buildWriteFilePreviewWithSftp(sftp, hostId, input))
}
