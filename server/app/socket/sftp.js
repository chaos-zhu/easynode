const rawPath = require('path')
const fs = require('fs-extra')
const SFTPClient = require('ssh2-sftp-client')
const CryptoJS = require('crypto-js')
const { Server } = require('socket.io')
const { sftpCacheDir } = require('../config')
const { verifyAuthSync } = require('../utils/verify-auth')
const { AESDecryptAsync } = require('../utils/encrypt')
const { isAllowedIp } = require('../utils/tools')
const { HostListDB, CredentialsDB } = require('../utils/db-class')
const hostListDB = new HostListDB().getInstance()
const credentialsDB = new CredentialsDB().getInstance()

// 读取切片
const pipeStream = (path, writeStream) => {
  return new Promise(resolve => {
    const readStream = fs.createReadStream(path)
    readStream.on('end', () => {
      fs.unlinkSync(path) // 删除已写入切片
      resolve()
    })
    readStream.pipe(writeStream)
  })
}

function listenInput(sftpClient, socket) {
  socket.on('open_dir', async (path, tips = true) => {
    const exists = await sftpClient.exists(path)
    if (!exists) return socket.emit('not_exists_dir', tips ? '目录不存在或当前不可访问' : '')
    try {
      let dirLs = await sftpClient.list(path)
      socket.emit('dir_ls', dirLs, path)
    } catch (error) {
      consola.error('open_dir Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })
  socket.on('rm_dir', async (path) => {
    const exists = await sftpClient.exists(path)
    if (!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
    consola.info('rm_dir: ', path)
    try {
      let res = await sftpClient.rmdir(path, true) // 递归删除
      socket.emit('rm_success', res)
    } catch (error) {
      consola.error('rm_dir Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })
  socket.on('rm_file', async (path) => {
    const exists = await sftpClient.exists(path)
    if (!exists) return socket.emit('not_exists_dir', '文件不存在或当前不可访问')
    try {
      let res = await sftpClient.delete(path)
      socket.emit('rm_success', res)
    } catch (error) {
      consola.error('rm_file Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })
  // socket.on('down_dir', async (path) => {
  //   const exists = await sftpClient.exists(path)
  //   if(!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
  //   let res = await sftpClient.downloadDir(path, sftpCacheDir)
  //   socket.emit('down_dir_success', res)
  // })

  // 下载
  socket.on('down_file', async ({ path, name, size, target = 'down' }) => {
    // target: down or preview
    const exists = await sftpClient.exists(path)
    if (!exists) return socket.emit('not_exists_dir', '文件不存在或当前不可访问')
    try {
      const localPath = rawPath.join(sftpCacheDir, name)
      let timer = null
      let res = await sftpClient.fastGet(path, localPath, {
        step: step => {
          if (timer) return
          timer = setTimeout(() => {
            const percent = Math.ceil((step / size) * 100) // 下载进度为服务器下载到服务端的进度，前端无需*2
            console.log(`从服务器下载进度：${ percent }%`)
            socket.emit('down_file_progress', percent)
            timer = null
          }, 1500)
        }
      })
      consola.success('sftp下载成功: ', res)
      let buffer = fs.readFileSync(localPath)
      let data = { buffer, name }
      switch (target) {
        case 'down':
          socket.emit('down_file_success', data)
          break
        case 'preview':
          socket.emit('preview_file_success', data)
          break
      }
      fs.unlinkSync(localPath) //删除文件
    } catch (error) {
      consola.error('down_file Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })

  // 上传
  socket.on('up_file', async ({ targetPath, fullPath, name, file }) => {
    // console.log({ targetPath, fullPath, name, file })
    const exists = await sftpClient.exists(targetPath)
    if (!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
    try {
      const localPath = rawPath.join(sftpCacheDir, name)
      fs.writeFileSync(localPath, file)
      let res = await sftpClient.fastPut(localPath, fullPath)
      consola.success('sftp上传成功: ', res)
      socket.emit('up_file_success', res)
    } catch (error) {
      consola.error('up_file Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })

  // 上传目录先在目标sftp服务器创建目录
  socket.on('create_remote_dir', async ({ targetDirPath, foldersName }) => {
    let baseFolderPath = rawPath.posix.join(targetDirPath, foldersName[0].split('/')[0])
    let baseFolderPathExists = await sftpClient.exists(baseFolderPath)
    if (baseFolderPathExists) return socket.emit('create_remote_dir_exists', `远程目录已存在: ${ baseFolderPath }`)
    consola.info('准备创建远程服务器目录:', foldersName)
    for (const folderName of foldersName) {
      const fullPath = rawPath.posix.join(targetDirPath, folderName)
      const exists = await sftpClient.exists(fullPath)
      if (exists) continue
      await sftpClient.mkdir(fullPath, true)
      socket.emit('create_remote_dir_progress', fullPath)
      consola.info('创建目录:', fullPath)
    }
    socket.emit('create_remote_dir_success')
  })

  /** 分片上传 */
  // 1. 创建本地缓存目录
  let md5List = []
  socket.on('create_cache_dir', async ({ targetDirPath, name }) => {
    // console.log({ targetDirPath, name })
    const exists = await sftpClient.exists(targetDirPath)
    if (!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
    md5List = []
    const localPath = rawPath.join(sftpCacheDir, name)
    fs.emptyDirSync(localPath) // 不存在会创建，存在则清空
    socket.emit('create_cache_success')
  })
  // 2. 上传分片到面板服务
  socket.on('up_file_slice', async ({ name, sliceFile, fileIndex }) => {
    // console.log('up_file_slice:', fileIndex, name)
    try {
      let md5 = `${ fileIndex }.${ CryptoJS.MD5(fileIndex+name).toString() }`
      const md5LocalPath = rawPath.join(sftpCacheDir, name, md5)
      md5List.push(md5LocalPath)
      fs.writeFileSync(md5LocalPath, sliceFile)
      socket.emit('up_file_slice_success', md5)
    } catch (error) {
      consola.error('up_file_slice Error', error.message)
      socket.emit('up_file_slice_fail', error.message)
    }
  })
  // 3. 合并分片上传到服务器
  socket.on('up_file_slice_over', async ({ name, targetFilePath, range, size }) => {
    const md5CacheDirPath = rawPath.join(sftpCacheDir, name)
    const resultFilePath = rawPath.join(sftpCacheDir, name, name)
    fs.ensureDirSync(md5CacheDirPath)
    try {
	    console.log('md5List: ', md5List)
	    const arr = md5List.map((chunkFilePath, index) => {
	      return pipeStream(
	        chunkFilePath,
	        fs.createWriteStream(resultFilePath, { // 指定位置创建可写流
	          start: index * range,
	          end: (index + 1) * range
	        })
	      )
	    })
	    md5List = []
	    await Promise.all(arr)
	    let timer = null
	    let res = await sftpClient.fastPut(resultFilePath, targetFilePath, {
	      step: step => {
	        if (timer) return
	        timer = setTimeout(() => {
	          const percent = Math.ceil((step / size) * 100)
	          console.log(`上传服务器进度：${ percent }%`)
	          socket.emit('up_file_progress', percent)
	          timer = null
	        }, 200)
	      }
	    })
	    consola.success('sftp上传成功: ', res)
	    socket.emit('up_file_success', res)
    } catch (error) {
	    consola.error('sftp上传失败: ', error.message)
      socket.emit('up_file_fail', error.message)
    } finally {
      fs.remove(md5CacheDirPath)
        .then(() => {
          console.log('clean md5CacheDirPath:', md5CacheDirPath)
        })
    }
  })
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/sftp',
    cors: {
      origin: '*'
    }
  })
  serverIo.on('connection', (socket) => {
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    let sftpClient = new SFTPClient()
    consola.success('terminal websocket 已连接')

    socket.on('create', async ({ hostId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      consola.log('code:', code)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
      if (!targetHostInfo) throw new Error(`Host with ID ${ hostId } not found`)
      let { authType, host, port, username } = targetHostInfo
      if (!host) return socket.emit('create_fail', `查找id【${ hostId }】凭证信息失败`)
      let authInfo = { host, port, username }

      // 解密放到try里面，防止报错【commonKey必须配对, 否则需要重新添加服务器密钥】
      if (authType === 'credential') {
        let credentialId = await AESDecryptAsync(targetHostInfo[authType])
        const sshRecordList = await credentialsDB.findAsync({})
        const sshRecord = sshRecordList.find(item => item._id === credentialId)
        authInfo.authType = sshRecord.authType
        authInfo[authInfo.authType] = await AESDecryptAsync(sshRecord[authInfo.authType])
      } else {
        authInfo[authType] = await AESDecryptAsync(targetHostInfo[authType])
      }
      consola.info('准备连接Sftp面板：', host)
      targetHostInfo[targetHostInfo.authType] = await AESDecryptAsync(targetHostInfo[targetHostInfo.authType])

      consola.log('连接信息', { username, port, authType })
      sftpClient
        .connect(authInfo)
        .then(() => {
          consola.success('连接Sftp成功：', host)
          fs.ensureDirSync(sftpCacheDir)
          return sftpClient.list('/')
        })
        .then((rootLs) => {
          // 普通文件-、目录文件d、链接文件l
          socket.emit('root_ls', rootLs) // 先返回根目录
          listenInput(sftpClient, socket) // 监听前端请求
        })
        .catch((err) => {
          consola.error('创建Sftp失败:', err.message)
          socket.emit('create_fail', err.message)
        })
    })

    socket.on('disconnect', async () => {
      sftpClient.end()
        .then(() => {
          consola.info('sftp连接断开')
        })
        .catch((error) => {
          consola.info('sftp断开连接失败:', error.message)
        })
        .finally(() => {
          sftpClient = null
          fs.emptyDir(sftpCacheDir)
            .then(() => {
              consola.success('clean sftpCacheDir: ', sftpCacheDir)
            })
        })
    })
  })
}
