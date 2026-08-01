/**
 * write_file 的不可覆盖备份。
 *
 * 路径先带 UTC 时间戳；同一毫秒或并发写入发生碰撞时追加序号。真正创建
 * 文件时使用 SFTP 的 wx（create + exclusive），不能只依赖 stat 后再写。
 */

const MAX_BACKUP_ATTEMPTS = 1000

export function formatBackupTimestamp(value = Date.now()) {
  return new Date(value).toISOString().replace(/[-:.]/g, '')
}

export function backupPathForAttempt(sourcePath, timestamp, attempt = 0) {
  const base = `${ sourcePath }.bak.${ timestamp }`
  return attempt ? `${ base }.${ attempt }` : base
}

function pathExists(sftp, pathname) {
  return new Promise((resolve) => {
    sftp.stat(pathname, (error) => resolve(!error))
  })
}

/** 流式复制且独占创建目标，避免并发备份互相覆盖。 */
function copyFileExclusive(sftp, from, to) {
  return new Promise((resolve, reject) => {
    const source = sftp.createReadStream(from)
    const target = sftp.createWriteStream(to, { flags: 'wx' })
    let targetOpened = false
    let settled = false

    const fail = (error, origin) => {
      if (settled) return
      settled = true
      source.destroy()
      target.destroy()
      error.backupOrigin = origin
      error.backupTargetOpened = targetOpened
      reject(error)
    }

    target.once('open', () => {
      targetOpened = true
    })
    source.on('error', (error) => fail(error, 'source'))
    target.on('error', (error) => fail(error, 'target'))
    target.on('close', () => {
      if (settled) return
      settled = true
      resolve()
    })
    source.pipe(target)
  })
}

export async function createUniqueBackup(sftp, sourcePath, options = {}) {
  const timestamp = formatBackupTimestamp(options.now?.() ?? Date.now())
  const exists = options.pathExists || pathExists
  const copy = options.copy || copyFileExclusive

  for (let attempt = 0; attempt < MAX_BACKUP_ATTEMPTS; attempt += 1) {
    const candidate = backupPathForAttempt(sourcePath, timestamp, attempt)
    if (await exists(sftp, candidate)) continue

    try {
      await copy(sftp, sourcePath, candidate)
      return candidate
    } catch (error) {
      // wx 在打开前失败且目标已经出现，说明另一个写入抢先创建了同名
      // 备份；换下一个序号即可。源读取失败或已开始写入后的错误必须上抛。
      const collided = error.backupOrigin === 'target'
        && error.backupTargetOpened === false
        && await exists(sftp, candidate)
      if (collided) continue
      throw error
    }
  }

  throw new Error('无法分配唯一的备份文件名，请清理过多的同时间戳备份后重试')
}
