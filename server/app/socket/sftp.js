const { Server } = require('socket.io')
const SFTPClient = require('ssh2-sftp-client')
const rawPath = require('path')
const fs = require('fs')
const { readSSHRecord, verifyAuthSync, RSADecryptSync, AESDecryptSync } = require('../utils')
const { sftpCacheDir } = require('../config')
const CryptoJS = require('crypto-js')

function clearDir(path, rmSelf = false) {
  let files = []
  if(!fs.existsSync(path)) return consola.info('clearDir: 目标文件夹不存在')
  files = fs.readdirSync(path)
  files.forEach((file) => {
    let curPath = path + '/' + file
    if(fs.statSync(curPath).isDirectory()){
      clearDir(curPath) //递归删除文件夹
      fs.rmdirSync(curPath) // 删除文件夹
    } else {
      fs.unlinkSync(curPath) //删除文件
    }
  })
  if(rmSelf) fs.rmdirSync(path)
  consola.success('clearDir: 已清空缓存文件')
}
const pipeStream = (path, writeStream) => {
  // console.log('path', path)
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
  socket.on('open_dir', async (path) => {
    const exists = await sftpClient.exists(path)
    if(!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
    try {
      let dirLs = await sftpClient.list(path)
      socket.emit('dir_ls', dirLs)
    } catch (error) {
      consola.error('open_dir Error', error.message)
      socket.emit('sftp_error', error.message)
    }
  })
  socket.on('rm_dir', async (path) => {
    const exists = await sftpClient.exists(path)
    if(!exists) return socket.emit('not_exists_dir', '目录不存在或当前不可访问')
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
    if(!exists) return socket.emit('not_exists_dir', '文件不存在或当前不可访问')
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
  //   if(!exists) return socket.emit('not_exists_dir', '文件夹不存在或当前不可访问')
  //   let res = await sftpClient.downloadDir(path, sftpCacheDir)
  //   socket.emit('down_dir_success', res)
  // })
  socket.on('down_file', async ({ path, name, size, target = 'down' }) => {
    // target: down or preview
    const exists = await sftpClient.exists(path)
    if(!exists) return socket.emit('not_exists_dir', '文件不存在或当前不可访问')
    try {
      const localPath = rawPath.join(sftpCacheDir, name)
      let timer = null
      let res = await sftpClient.fastGet(path, localPath, {
        step: step => {
          if(timer) return
          timer = setTimeout(() => {
            const percent = Math.ceil((step / size) * 100) // 下载进度为服务器下载到服务端的进度，前端无需*2
            console.log(`从服务器下载进度：${ percent }%`)
            socket.emit('down_file_progress', percent)
            timer = null
          }, 200)
        }
      })
      consola.success('sftp下载成功: ', res)
      let buffer = fs.readFileSync(localPath)
      let data = { buffer, name }
      switch(target) {
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
  socket.on('up_file', async ({ targetPath, fullPath, name, file }) => {
    console.log({ targetPath, fullPath, name, file })
    const exists = await sftpClient.exists(targetPath)
    if(!exists) return socket.emit('not_exists_dir', '文件夹不存在或当前不可访问')
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

  /** 分片上传 */
  // 1. 创建本地缓存文件夹
  let md5List = []
  socket.on('create_cache_dir', async ({ targetPath, name }) => {
    // console.log({ targetPath, name })
    const exists = await sftpClient.exists(targetPath)
    if(!exists) return socket.emit('not_exists_dir', '文件夹不存在或当前不可访问')
    md5List = []
    const localPath = rawPath.join(sftpCacheDir, name)
    if(fs.existsSync(localPath)) clearDir(localPath) // 清空目录
    fs.mkdirSync(localPath, { recursive: true })
    console.log('================create_cache_success================')
    socket.emit('create_cache_success')
  })
  socket.on('up_file_slice', async ({ name, sliceFile, fileIndex }) => {
    // console.log('up_file_slice:', fileIndex, name)
    try {
      let md5 = `${ fileIndex }.${ CryptoJS.MD5(fileIndex+name).toString() }`
      const localPath = rawPath.join(sftpCacheDir, name, md5)
      md5List.push(localPath)
      fs.writeFileSync(localPath, sliceFile)
      socket.emit('up_file_slice_success', md5)
    } catch (error) {
      consola.error('up_file_slice Error', error.message)
      socket.emit('up_file_slice_fail', error.message)
    }
  })
  socket.on('up_file_slice_over', async ({ name, fullPath, range, size }) => {
    const resultDirPath = rawPath.join(sftpCacheDir, name)
    const resultFilePath = rawPath.join(sftpCacheDir, name, name)
    try {
	    console.log('md5List: ', md5List)
	    const arr = md5List.map((chunkFilePath, index) => {
	      return pipeStream(
	        chunkFilePath,
	        // 指定位置创建可写流
	        fs.createWriteStream(resultFilePath, {
	          start: index * range,
	          end: (index + 1) * range
	        })
	      )
	    })
	    md5List = []
	    await Promise.all(arr)
	    let timer = null
	    let res = await sftpClient.fastPut(resultFilePath, fullPath, {
	      step: step => {
	        if(timer) return
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
	    clearDir(resultDirPath, true) // 传服务器后移除文件夹及其文件
    } catch (error) {
	    consola.error('sftp上传失败: ', error.message)
      socket.emit('up_file_fail', error.message)
	    clearDir(resultDirPath, true) // 传服务器后移除文件夹及其文件
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
    let clientIp = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    let sftpClient = new SFTPClient()
    consola.success('terminal websocket 已连接')

    socket.on('create', async ({ host: ip, token }) => {
      const { code } = await verifyAuthSync(token, clientIp)
      if(code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      const sshRecord = await readSSHRecord()
      let loginInfo = sshRecord.find(item => item.host === ip)
      if(!sshRecord.some(item => item.host === ip)) return socket.emit('create_fail', `未找到【${ ip }】凭证`)
      let { type, host, port, username, randomKey } = loginInfo
      // 解密放到try里面，防止报错【公私钥必须配对, 否则需要重新添加服务器密钥】
      randomKey = await AESDecryptSync(randomKey) // 先对称解密key
      randomKey = await RSADecryptSync(randomKey) // 再非对称解密key
      loginInfo[type] = await AESDecryptSync(loginInfo[type], randomKey) // 对称解密ssh密钥
      consola.info('准备连接Sftp：', host)
      const authInfo = { host, port, username, [type]: loginInfo[type] }
      sftpClient.connect(authInfo)
        .then(() => {
          consola.success('连接Sftp成功：', host)
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
          const cacheDir = rawPath.join(sftpCacheDir)
          clearDir(cacheDir)
        })
    })
  })
}
