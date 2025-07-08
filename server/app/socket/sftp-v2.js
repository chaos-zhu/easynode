const rawPath = require('path')
const fs = require('fs-extra')
const SFTPClient = require('ssh2-sftp-client')
const { Server } = require('socket.io')
const { sftpCacheDir } = require('../config')
const { verifyAuthSync } = require('../utils/verify-auth')
const { isAllowedIp } = require('../utils/tools')
const { HostListDB, FavoriteSftpDB } = require('../utils/db-class')
const { getConnectionOptions } = require('./terminal')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const hostListDB = new HostListDB().getInstance()
const favoriteSftpDB = new FavoriteSftpDB().getInstance()
const { Client: SSHClient } = require('ssh2')

const listenAction = (sftpClient, socket) => {
  // 下载任务管理
  const downloadTasks = new Map() // taskId -> { abortController, startTime, totalSize, downloadedSize }

  // 上传任务管理
  const uploadTasks = new Map() // taskId -> { abortController, startTime, totalSize, uploadedSize, chunks }
  const uploadCache = new Map() // taskId -> { chunks: [], totalChunks: 0 }

  socket.on('open_dir', async (path) => {
    try {
      const dirLs = await sftpClient.list(path)
      console.log('dirLs:', dirLs.length)
      socket.emit('dir_ls', dirLs, path)
    } catch (err) {
      socket.emit('not_exists_dir', err.message)
    }
  })

  // rename file / directory
  socket.on('rename', async ({ dirPath, oldName, newName }) => {
    try {
      if (!oldName || !newName || oldName === newName) throw new Error('无效文件名')
      const src = rawPath.posix.join(dirPath, oldName)
      const dest = rawPath.posix.join(dirPath, newName)
      await sftpClient.rename(src, dest)
      socket.emit('rename_success', { oldName, newName })
      // 返回最新目录列表
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      socket.emit('rename_fail', err.message)
    }
  })

  // delete file/dir
  socket.on('delete', async ({ dirPath, name, type }) => {
    try {
      const target = rawPath.posix.join(dirPath, name)
      if (type === 'd') {
        await sftpClient.rmdir(target, true)
      } else {
        await sftpClient.delete(target)
      }
      socket.emit('delete_success')
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      socket.emit('delete_fail', err.message)
    }
  })

  socket.on('delete_batch', async ({ dirPath, targets }) => {
    try {
      for (const { name, type } of targets) {
        const target = rawPath.posix.join(dirPath, name)
        if (type === 'd') {
          await sftpClient.rmdir(target, true)
        } else {
          await sftpClient.delete(target)
        }
      }
      socket.emit('delete_success')
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      socket.emit('delete_fail', err.message)
    }
  })

  // move file/dir
  socket.on('move', async ({ dirPath, destDir, name }) => {
    try {
      const src = rawPath.posix.join(dirPath, name)
      await ensureDir(destDir)
      const dest = rawPath.posix.join(destDir, name)
      await sftpClient.rename(src, dest)
      socket.emit('move_success')
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      socket.emit('move_fail', err.message)
    }
  })

  socket.on('move_batch', async ({ dirPath, destDir, targets }) => {
    try {
      await ensureDir(destDir)
      for (const { name } of targets) {
        const src = rawPath.posix.join(dirPath, name)
        const dest = rawPath.posix.join(destDir, name)
        await sftpClient.rename(src, dest)
      }
      socket.emit('move_success')
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      socket.emit('move_fail', err.message)
    }
  })

  async function ensureDir(dir) {
    const exists = await sftpClient.exists(dir)
    if (!exists) {
      await sftpClient.mkdir(dir, true)
    }
  }

  const execCommand = (cmd) => new Promise((res, rej) => {
    // 检查SSH客户端连接状态
    if (!sftpClient || !sftpClient.client) {
      return rej(new Error('SSH客户端未初始化'))
    }

    // 检查底层socket连接状态
    if (sftpClient.client._sock && sftpClient.client._sock.destroyed) {
      return rej(new Error('SSH连接已断开'))
    }

    // 检查SSH客户端状态
    if (sftpClient.client._readyTimeout === null && !sftpClient.client._authenticated) {
      return rej(new Error('SSH客户端未认证'))
    }

    try {
      sftpClient.client.exec(cmd, (err, stream) => {
        if (err) {
          consola.error('执行命令失败:', cmd, err.message)
          // 检查是否是连接相关错误
          if (err.message.includes('Not connected') || err.message.includes('Connection lost')) {
            return rej(new Error('SSH连接已断开，无法执行命令'))
          }
          return rej(err)
        }

        if (!stream) {
          return rej(new Error('无法创建命令执行流'))
        }

        let errMsg = ''
        let isResolved = false
        let timeout = null

        // 清理函数
        const cleanup = () => {
          if (timeout) {
            clearTimeout(timeout)
            timeout = null
          }
          if (stream) {
            try {
              stream.removeAllListeners()
              if (!stream.destroyed) {
                stream.destroy()
              }
            } catch (cleanupErr) {
              consola.warn('清理stream失败:', cleanupErr.message)
            }
          }
        }

        // 统一的结果处理函数
        const resolveOnce = (result, isError = false) => {
          if (isResolved) return
          isResolved = true
          cleanup()

          if (isError) {
            rej(result)
          } else {
            res(result)
          }
        }

        // 设置超时保护（60秒）
        timeout = setTimeout(() => {
          consola.warn('命令执行超时:', cmd)
          resolveOnce(new Error(`命令执行超时: ${ cmd }`), true)
        }, 60000)

        // 处理错误输出
        stream.stderr.on('data', d => {
          errMsg += d.toString()
        })

        // 处理错误事件
        stream.on('error', (streamErr) => {
          consola.error('Stream错误:', cmd, streamErr.message)
          if (streamErr.message.includes('Not connected')) {
            resolveOnce(new Error('SSH连接在命令执行过程中断开'), true)
          } else {
            resolveOnce(streamErr, true)
          }
        })

        // 处理连接断开
        stream.on('close', (code) => {
          if (errMsg) {
            consola.error('命令执行错误:', cmd, errMsg)
            resolveOnce(new Error(`命令执行失败: ${ code }: ${ errMsg }`), true)
          } else {
            consola.info('命令执行完成:', cmd)
            resolveOnce('success')
          }
        })

        // 处理命令退出
        stream.on('exit', (code) => {
          if (code === 0) {
            consola.info('命令执行成功:', cmd)
            resolveOnce() // 成功
          } else {
            const errorMessage = errMsg || `命令退出码: ${ code }`
            consola.error('命令执行失败:', cmd, errorMessage)
            resolveOnce(new Error(errorMessage), true)
          }
        })

        // 消耗 stdout 防止阻塞
        stream.on('data', () => {})
      })
    } catch (execErr) {
      consola.error('execCommand异常:', cmd, execErr.message)
      rej(execErr)
    }
  })

  // -------- copy (download then upload) --------
  socket.on('copy_server_batch', async ({ dirPath, destDir, targets }) => {
    try {
      await ensureDir(destDir)
      for (const { name } of targets) {
        const src = rawPath.posix.join(dirPath, name)
        // cp -r preserves dir/file, will overwrite if exists
        const cmd = `cp -r -- "${ src }" "${ destDir }/"`
        await execCommand(cmd)
      }

      socket.emit('copy_success')
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      consola.error('copy error:', err.message)
      socket.emit('copy_fail', err.message)
    }
  })

  // -------- create file/folder --------
  socket.on('create_item', async ({ dirPath, name, type }) => {
    try {
      if (!name || !name.trim()) {
        throw new Error('文件名不能为空')
      }

      const trimmedName = name.trim()

      // 验证文件名（不能包含路径分隔符和其他无效字符）
      const invalidChars = ['/', '\0']
      if (invalidChars.some(char => trimmedName.includes(char))) {
        throw new Error('文件名包含无效字符')
      }

      const targetPath = rawPath.posix.join(dirPath, trimmedName)

      // 检查文件/文件夹是否已存在
      const exists = await sftpClient.exists(targetPath)
      if (exists) {
        throw new Error(`${ type === 'folder' ? '文件夹' : '文件' } "${ trimmedName }" 已存在`)
      }

      if (type === 'folder') {
        consola.info(`创建文件夹: ${ targetPath }`)
        await sftpClient.mkdir(targetPath)
        socket.emit('create_success', `文件夹 "${ trimmedName }" 创建成功`)
      } else if (type === 'file') {
        consola.info(`创建文件: ${ targetPath }`)
        // 创建空文件，使用 touch 命令
        const cmd = `touch "${ targetPath }"`
        await execCommand(cmd)
        socket.emit('create_success', `文件 "${ trimmedName }" 创建成功`)
      } else {
        throw new Error('无效的创建类型')
      }

      // 返回最新目录列表
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      consola.error('create error:', err.message)
      socket.emit('create_fail', err.message)
    }
  })

  // -------- compress files --------
  socket.on('compress_files', async ({ dirPath, targets, archiveName }) => {
    try {
      if (!targets || targets.length === 0) {
        throw new Error('未选择要压缩的文件')
      }

      if (!archiveName || !archiveName.trim()) {
        throw new Error('压缩文件名不能为空')
      }

      const trimmedArchiveName = archiveName.trim()

      // 验证压缩文件名
      const invalidChars = ['/', '\0']
      if (invalidChars.some(char => trimmedArchiveName.includes(char))) {
        throw new Error('压缩文件名包含无效字符')
      }

      const archivePath = rawPath.posix.join(dirPath, trimmedArchiveName)

      // 检查压缩文件是否已存在
      const exists = await sftpClient.exists(archivePath)
      if (exists) {
        throw new Error(`文件 "${ trimmedArchiveName }" 已存在`)
      }

      // 构建要压缩的文件列表
      const fileNames = targets.map(t => `"${ t.name }"`).join(' ')

      // 使用 tar 命令压缩
      const tarCmd = `cd "${ dirPath }" && tar -czf "${ trimmedArchiveName }" ${ fileNames }`

      consola.info(`开始压缩文件: ${ targets.map(t => t.name).join(', ') } -> ${ trimmedArchiveName }`)
      await execCommand(tarCmd)
      consola.info(`压缩完成: ${ trimmedArchiveName }`)

      socket.emit('compress_success', `压缩文件 "${ trimmedArchiveName }" 创建成功`)

      // 返回最新目录列表
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      consola.error('compress error:', err.message)
      socket.emit('compress_fail', err.message)
    }
  })

  // -------- decompress file --------
  socket.on('decompress_file', async ({ dirPath, fileName, mode, folderName }) => {
    try {
      if (!fileName || !fileName.trim()) {
        throw new Error('文件名不能为空')
      }

      const trimmedFileName = fileName.trim()
      const archivePath = rawPath.posix.join(dirPath, trimmedFileName)

      // 检查压缩文件是否存在
      const exists = await sftpClient.exists(archivePath)
      if (!exists) {
        throw new Error(`文件 "${ trimmedFileName }" 不存在`)
      }

      // 检查是否为支持的压缩格式
      const isValidArchive = /(\.tar\.gz|\.tgz|\.tar|\.zip)$/i.test(trimmedFileName)
      if (!isValidArchive) {
        throw new Error('不支持的压缩格式，仅支持 .tar.gz、.tgz、.tar、.zip 格式')
      }

      // 确定解压目标目录
      let targetDir = dirPath
      let targetDirName = '当前文件夹'

      if (mode === 'folder' && folderName) {
        // 解压到同名文件夹
        targetDir = rawPath.posix.join(dirPath, folderName)
        targetDirName = `文件夹 "${ folderName }"`

        // 检查目标文件夹是否已存在
        const targetExists = await sftpClient.exists(targetDir)
        if (targetExists) {
          throw new Error(`目标文件夹 "${ folderName }" 已存在`)
        }

        // 创建目标文件夹
        await sftpClient.mkdir(targetDir)
        consola.info(`创建目标文件夹: ${ targetDir }`)
      }

      // 根据文件扩展名选择解压命令
      let decompressCmd = ''
      if (/\.tar\.gz$|\.tgz$/i.test(trimmedFileName)) {
        // tar.gz 或 tgz 格式
        if (mode === 'folder') {
          decompressCmd = `cd "${ dirPath }" && tar -xzf "${ trimmedFileName }" -C "${ folderName }"`
        } else {
          decompressCmd = `cd "${ dirPath }" && tar -xzf "${ trimmedFileName }"`
        }
      } else if (/\.tar$/i.test(trimmedFileName)) {
        // tar 格式
        if (mode === 'folder') {
          decompressCmd = `cd "${ dirPath }" && tar -xf "${ trimmedFileName }" -C "${ folderName }"`
        } else {
          decompressCmd = `cd "${ dirPath }" && tar -xf "${ trimmedFileName }"`
        }
      } else if (/\.zip$/i.test(trimmedFileName)) {
        // zip 格式
        if (mode === 'folder') {
          decompressCmd = `cd "${ dirPath }" && unzip -o "${ trimmedFileName }" -d "${ folderName }"`
        } else {
          decompressCmd = `cd "${ dirPath }" && unzip -o "${ trimmedFileName }"`
        }
      }

      consola.info(`开始解压文件: ${ trimmedFileName } -> ${ targetDirName }`)
      await execCommand(decompressCmd)
      consola.info(`解压完成: ${ trimmedFileName } -> ${ targetDirName }`)

      socket.emit('decompress_success', `文件 "${ trimmedFileName }" 解压到${ targetDirName }成功`)

      // 返回最新目录列表
      const dirLs = await sftpClient.list(dirPath)
      socket.emit('dir_ls', dirLs, dirPath)
    } catch (err) {
      consola.error('decompress error:', err.message)
      socket.emit('decompress_fail', err.message)
    }
  })

  // 下载功能
  socket.on('download_request', async ({ dirPath, targets }) => {
    let remoteTarPath = null // 跟踪远程临时文件路径
    let taskId = null // 声明在外层以便错误处理时访问
    try {
      if (!targets || targets.length === 0) {
        throw new Error('未选择要下载的文件')
      }

      taskId = Date.now() + '-' + Math.random().toString(36).slice(2)
      const taskDir = rawPath.join(sftpCacheDir, taskId)
      await fs.ensureDir(taskDir)

      const abortController = new AbortController()
      downloadTasks.set(taskId, {
        abortController,
        startTime: Date.now(),
        totalSize: 0,
        downloadedSize: 0,
        remoteTarPath: null // 跟踪远程临时文件
      })

      if (targets.length === 1) {
        // 单文件/文件夹逻辑（保持原有逻辑）
        const target = targets[0]
        socket.emit('download_started', { taskId, fileName: target.name })
        const srcPath = rawPath.posix.join(dirPath, target.name)

        if (target.type === 'd') {
          // 文件夹：先在远端打包
          const tarFileName = `${ target.name }.tar.gz`
          remoteTarPath = `/tmp/${ taskId }.tar.gz`
          const localTarPath = rawPath.join(taskDir, tarFileName)

          // 保存远程文件路径到任务中
          downloadTasks.get(taskId).remoteTarPath = remoteTarPath

          // 检查是否被取消
          if (abortController.signal.aborted) {
            await cleanupRemoteTarFile(remoteTarPath)
            throw new Error('下载已取消')
          }

          // 在远端打包
          consola.info(`开始打包文件夹: ${ srcPath }`)
          const tarCmd = `cd "${ dirPath }" && tar -czf "${ remoteTarPath }" "${ target.name }"`
          try {
            await execCommand(tarCmd)
            consola.info(`打包文件夹: ${ srcPath } 成功`)
          } catch (tarErr) {
            consola.error('打包文件夹失败:', tarErr.message)
            throw new Error(`打包文件夹失败: ${ tarErr.message }`)
          }

          // 获取打包文件大小
          const statResult = await sftpClient.stat(remoteTarPath)
          downloadTasks.get(taskId).totalSize = statResult.size

          // 下载打包文件
          await downloadFileWithProgress(sftpClient, remoteTarPath, localTarPath, taskId, downloadTasks, socket, abortController)

          // 下载完成后立即清理远端临时文件
          await cleanupRemoteTarFile(remoteTarPath)
          remoteTarPath = null // 已清理，置空

          socket.emit('download_ready', { taskId, fileName: tarFileName })
        } else {
          // 单文件：直接下载
          const localFilePath = rawPath.join(taskDir, target.name)

          // 获取文件大小
          const statResult = await sftpClient.stat(srcPath)
          downloadTasks.get(taskId).totalSize = statResult.size

          await downloadFileWithProgress(sftpClient, srcPath, localFilePath, taskId, downloadTasks, socket, abortController)

          socket.emit('download_ready', { taskId, fileName: target.name })
        }
      } else {
        // 多文件逻辑：打包所有选中的文件/文件夹
        const archiveName = `selected-files-${ Date.now() }.tar.gz`
        remoteTarPath = `/tmp/${ taskId }.tar.gz`
        const localTarPath = rawPath.join(taskDir, archiveName)

        // 保存远程文件路径到任务中
        downloadTasks.get(taskId).remoteTarPath = remoteTarPath

        socket.emit('download_started', { taskId, fileName: archiveName })

        // 检查是否被取消
        if (abortController.signal.aborted) {
          await cleanupRemoteTarFile(remoteTarPath)
          throw new Error('下载已取消')
        }

        // 构建tar命令，打包所有选中的文件/文件夹
        const fileNames = targets.map(t => `"${ t.name }"`).join(' ')
        const tarCmd = `cd "${ dirPath }" && tar -czf "${ remoteTarPath }" ${ fileNames }`

        consola.info(`开始打包多个文件: ${ targets.map(t => t.name).join(', ') }`)
        try {
          await execCommand(tarCmd)
          consola.info('打包多个文件成功')
        } catch (tarErr) {
          consola.error('打包失败:', tarErr.message)
          throw new Error(`打包失败: ${ tarErr.message }`)
        }

        // 获取打包文件大小
        const statResult = await sftpClient.stat(remoteTarPath)
        downloadTasks.get(taskId).totalSize = statResult.size

        // 下载打包文件
        await downloadFileWithProgress(sftpClient, remoteTarPath, localTarPath, taskId, downloadTasks, socket, abortController)

        // 下载完成后立即清理远端临时文件
        await cleanupRemoteTarFile(remoteTarPath)
        remoteTarPath = null // 已清理，置空

        socket.emit('download_ready', { taskId, fileName: archiveName })
      }

      downloadTasks.delete(taskId)
    } catch (err) {
      consola.error('下载失败:', err.message)
      socket.emit('download_fail', err.message)

      // 清理远程临时文件（如果还存在）
      if (remoteTarPath) {
        await cleanupRemoteTarFile(remoteTarPath)
      }

      // 清理任务（如果taskId存在）
      if (taskId) {
        downloadTasks.delete(taskId)
      }
    }
  })

  // 清理远程tar文件的辅助函数
  async function cleanupRemoteTarFile(remoteTarPath) {
    if (!remoteTarPath) return
    try {
      await execCommand(`rm -f "${ remoteTarPath }"`)
      consola.info(`已清理远程临时文件: ${ remoteTarPath }`)
    } catch (cleanupErr) {
      consola.warn('清理远程临时文件失败:', remoteTarPath, cleanupErr.message)
    }
  }

  // 取消下载
  socket.on('download_cancel', ({ taskId }) => {
    const task = downloadTasks.get(taskId)
    if (task) {
      task.abortController.abort()
      downloadTasks.delete(taskId)
      socket.emit('download_cancelled', { taskId })

      // 如果没有其他下载任务，清理缓存目录
      if (downloadTasks.size === 0) {
        cleanupCacheDir()
      }
    }
  })

  // 清理缓存目录
  const cleanupCacheDir = () => {
    try {
      fs.emptyDirSync(sftpCacheDir)
      consola.success('已清理 sftpCacheDir:', sftpCacheDir)
    } catch (err) {
      consola.warn('清理缓存目录失败:', err.message)
    }
  }

  // -------- 收藏相关功能 --------

  // 获取收藏列表
  socket.on('get_favorites', async ({ hostId }) => {
    try {
      const favorites = await favoriteSftpDB.findAsync({ hostId }, { sort: { createTime: -1 } })
      socket.emit('favorites_list', favorites)
    } catch (err) {
      consola.error('获取收藏列表失败:', err.message)
      socket.emit('favorite_error', '获取收藏列表失败')
    }
  })

  // 添加收藏
  socket.on('add_favorite', async ({ hostId, path, name, type }) => {
    try {
      if (!hostId || !path || !name || !type) {
        throw new Error('缺少必要参数')
      }

      // 检查是否已存在相同路径的收藏
      const existing = await favoriteSftpDB.findOneAsync({ hostId, path })
      if (existing) {
        socket.emit('favorite_error', '该路径已经收藏过了')
        return
      }

      // 添加新收藏
      const newFavorite = {
        hostId,
        path,
        name,
        type,
        createTime: Date.now()
      }

      await favoriteSftpDB.insertAsync(newFavorite)
      socket.emit('favorite_added', `收藏 "${ name }" 成功`)

      consola.info(`用户收藏了路径: ${ path }`)
    } catch (err) {
      consola.error('添加收藏失败:', err.message)
      socket.emit('favorite_error', err.message)
    }
  })

  // 删除收藏
  socket.on('remove_favorite', async ({ hostId, path }) => {
    try {
      if (!hostId || !path) {
        throw new Error('缺少必要参数')
      }

      const result = await favoriteSftpDB.removeAsync({ hostId, path }, {})

      if (result === 0) {
        socket.emit('favorite_error', '收藏不存在')
        return
      }

      socket.emit('favorite_removed', '取消收藏成功')
      consola.info(`用户取消收藏路径: ${ path }`)
    } catch (err) {
      consola.error('删除收藏失败:', err.message)
      socket.emit('favorite_error', err.message)
    }
  })

  // -------- 软链接解析功能 --------

  // 解析软链接的真实路径
  socket.on('resolve_symlink', async ({ symlinkPath }) => {
    try {
      // 获取软链接的真实路径
      consola.info(`解析软链接: ${ symlinkPath }`)
      const realPath = await sftpClient.realPath(symlinkPath)
      consola.info(`软链接真实路径: ${ realPath }`)

      // 检查真实路径是否存在
      const stats = await sftpClient.stat(realPath)
      const isDirectory = stats.isDirectory

      socket.emit('symlink_resolved', {
        realPath,
        isDirectory,
        symlinkPath
      })

      consola.info(`软链接解析成功: ${ symlinkPath } -> ${ realPath } (${ isDirectory ? '目录' : '文件' })`)

    } catch (err) {
      consola.error('软链接解析失败:', err.message)
      socket.emit('symlink_resolve_error', {
        error: err.message,
        symlinkPath
      })
    }
  })

  // -------- 文本文件编辑功能 --------

  // 读取文件内容
  socket.on('read_file', async ({ filePath, fileSize }) => {
    try {
      // 检查文件大小限制 (1MB)
      const maxFileSize = 1024 * 1024
      if (fileSize > maxFileSize) {
        socket.emit('file_read_error', {
          error: `文件过大（${ Math.round(fileSize / 1024 / 1024 * 100) / 100 }MB），仅支持编辑小于1MB的文件`,
          filePath
        })
        return
      }

      // 检查文件是否存在
      const exists = await sftpClient.exists(filePath)
      if (!exists) {
        socket.emit('file_read_error', {
          error: '文件不存在',
          filePath
        })
        return
      }

      // 读取文件内容
      consola.info(`开始读取文件: ${ filePath }`)
      const buffer = await sftpClient.get(filePath)
      const content = buffer.toString('utf8')

      consola.info(`文件读取成功: ${ filePath }，大小: ${ content.length } 字符`)
      socket.emit('file_content', { content, filePath })

    } catch (err) {
      consola.error('读取文件失败:', err.message)
      socket.emit('file_read_error', {
        error: err.message,
        filePath
      })
    }
  })

  // -------- 图片预览功能 --------

  // 读取图片文件内容
  socket.on('read_image', async ({ filePath, fileSize }) => {
    try {
      // 检查文件大小限制 (10MB)
      const maxFileSize = 10 * 1024 * 1024
      if (fileSize > maxFileSize) {
        socket.emit('image_read_error', {
          error: `图片过大（${ Math.round(fileSize / 1024 / 1024 * 100) / 100 }MB），仅支持预览小于10MB的图片`,
          filePath
        })
        return
      }

      // 检查文件是否存在
      const exists = await sftpClient.exists(filePath)
      if (!exists) {
        socket.emit('image_read_error', {
          error: '图片文件不存在',
          filePath
        })
        return
      }

      // 检查是否为图片文件
      const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif']
      const ext = rawPath.extname(filePath).toLowerCase().slice(1)
      if (!imageExtensions.includes(ext)) {
        socket.emit('image_read_error', {
          error: '不支持的图片格式',
          filePath
        })
        return
      }

      // 生成缓存文件名（使用时间戳避免冲突）
      const fileName = rawPath.basename(filePath)
      const timestamp = Date.now()
      const cacheFileName = `image_${ timestamp }_${ fileName }`
      const localImagePath = rawPath.join(sftpCacheDir, cacheFileName)

      consola.info(`开始下载图片到缓存: ${ filePath } -> ${ localImagePath }`)

      // 下载图片到本地缓存
      await sftpClient.fastGet(filePath, localImagePath)

      // 生成访问URL
      const imageUrl = `/sftp-cache/${ cacheFileName }`

      consola.info(`图片下载成功: ${ filePath }，缓存路径: ${ localImagePath }`)

      socket.emit('image_content', {
        imageUrl,
        filePath,
        fileName,
        fileSize
      })

    } catch (err) {
      consola.error('图片预览失败:', err.message)
      socket.emit('image_read_error', {
        error: err.message,
        filePath
      })
    }
  })

  // 保存文件内容
  socket.on('save_file', async ({ filePath, content }) => {
    try {
      // 检查内容大小限制 (1MB)
      const maxFileSize = 1024 * 1024
      const contentSize = Buffer.byteLength(content, 'utf8')
      if (contentSize > maxFileSize) {
        socket.emit('file_save_error', {
          error: `文件内容过大（${ Math.round(contentSize / 1024 / 1024 * 100) / 100 }MB），仅支持保存小于1MB的文件`,
          filePath
        })
        return
      }

      // 保存文件内容
      consola.info(`开始保存文件: ${ filePath }，大小: ${ content.length } 字符`)
      await sftpClient.put(Buffer.from(content, 'utf8'), filePath)

      consola.info(`文件保存成功: ${ filePath }`)
      socket.emit('file_saved', { filePath })

    } catch (err) {
      consola.error('保存文件失败:', err.message)
      socket.emit('file_save_error', {
        error: err.message,
        filePath
      })
    }
  })

  // -------- 上传相关功能 --------

  // 开始上传
  socket.on('upload_start', async ({ taskId, fileName, fileSize, targetPath }) => {
    try {
      if (!taskId || !fileName || !fileSize || !targetPath) {
        throw new Error('上传参数不完整')
      }

      // 创建上传任务
      const uploadTask = {
        taskId,
        fileName,
        fileSize,
        targetPath,
        uploadedSize: 0,
        chunks: [],
        totalChunks: 0,
        startTime: Date.now(),
        lastProgressTime: Date.now(),
        abortController: new AbortController()
      }

      uploadTasks.set(taskId, uploadTask)
      uploadCache.set(taskId, { chunks: [], totalChunks: 0 })

      consola.info(`开始上传任务: ${ taskId } - ${ fileName }`)
      socket.emit('upload_started', { taskId, fileName })

    } catch (err) {
      consola.error('开始上传失败:', err.message)
      socket.emit('upload_fail', { taskId, error: err.message })
    }
  })

  // 上传文件分片
  socket.on('upload_chunk', async ({ taskId, chunkIndex, chunkData, totalChunks, isLastChunk }) => {
    try {
      const task = uploadTasks.get(taskId)
      const cache = uploadCache.get(taskId)

      if (!task || !cache) {
        throw new Error('上传任务不存在')
      }

      if (task.abortController.signal.aborted) {
        throw new Error('上传已取消')
      }

      // 存储分片数据
      cache.chunks[chunkIndex] = chunkData
      cache.totalChunks = totalChunks

      // 更新上传进度
      const uploadedChunks = cache.chunks.filter(chunk => chunk !== undefined).length
      task.uploadedSize = (uploadedChunks / totalChunks) * task.fileSize

      // 计算速度和ETA
      const now = Date.now()
      const elapsed = (now - task.lastProgressTime) / 1000
      if (elapsed >= 1) { // 每秒更新一次进度
        const chunkProgress = Math.min((uploadedChunks / totalChunks) * 100, 100)
        const totalElapsed = (now - task.startTime) / 1000
        const speed = totalElapsed > 0 ? task.uploadedSize / totalElapsed : 0
        const eta = speed > 0 ? (task.fileSize - task.uploadedSize) / speed : 0

        socket.emit('upload_progress', {
          taskId,
          chunkProgress,
          chunkUploadedSize: task.uploadedSize,
          chunkTotalSize: task.fileSize,
          sftpProgress: 0,
          sftpUploadedSize: 0,
          sftpTotalSize: task.fileSize,
          speed: Math.round(speed),
          eta: Math.round(eta),
          stage: 'uploading'
        })

        task.lastProgressTime = now
      }

      consola.info(`上传分片: ${ taskId } - ${ chunkIndex + 1 }/${ totalChunks }`)
      socket.emit('upload_chunk_success', { taskId, chunkIndex })

      // 如果是最后一个分片，开始合并和传输
      if (isLastChunk && uploadedChunks === totalChunks) {
        await completeUpload(task, cache)
      }

    } catch (err) {
      consola.error('上传分片失败:', err.message)
      socket.emit('upload_chunk_fail', { taskId, chunkIndex, error: err.message })
    }
  })

  // 完成上传的辅助函数
  async function completeUpload(task, cache) {
    let tempFilePath = null

    try {
      consola.info(`开始合并文件: ${ task.fileName }`)

      // 发送合并开始事件
      socket.emit('upload_progress', {
        taskId: task.taskId,
        chunkProgress: 100,
        chunkUploadedSize: task.fileSize,
        chunkTotalSize: task.fileSize,
        sftpProgress: 0,
        sftpUploadedSize: 0,
        sftpTotalSize: task.fileSize,
        speed: 0,
        eta: 0,
        stage: 'merging'
      })

      // 创建临时文件用于SFTP传输
      tempFilePath = rawPath.join(sftpCacheDir, `temp_${ task.taskId }_${ task.fileName }`)
      const writeStream = fs.createWriteStream(tempFilePath)

      // 流式合并分片，避免大文件占用过多内存
      try {
        for (let i = 0; i < cache.totalChunks; i++) {
          if (!cache.chunks[i]) {
            throw new Error(`分片 ${ i } 缺失`)
          }

          const chunkBuffer = Buffer.from(cache.chunks[i])
          await new Promise((resolve, reject) => {
            writeStream.write(chunkBuffer, (err) => {
              if (err) reject(err)
              else resolve()
            })
          })

          // 立即释放已写入的分片内存
          cache.chunks[i] = null
        }

        await new Promise((resolve, reject) => {
          writeStream.end((err) => {
            if (err) reject(err)
            else resolve()
          })
        })
      } catch (mergeErr) {
        writeStream.destroy()
        throw mergeErr
      }

      // 验证文件大小
      const stats = fs.statSync(tempFilePath)
      if (stats.size !== task.fileSize) {
        throw new Error(`文件大小不匹配: 期望 ${ task.fileSize }, 实际 ${ stats.size }`)
      }

      // 发送SFTP传输开始事件
      socket.emit('upload_progress', {
        taskId: task.taskId,
        chunkProgress: 100,
        chunkUploadedSize: task.fileSize,
        chunkTotalSize: task.fileSize,
        sftpProgress: 0,
        sftpUploadedSize: 0,
        sftpTotalSize: task.fileSize,
        speed: 0,
        eta: 0,
        stage: 'transferring'
      })

      // 通过SFTP传输到远程服务器，使用fastPut带进度回调
      consola.info(`开始传输文件到远程服务器: ${ task.targetPath }`)

      let sftpStartTime = Date.now()
      let lastSftpUpdateTime = sftpStartTime
      let lastSftpUploadedSize = 0

      await sftpClient.fastPut(tempFilePath, task.targetPath, {
        step: (transferredBytes) => {
          const now = Date.now()
          const sftpProgress = Math.min((transferredBytes / task.fileSize) * 100, 100)

          // 计算SFTP传输速度和ETA（每500ms更新一次）
          if (now - lastSftpUpdateTime >= 500) {
            const elapsed = (now - lastSftpUpdateTime) / 1000
            const sizeDiff = transferredBytes - lastSftpUploadedSize
            const sftpSpeed = elapsed > 0 ? sizeDiff / elapsed : 0
            const remainingBytes = task.fileSize - transferredBytes
            const sftpEta = sftpSpeed > 0 ? remainingBytes / sftpSpeed : 0

            socket.emit('upload_progress', {
              taskId: task.taskId,
              chunkProgress: 100,
              chunkUploadedSize: task.fileSize,
              chunkTotalSize: task.fileSize,
              sftpProgress,
              sftpUploadedSize: transferredBytes,
              sftpTotalSize: task.fileSize,
              speed: Math.round(sftpSpeed),
              eta: Math.round(sftpEta),
              stage: 'transferring'
            })

            lastSftpUpdateTime = now
            lastSftpUploadedSize = transferredBytes
          }
        }
      })

      // 传输完成
      consola.info(`文件上传成功: ${ task.fileName }`)
      socket.emit('upload_complete', {
        taskId: task.taskId,
        fileName: task.fileName,
        targetPath: task.targetPath
      })

    } catch (err) {
      consola.error('完成上传失败:', err.message)
      socket.emit('upload_fail', {
        taskId: task.taskId,
        error: err.message
      })
    } finally {
      // 确保清理临时文件
      if (tempFilePath) {
        try {
          fs.unlinkSync(tempFilePath)
        } catch (cleanupErr) {
          consola.warn('清理临时文件失败:', cleanupErr.message)
        }
      }

      // 清理任务和缓存
      uploadTasks.delete(task.taskId)
      uploadCache.delete(task.taskId)
    }
  }

  // 取消上传
  socket.on('upload_cancel', ({ taskId }) => {
    const task = uploadTasks.get(taskId)
    if (task) {
      task.abortController.abort()
      uploadTasks.delete(taskId)
      uploadCache.delete(taskId)

      consola.info(`取消上传任务: ${ taskId }`)
      socket.emit('upload_cancelled', { taskId })
    }
  })

  // 监听连接断开，清理下载任务和缓存
  socket.on('disconnect', async (reason) => {
    try {
      consola.info('SFTP连接断开，开始清理资源...', reason)

      // 清理定时器
      if (memoryCleanupInterval) {
        clearInterval(memoryCleanupInterval)
      }

      // 清理所有远程临时文件
      const remoteCleanupPromises = []
      for (const [taskId, task] of downloadTasks) {
        try {
          // 取消下载任务
          if (task.abortController) {
            task.abortController.abort()
          }

          // 如果有远程临时文件，添加到清理列表
          if (task.remoteTarPath) {
            remoteCleanupPromises.push(cleanupRemoteTarFile(task.remoteTarPath))
          }
        } catch (taskError) {
          consola.warn(`清理下载任务 ${ taskId } 失败:`, taskError.message)
        }
      }

      // 并行清理所有远程临时文件
      if (remoteCleanupPromises.length > 0) {
        try {
          await Promise.all(remoteCleanupPromises)
          consola.info(`连接断开时已清理 ${ remoteCleanupPromises.length } 个远程临时文件`)
        } catch (err) {
          consola.warn('连接断开时清理远程临时文件部分失败:', err.message)
        }
      }

      // 清理上传任务和相关资源
      for (const [taskId, task] of uploadTasks) {
        try {
          if (task.abortController) {
            task.abortController.abort()
          }
        } catch (taskError) {
          consola.warn(`清理上传任务 ${ taskId } 失败:`, taskError.message)
        }
      }

      // 清理上传缓存中的大文件数据
      for (const [taskId, cache] of uploadCache) {
        try {
          if (cache.chunks) {
            // 释放分片内存
            cache.chunks.length = 0
          }
        } catch (cacheError) {
          consola.warn(`清理上传缓存 ${ taskId } 失败:`, cacheError.message)
        }
      }

      // 清理所有任务映射
      downloadTasks.clear()
      uploadTasks.clear()
      uploadCache.clear()

      // 清理本地缓存目录
      try {
        cleanupCacheDir()
      } catch (cleanupError) {
        consola.warn('清理本地缓存目录失败:', cleanupError.message)
      }

      consola.info('SFTP资源清理完成')
    } catch (disconnectError) {
      consola.error('Socket断开连接清理过程中发生错误:', disconnectError.message)
    }
  })

  // 定期内存清理（可选优化）
  const memoryCleanupInterval = setInterval(() => {
    // 检查并清理超时的上传任务（超过1小时）
    const now = Date.now()
    const timeout = 2 * 60 * 60 * 1000 // 2小时

    for (const [taskId, task] of uploadTasks) {
      if (now - task.startTime > timeout) {
        consola.warn(`清理超时上传任务: ${ taskId }`)
        if (task.abortController) {
          task.abortController.abort()
        }
        uploadTasks.delete(taskId)
        uploadCache.delete(taskId)
      }
    }

    // 检查并清理超时的下载任务
    for (const [taskId, task] of downloadTasks) {
      if (now - task.startTime > timeout) {
        consola.warn(`清理超时下载任务: ${ taskId }`)
        if (task.abortController) {
          task.abortController.abort()
        }
        downloadTasks.delete(taskId)
      }
    }
  }, 5 * 60 * 1000) // 每5分钟检查一次

  // 带进度的文件下载函数
  async function downloadFileWithProgress(sftpClient, remotePath, localPath, taskId, downloadTasks, socket, abortController) {
    return new Promise((resolve, reject) => {
      const task = downloadTasks.get(taskId)
      if (!task) {
        return reject(new Error('任务不存在'))
      }

      let lastUpdateTime = Date.now()
      let lastDownloadedSize = 0
      let progressInterval = null
      let readStream = null
      let writeStream = null

      // 清理函数
      const cleanup = () => {
        if (progressInterval) {
          clearInterval(progressInterval)
          progressInterval = null
        }
        if (readStream) {
          readStream.destroy()
          readStream = null
        }
        if (writeStream) {
          writeStream.destroy()
          writeStream = null
        }
      }

      // 错误处理函数
      const handleError = (err) => {
        cleanup()
        fs.unlink(localPath).catch(() => {})
        reject(err)
      }

      progressInterval = setInterval(() => {
        if (abortController.signal.aborted) {
          cleanup()
          reject(new Error('下载已取消'))
          return
        }

        const now = Date.now()
        const currentTask = downloadTasks.get(taskId)
        if (!currentTask) {
          cleanup()
          reject(new Error('任务已被删除'))
          return
        }

        const { totalSize, downloadedSize } = currentTask // , startTime
        // const elapsed = (now - startTime) / 1000 // 秒
        const progress = totalSize > 0 ? (downloadedSize / totalSize * 100) : 0

        // 计算速度 (bytes/s)
        const timeDiff = (now - lastUpdateTime) / 1000
        const sizeDiff = downloadedSize - lastDownloadedSize
        const speed = timeDiff > 0 ? sizeDiff / timeDiff : 0

        // 计算剩余时间
        const remainingBytes = totalSize - downloadedSize
        const eta = speed > 0 ? remainingBytes / speed : 0

        socket.emit('download_progress', {
          taskId,
          progress: Math.min(progress, 100),
          downloadedSize,
          totalSize,
          speed: Math.round(speed),
          eta: Math.round(eta)
        })

        lastUpdateTime = now
        lastDownloadedSize = downloadedSize
      }, 1000) // 每1秒更新

      try {
        readStream = sftpClient.createReadStream(remotePath)
        writeStream = fs.createWriteStream(localPath)

        readStream.on('data', (chunk) => {
          if (abortController.signal.aborted) {
            cleanup()
            fs.unlink(localPath).catch(() => {}) // 删除部分下载的文件
            reject(new Error('下载已取消'))
            return
          }

          const currentTask = downloadTasks.get(taskId)
          if (currentTask) {
            currentTask.downloadedSize += chunk.length
          }
        })

        readStream.on('error', handleError)
        writeStream.on('error', handleError)

        writeStream.on('finish', () => {
          cleanup()
          resolve()
        })

        readStream.pipe(writeStream)
      } catch (err) {
        handleError(err)
      }
    })
  }
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/sftp-v2',
    cors: {
      origin: '*'
    }
  })
  serverIo.on('connection', (socket) => {
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    let sftpClient = new SFTPClient()
    consola.success('sftp-v2 websocket 已连接')
    let jumpSshClients = []

    // 添加socket本身的错误处理
    socket.on('error', (err) => {
      consola.error('SFTP-v2 Socket连接错误:', err.message)
    })

    socket.on('ws_sftp', async ({ hostId, token }) => {
      try {
        const { code } = await verifyAuthSync(token, requestIP)
        if (code !== 1) {
          socket.emit('token_verify_fail')
          socket.disconnect()
          return
        }
        const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
        if (!targetHostInfo) throw new Error(`Host with ID ${ hostId } not found`)

        let { connectByJumpHosts = null } = (await decryptAndExecuteAsync(rawPath.join(__dirname, 'plus.js'))) || {}
        let { authType, host, port, username, jumpHosts } = targetHostInfo

        let { authInfo: targetConnectionOptions } = await getConnectionOptions(hostId)
        let jumpHostResult = connectByJumpHosts && (await connectByJumpHosts(jumpHosts, targetConnectionOptions.host, targetConnectionOptions.port, socket))
        if (jumpHostResult) {
          targetConnectionOptions.sock = jumpHostResult.sock
          jumpSshClients = jumpHostResult.sshClients
          consola.success('sftp-v2 跳板机连接成功')
        }

        consola.info('准备连接sftp-v2 面板：', host)
        consola.log('连接信息', { username, port, authType })

        sftpClient.client = new SSHClient()

        // 添加错误处理器，防止程序崩溃
        sftpClient.client.on('error', (err) => {
          consola.error('SFTP SSH连接错误:', err.message)
          try {
          // 发送SSH连接错误事件
            socket.emit('shell_connection_error', {
              message: `SSH连接错误: ${ err.message }`,
              code: err.code || 'UNKNOWN'
            })
          } catch (emitError) {
            consola.error('发送错误事件失败:', emitError.message)
          }
        })

        sftpClient.client.on('end', () => {
          consola.info('SSH连接正常结束')
        })

        sftpClient.client.on('close', (hadError) => {
          if (hadError) {
            consola.warn('SSH连接异常关闭')
            try {
              socket.emit('shell_connection_error', {
                message: 'SSH连接异常关闭',
                code: 'CONNECTION_CLOSED'
              })
            } catch (emitError) {
              consola.error('发送连接关闭事件失败:', emitError.message)
            }
          } else {
            consola.info('SSH连接已关闭')
          }
        })

        // 添加未处理异常捕获
        sftpClient.client.on('timeout', () => {
          consola.warn('SSH连接超时')
          try {
            socket.emit('shell_connection_error', {
              message: 'SSH连接超时',
              code: 'CONNECTION_TIMEOUT'
            })
          } catch (emitError) {
            consola.error('发送超时事件失败:', emitError.message)
          }
        })

        sftpClient.client.on('keyboard-interactive', function (name, instructions, instructionsLang, prompts, finish) {
          finish([targetConnectionOptions[authType]])
        })

        try {
          await sftpClient.connect({
            tryKeyboard: true,
            ...targetConnectionOptions
          })
          fs.ensureDirSync(sftpCacheDir)
          let rootList = []
          let isRootUser = true
          let currentWorkingDir = '/'

          try {
            rootList = await sftpClient.list('/')
            consola.success('获取根目录成功')
          } catch (error) {
            consola.error('获取根目录失败:', error.message)
            consola.info('尝试获取当前目录')
            isRootUser = false

            try {
            // 获取当前工作目录的绝对路径
              currentWorkingDir = await sftpClient.cwd()
              consola.info('当前工作目录:', currentWorkingDir)
              rootList = await sftpClient.list(currentWorkingDir)
              consola.success('获取当前目录成功')
            } catch (cwdError) {
              consola.warn('获取工作目录失败，使用相对路径:', cwdError.message)
              currentWorkingDir = '~'
              rootList = await sftpClient.list('./')
              consola.success('获取当前目录成功')
            }
          }

          // 普通文件-、目录文件d、链接文件l
          socket.emit('connect_success', {
            rootList,
            isRootUser,
            currentPath: currentWorkingDir
          })
          consola.success('连接sftp-v2 成功：', host)
          listenAction(sftpClient, socket)
        } catch (error) {
          consola.error('连接sftp-v2 失败：', error.message)

          // 发送详细的错误信息给前端
          let errorMessage = error.message
          if (error.code) {
            errorMessage += ` (错误代码: ${ error.code })`
          }
          if (error.errno) {
            errorMessage += ` (错误号: ${ error.errno })`
          }

          socket.emit('connect_fail', errorMessage)

          // 清理资源
          try {
            if (sftpClient && sftpClient.sftp) {
              await sftpClient.end()
            }
          } catch (cleanupError) {
            consola.warn('清理SFTP客户端资源失败:', cleanupError.message)
          }

          // 清理跳板机连接
          if (jumpSshClients && jumpSshClients.length > 0) {
            jumpSshClients.forEach((client, index) => {
              try {
                client.end()
                consola.info(`已清理跳板机连接 ${ index + 1 }`)
              } catch (cleanupError) {
                consola.warn(`清理跳板机连接 ${ index + 1 } 失败:`, cleanupError.message)
              }
            })
          }

          socket.disconnect()
        }
      } catch (globalError) {
        consola.error('SFTP连接处理过程中发生未预期错误:', globalError.message)
        try {
          socket.emit('connect_fail', `连接失败: ${ globalError.message }`)
          socket.disconnect()
        } catch (cleanupError) {
          consola.error('清理失败连接时发生错误:', cleanupError.message)
        }
      }
    })

    socket.on('disconnect', async () => {
      try {
        await sftpClient.end()
        consola.info('sftp-v2 连接断开')
      } catch (error) {
        consola.info('sftp断开连接失败:', error.message)
      } finally {
        sftpClient = null
        // 这里不再清理缓存目录，因为在 listenAction 中的 disconnect 处理器会处理
        jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
        jumpSshClients = null
      }
    })
  })
}
