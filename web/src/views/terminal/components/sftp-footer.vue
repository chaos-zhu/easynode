<template>
  <div class="sftp-container">
    <div ref="adjust" class="adjust" />
    <section>
      <div class="left box">
        <div class="header">
          <div class="operation">
            根目录
            <span style="font-size: 12px;color: gray;transform: scale(0.8);margin-left: -10px;">
              (单击选择, 双击打开)
            </span>
          </div>
        </div>
        <ul class="dir-list">
          <li
            v-for="item in rootLs"
            :key="item.name"
            @click="openRootChild(item)"
          >
            <img :src="icons[item.type]" :alt="item.type">
            <span>{{ item.name }}</span>
          </li>
        </ul>
      </div>
      <div class="right box">
        <div class="header">
          <div class="operation">
            <tooltip content="上级目录">
              <div class="img">
                <img src="@/assets/image/system/return.png" alt="" @click="handleReturn">
              </div>
            </tooltip>
            <tooltip content="刷新">
              <div class="img">
                <img
                  src="@/assets/image/system/refresh.png"
                  style=" width: 15px; height: 15px; margin-top: 2px; margin-left: 2px;"
                  @click="handleRefresh"
                >
              </div>
            </tooltip>
            <tooltip content="删除">
              <div class="img">
                <img
                  src="@/assets/image/system/delete.png"
                  style="height: 20px; width: 20px;"
                  @click="handleDelete"
                >
              </div>
            </tooltip>
            <tooltip content="下载选择文件">
              <div class="img">
                <img
                  src="@/assets/image/system/download.png"
                  style=" height: 22px; width: 22px; margin-left: -3px; "
                  @click="handleDownload"
                >
              </div>
            </tooltip>
            <tooltip content="上传到当前目录">
              <div class="img">
                <img
                  src="@/assets/image/system/upload.png"
                  style=" width: 19px; height: 19px; "
                  @click="$refs['upload_file'].click()"
                >
                <input
                  ref="upload_file"
                  type="file"
                  style="display: none;"
                  multiple
                  @change="handleUpload"
                >
              </div>
            </tooltip>
            <!-- <tooltip content="搜索">
              <div class="img">
                <img
                  src="@/assets/image/system/search.png"
                  style="width: 20px; height: 20px; margin-top: 1px;"
                >
              </div>
            </tooltip> -->
          </div>
          <div class="filter-input">
            <el-input
              v-model="filterKey"
              size="small"
              placeholder="Filter Files"
              clearable
            />
          </div>
          <span class="path">{{ curPath }}</span>
          <div v-if="showFileProgress">
            <span>{{ curUploadFileName }}</span>
            <el-progress
              class="up-file-progress-wrap"
              :percentage="upFileProgress"
            />
          </div>
        </div>
        <ul
          v-if="fileList.length !== 0"
          ref="child-dir"
          v-loading="childDirLoading"
          element-loading-text="加载中..."
          class="dir-list"
        >
          <li
            v-for="item in fileList"
            :key="item.name"
            :class="curTarget === item ? 'active' : ''"
            @click="selectFile(item)"
            @dblclick="openTarget(item)"
          >
            <img :src="icons[item.type]" :alt="item.type">
            <span>{{ item.name }}</span>
          </li>
        </ul>
        <div v-else>
          <el-empty :image-size="100" description="空空如也~" />
        </div>
      </div>
    </section>
    <CodeEdit
      v-model:show="visible"
      :original-code="originalCode"
      :filename="filename"
      @save="handleSaveCode"
      @closed="handleClosedCode"
    />
  </div>
</template>

<script>
import socketIo from 'socket.io-client'
import CodeEdit from '@/components/code-edit/index.vue'
import { isDir, isFile, sortDirTree, downloadFile } from '@/utils'
import dirIcon from '@/assets/image/system/dir.png'
import linkIcon from '@/assets/image/system/link.png'
import fileIcon from '@/assets/image/system/file.png'
import unknowIcon from '@/assets/image/system/unknow.png'

const { io } = socketIo
export default {
  name: 'Sftp',
  components: { CodeEdit },
  props: {
    token: {
      required: true,
      type: String
    },
    host: {
      required: true,
      type: String
    }
  },
  emits: ['resize',],
  data() {
    return {
      visible: false,
      originalCode: '',
      filename: '',
      filterKey: '',
      socket: null,
      icons: {
        '-': fileIcon,
        l: linkIcon,
        d: dirIcon,
        c: dirIcon,
        p: unknowIcon,
        s: unknowIcon,
        b: unknowIcon
      },
      paths: ['/',],
      rootLs: [],
      childDir: [],
      childDirLoading: false,
      curTarget: null,
      showFileProgress: false,
      upFileProgress: 0,
      curUploadFileName: ''
    }
  },
  computed: {
    curPath() {
      return this.paths.join('/').replace(/\/{2,}/g, '/')
    },
    fileList() {
      return this.childDir.filter(({ name }) => name.includes(this.filterKey))
    }
  },
  mounted() {
    this.connectSftp()
    this.adjustHeight()
  },
  beforeUnmount() {
    this.socket && this.socket.close()
  },
  methods: {
    connectSftp() {
      let { host, token } = this
      this.socket = io(this.$serviceURI, {
        path: '/sftp',
        forceNew: false, // 强制新的连接
        reconnectionAttempts: 1 // 尝试重新连接次数
      })
      this.socket.on('connect', () => {
        console.log('/sftp socket已连接：', this.socket.id)
        this.listenSftp()
        // 验证身份并连接终端
        this.socket.emit('create', { host, token })
        this.socket.on('root_ls', (tree) => {
          // console.log(tree)
          let temp = sortDirTree(tree).filter((item) => isDir(item.type)) // 只保留文件夹类型的文件
          temp.unshift({ name: '/', type: 'd' })
          this.rootLs = temp
        })
        this.socket.on('create_fail', (message) => {
          // console.error(message)
          this.$notification({
            title: 'Sftp连接失败',
            message,
            type: 'error'
          })
        })
        this.socket.on('token_verify_fail', () => {
          this.$notification({
            title: 'Error',
            message: 'token校验失败，需重新登录',
            type: 'error'
          })
          // this.$router.push('/login')
        })
      })
      this.socket.on('disconnect', () => {
        console.warn('sftp websocket 连接断开')
        if(this.showFileProgress) {
          this.$notification({
            title: '上传失败',
            message: '请检查socket服务是否正常',
            type: 'error'
          })
          this.handleRefresh()
          this.resetFileStatusFlag()
        }
      })
      this.socket.on('connect_error', (err) => {
        console.error('sftp websocket 连接错误：', err)
        this.$notification({
          title: 'sftp连接失败',
          message: '请检查socket服务是否正常',
          type: 'error'
        })
      })
    },
    // 这个方法连接socket只能调用一次，否则on回调会执行多次
    listenSftp() {
      this.socket.on('dir_ls', (dirLs) => {
        // console.log('dir_ls: ', dirLs)
        this.childDir = sortDirTree(dirLs)
        this.childDirLoading = false
      })
      this.socket.on('not_exists_dir', (errMsg) => {
        this.$message.error(errMsg)
        this.childDirLoading = false
      })
      this.socket.on('rm_success', (res) => {
        this.$message.success(res)
        this.childDirLoading = false
        this.handleRefresh()
      })
      // this.socket.on('down_dir_success', (res) => {
      //   console.log(res)
      //   this.$message.success(res)
      //   this.childDirLoading = false
      // })
      this.socket.on('down_file_success', (res) => {
        const { buffer, name } = res
        downloadFile({ buffer, name })
        this.$message.success('success')
        this.resetFileStatusFlag()
      })
      this.socket.on('preview_file_success', (res) => {
        const { buffer, name } = res
        console.log('preview_file: ', name, buffer)
        // String.fromCharCode.apply(null, new Uint8Array(temp1))
        this.originalCode = new TextDecoder().decode(buffer)
        this.filename = name
        this.visible = true
      })
      this.socket.on('sftp_error', (res) => {
        console.log('操作失败:', res)
        this.$message.error(res)
        this.resetFileStatusFlag()
      })
      this.socket.on('up_file_progress', (res) => {
        // console.log('上传进度:', res)
        // 浏览器到服务端占比50%，服务端到服务器占比50%
        let progress = Math.ceil(50 + (res / 2))
        this.upFileProgress = progress > 100 ? 100 : progress
      })
      this.socket.on('down_file_progress', (res) => {
        // console.log('下载进度:', res)
        this.upFileProgress = res
      })
    },
    openRootChild(item) {
      const { name, type } = item
      if(isDir(type)) {
        this.childDirLoading = true
        this.paths.length = 2
        this.paths[1] = name
        this.$refs['child-dir']?.scrollTo(0, 0)
        this.openDir()
        this.filterKey = '' // 移除搜索条件
      }else {
        console.log('暂不支持打开文件', name, type)
        this.$message.warning(`暂不支持打开文件${ name } ${ type }`)
      }
    },
    openTarget(item) {
      console.log(item)
      const { name, type, size } = item
      if(isDir(type)) {
        this.paths.push(name)
        this.$refs['child-dir']?.scrollTo(0, 0)
        this.openDir()
      } else if(isFile(type)) {
        if(size/1024/1024 > 1) return this.$message.warning('暂不支持打开1M及以上文件, 请下载本地查看')
        const path = this.getPath(name)
        this.socket.emit('down_file', { path, name, size, target: 'preview' })
      } else {
        this.$message.warning(`暂不支持打开文件${ name } ${ type }`)
      }
    },
    handleSaveCode(code) {
      // console.log('code: ', code)
      let file = new TextEncoder('utf-8').encode(code)
      let name = this.filename
      const fullPath = this.getPath(name)
      const targetPath = this.curPath
      this.socket.emit('up_file', { targetPath, fullPath, name, file })
    },
    handleClosedCode() {
      this.filename = ''
      this.originalCode = ''
    },
    selectFile(item) {
      this.curTarget = item
    },
    handleReturn() {
      if(this.paths.length === 1) return
      this.paths.pop()
      this.openDir()
    },
    handleRefresh() {
      this.openDir()
    },
    handleDownload() {
      if(this.curTarget === null) return this.$message.warning('先选择一个文件')
      const { name, size, type } = this.curTarget
      if(isDir(type)) return this.$message.error('暂不支持下载文件夹')
      this.$messageBox.confirm( `确认下载：${ name }`, 'Warning', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
        .then(() => {
          this.childDirLoading = true
          const path = this.getPath(name)
          if(isDir(type)) {
            // '暂不支持下载文件夹'
            // this.socket.emit('down_dir', path)
          }else if(isFile(type)) {
            this.showFileProgress = true
            this.socket.emit('down_file', { path, name, size, target: 'down' })
          }else {
            this.$message.error('不支持下载的文件类型')
          }
        })
    },
    handleDelete() {
      if(this.curTarget === null) return this.$message.warning('先选择一个文件(夹)')
      const { name, type } = this.curTarget
      this.$messageBox.confirm( `确认删除：${ name }`, 'Warning', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
        .then(() => {
          this.childDirLoading = true
          const path = this.getPath(name)
          if(isDir(type)) {
            this.socket.emit('rm_dir', path)
          }else {
            this.socket.emit('rm_file', path)
          }
        })
    },
    async handleUpload(event) {
      if(this.showFileProgress) return this.$message.warning('需等待当前任务完成')
      let { files } = event.target
      for(let file of files) {
        console.log(file)
        try {
          await this.uploadFile(file)
        } catch (error) {
          this.$message.error(error)
        }
      }
      this.$refs['upload_file'].value = ''
    },
    uploadFile(file) {
      return new Promise((resolve, reject) => {
        if(!file) return reject('file is not defined')
        if((file.size/1024/1024)> 1000) {
          this.$message.warn('用网页传这么大文件你是认真的吗?')
        }
        let reader = new FileReader()
        reader.onload = async (e) => {
          // console.log('buffer:', e.target.result)
          const { name } = file
          const fullPath = this.getPath(name)
          const targetPath = this.curPath
          this.curUploadFileName = name
          this.socket.emit('create_cache_dir', { targetPath, name })
          // 每次上传只监听一次，多次监听会导致回调重复执行
          this.socket.once('create_cache_success', async () => {
            let start = 0
            let end = 0
            let range = 1024 * 512 // 每段512KB
            let size = file.size
            let fileIndex = 0
            let multipleFlag = false // 用于防止上一个文件失败导致多次执行once
            try {
              console.log('=========开始上传分片=========')
              this.upFileProgress = 0
              this.showFileProgress = true
              this.childDirLoading = true
              let totalSliceCount = Math.ceil(size / range)
              while(end < size) {
                fileIndex++
                end += range
                let sliceFile = file.slice(start, end)
                start = end
                await this.uploadSliceFile({ name, sliceFile, fileIndex })
                // 浏览器到服务端占比50%，服务端到服务器占比50%
                this.upFileProgress = parseInt((fileIndex / totalSliceCount * 100) / 2)
              }
              console.log('=========分片上传完成(等待服务端上传至客户端)=========')
              this.socket.emit('up_file_slice_over', { name, fullPath, range, size })
              this.socket.once('up_file_success', (res) => {
                if(multipleFlag) return
                console.log('=========服务端上传至客户端上传完成✔=========')
                // console.log('up_file_success:', res)
                // this.$message.success(res)
                this.handleRefresh()
                this.resetFileStatusFlag()
                multipleFlag = true
                resolve()
              })
              this.socket.once('up_file_fail', (res) => {
                if(multipleFlag) return
                console.log('=========服务端上传至客户端上传失败❌=========')
                // console.log('up_file_fail:', res)
                this.$message.error(res)
                this.handleRefresh()
                this.resetFileStatusFlag()
                multipleFlag = true
                reject()
              })
            } catch (err) {
              reject(err)
              let errMsg = `上传失败, ${ err }`
              console.error(errMsg)
              this.$message.error(errMsg)
              this.handleRefresh()
              this.resetFileStatusFlag()
            }
          })
        }
        reader.readAsArrayBuffer(file)
      })
    },
    resetFileStatusFlag() {
      this.upFileProgress = 0
      this.curUploadFileName = ''
      this.showFileProgress = false
      this.childDirLoading = false
    },
    uploadSliceFile(fileInfo) {
      return new Promise((resolve, reject) => {
        this.socket.emit('up_file_slice', fileInfo)
        this.socket.once('up_file_slice_success', () => {
          resolve()
        })
        this.socket.once('up_file_slice_fail', () => {
          reject('分片文件上传失败')
        })
        this.socket.once('not_exists_dir', (errMsg) => {
          reject(errMsg)
        })
      })
    },
    openDir() {
      this.childDirLoading = true
      this.curTarget = null
      this.socket.emit('open_dir', this.curPath)
    },
    getPath(name = '') {
      return this.curPath.length === 1 ? `/${ name }` : `${ this.curPath }/${ name }`
    },
    adjustHeight() {
      let startAdjust = false
      let timer = null
      this.$nextTick(() => {
        let sftpHeight = localStorage.getItem('sftpHeight')
        if(sftpHeight) document.querySelector('.sftp-container').style.height = sftpHeight
        else document.querySelector('.sftp-container').style.height = '33vh' // 默认占据页面高度1/3

        this.$refs['adjust'].addEventListener('mousedown', () => {
          // console.log('开始调整')
          startAdjust = true
        })
        document.addEventListener('mousemove', (e) => {
          if(!startAdjust) return
          if(timer) clearTimeout(timer)
          timer = setTimeout(() => {
            sftpHeight = `calc(100vh - ${ e.pageY }px)`
            document.querySelector('.sftp-container').style.height = sftpHeight
            this.$emit('resize')
          })
        })
        document.addEventListener('mouseup', (e) => {
          if(!startAdjust) return
          startAdjust = false
          sftpHeight = `calc(100vh - ${ e.pageY }px)`
          localStorage.setItem('sftpHeight', sftpHeight)
        })
      })
    }
  }
}
</script>

<style lang="scss" scoped>
.sftp-container {
  position: relative;
  background: #ffffff;
  height: 400px;
  .adjust {
    user-select: none;
    position: absolute;
    top: -5px;
    left: 50%;
    transform: translateX(-25px);
    width: 50px;
    height: 5px;
    background: rgb(138, 226, 52);
    border-radius: 3px;
    cursor: ns-resize;
  }
  section {
    height: 100%;
    display: flex;
    // common
    .box {
      $header_height: 30px;
      .header {
        user-select: none;
        height: $header_height;
        padding: 0 5px;
        background: #e1e1e2;
        display: flex;
        align-items: center;
        font-size: 12px;
        .operation {
          display: flex;
          align-items: center;
          // margin-right: 20px;
          .img {
            margin: 0 5px;
            width: 20px;
            height: 20px;
            img {
              width: 100%;
              height: 100%;
            }
            &:hover {
              background: #cec4c4;
            }
          }
        }
        .filter-input {
          width: 200px;
          margin: 0 20px 0 10px;
        }
        .path {
          flex: 1;
          user-select: all;
        }
        .up-file-progress-wrap {
          min-width: 200px;
          max-width: 350px;
        }
      }
      .dir-list {
        overflow: auto;
        scroll-behavior: smooth;
        height: calc(100% - $header_height);
        user-select: none;
        display: flex;
        flex-direction: column;
        .active {
          background: #e9e9e9;
        }
        li {
          font-size: 14px;
          padding: 5px 3px;
          color: #303133;
          display: flex;
          align-items: center;
          // cursor: pointer;
          &:hover {
            background: #e9e9e9;
          }
          img {
            width: 20px;
            height: 20px;
            margin-right: 3px;
          }
          span {
            line-height: 20px;
          }
        }
      }
    }
    .left {
      width: 200px;
      border-right: 1px solid #dcdfe6;
      .dir-list {
        li:nth-child(n+2){
          margin-left: 15px;
        }
      }
    }
    .right {
      flex: 1;
    }
  }
}
</style>
