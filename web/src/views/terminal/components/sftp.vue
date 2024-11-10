<template>
  <div ref="sftpTabContainerRef" class="sftp_tab_container">
    <div ref="adjustRef" class="adjust" />
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

            <el-dropdown trigger="click">
              <div class="img">
                <img
                  src="@/assets/image/system/upload.png"
                  style=" width: 19px; height: 19px; "
                >
                <input
                  ref="uploadFileRef"
                  type="file"
                  style="display: none;"
                  multiple
                  @change="handleUploadFiles"
                >
                <input
                  ref="uploadDirRef"
                  style="display: none;"
                  type="file"
                  webkitdirectory
                  directory
                  @change="handleUploadDir"
                >
              </div>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item @click="uploadFileRef.click()">
                    上传文件
                  </el-dropdown-item>
                  <el-dropdown-item @click="uploadDirRef.click()">
                    上传文件夹
                  </el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </div>
          <div class="filter_input">
            <el-input
              v-model="filterKey"
              size="small"
              placeholder="Filter Files"
              clearable
            />
          </div>
          <el-input
            v-if="showPathInput"
            ref="pathInputRef"
            v-model="pathInput"
            class="path_input"
            size="small"
            clearable
            @blur="showPathInput = false"
            @keyup.enter="handleInputPath"
          />
          <span v-else class="path" @click="handleShowPathInput">{{ curPath }}</span>
          <div v-if="showFileProgress">
            <span>{{ curUploadFileName }}</span>
            <el-progress
              class="up-file-progress-wrap"
              :percentage="upFileProgress"
            />
          </div>
          <div v-if="showDirProgress">
            <span>文件夹创建: {{ curUploadDirName }}</span>
          </div>
        </div>
        <ul
          v-if="fileList.length !== 0"
          ref="childDirRef"
          v-loading="childDirLoading"
          element-loading-text="操作中..."
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

<script setup>
import { ref, computed, onMounted, onBeforeUnmount, getCurrentInstance } from 'vue'
import socketIo from 'socket.io-client'
import CodeEdit from '@/components/code-edit/index.vue'
import { EventBus, isDir, isFile, sortDirTree, downloadFile, isMobile } from '@/utils'
import dirIcon from '@/assets/image/system/dir.png'
import linkIcon from '@/assets/image/system/link.png'
import fileIcon from '@/assets/image/system/file.png'
import unknowIcon from '@/assets/image/system/unknow.png'

const { io } = socketIo

const props = defineProps({
  hostId: {
    required: true,
    type: String
  }
})

const emit = defineEmits(['resize',])

const { proxy: { $store, $notification, $message, $messageBox, $serviceURI, $nextTick } } = getCurrentInstance()

const visible = ref(false)
const originalCode = ref('')
const filename = ref('')
const filterKey = ref('')
const socket = ref(null)
const icons = {
  '-': fileIcon,
  l: linkIcon,
  d: dirIcon,
  c: dirIcon,
  p: unknowIcon,
  s: unknowIcon,
  b: unknowIcon
}
const paths = ref(['/',])
const rootLs = ref([])
const childDir = ref([])
const childDirLoading = ref(false)
const curTarget = ref(null)
const showFileProgress = ref(false)
const upFileProgress = ref(0)
const curUploadFileName = ref('')

const showDirProgress = ref(false)
const curUploadDirName = ref(0)

const adjustRef = ref(null)
const sftpTabContainerRef = ref(null)
const childDirRef = ref(null)
const uploadFileRef = ref(null)
const uploadDirRef = ref(null)
const forbiddenAction = ref(false)

const pathInputRef = ref(null)
const showPathInput = ref(false)
const pathInput = ref('')

const token = computed(() => $store.token)
const curPath = computed(() => paths.value.join('/').replace(/\/{2,}/g, '/'))
const fileList = computed(() => childDir.value.filter(({ name }) => name.includes(filterKey.value)))

onMounted(() => {
  connectSftp()
  adjustHeight()
  EventBus.$on('update-sftp-tab-height', () => {
    adjustHeight()
  })
})

onBeforeUnmount(() => {
  if (socket.value) socket.value.close()
})

const adjustHeight = async () => {
  let startAdjust = false
  let timer = null
  await $nextTick()
  try {
    let sftpHeight = localStorage.getItem('sftpHeight')
    if (sftpHeight) sftpTabContainerRef.value.style.height = sftpHeight
    adjustRef.value.addEventListener('mousedown', () => {
      startAdjust = true
    })
    document.addEventListener('mousemove', (e) => {
      if (!startAdjust) return
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => {
        sftpHeight = `calc(100vh - ${ e.pageY }px - 20px)`
        sftpTabContainerRef.value.style.height = sftpHeight
        emit('resize')
      })
    })
    document.addEventListener('mouseup', () => {
      if (!startAdjust) return
      startAdjust = false
      localStorage.setItem('sftpHeight', sftpHeight)
      EventBus.$emit('update-sftp-tab-height')
    })
  } catch (error) {
    console.warn(error.message)
  }
}

const connectSftp = () => {
  socket.value = io($serviceURI, {
    path: '/sftp',
    forceNew: false,
    reconnectionAttempts: 1
  })
  socket.value.on('connect', () => {
    console.log('/sftp socket已连接：', socket.value.id)
    listenSftp()
    socket.value.emit('create', { hostId: props.hostId, token: token.value })
    socket.value.on('root_ls', (tree) => {
      let temp = sortDirTree(tree).filter((item) => isDir(item.type))
      temp.unshift({ name: '/', type: 'd' })
      rootLs.value = temp
    })
    socket.value.on('create_fail', (message) => {
      $notification({
        title: 'Sftp连接失败',
        message,
        type: 'error'
      })
    })
    socket.value.on('token_verify_fail', () => {
      $notification({
        title: 'Error',
        message: 'token校验失败，需重新登录',
        type: 'error'
      })
    })
  })
  socket.value.on('disconnect', () => {
    console.warn('sftp websocket 连接断开')
    if (showFileProgress.value) {
      $notification({
        title: '上传失败',
        message: '请检查socket服务是否正常',
        type: 'error'
      })
      handleRefresh()
      resetFileStatusFlag()
    }
  })
  socket.value.on('connect_error', (err) => {
    console.error('sftp websocket 连接错误：', err)
    $notification({
      title: 'sftp连接失败',
      message: '请检查socket服务是否正常',
      type: 'error'
    })
  })
}

const listenSftp = () => {
  socket.value.on('dir_ls', (dirLs, path) => {
    childDir.value = sortDirTree(dirLs)
    childDirLoading.value = false
    // 格式化path为当前目录
    let formatPath = path.split('/').filter(item => item)
    formatPath.unshift('/')
    // console.log('formatPath:', formatPath)
    paths.value = formatPath
  })
  socket.value.on('not_exists_dir', (errMsg) => {
    if (errMsg) $message.error(errMsg)
    childDirLoading.value = false
  })
  socket.value.on('rm_success', (res) => {
    $message.success(res)
    childDirLoading.value = false
    forbiddenAction.value = false
    handleRefresh()
  })
  socket.value.on('down_file_success', (res) => {
    const { buffer, name } = res
    downloadFile({ buffer, name })
    $message.success('success')
    resetFileStatusFlag()
  })
  socket.value.on('preview_file_success', (res) => {
    const { buffer, name } = res
    originalCode.value = new TextDecoder().decode(buffer)
    filename.value = name
    visible.value = true
  })
  socket.value.on('sftp_error', (res) => {
    $message.error(res)
    forbiddenAction.value = false
    resetFileStatusFlag()
  })
  socket.value.on('up_file_progress', (res) => {
    let progress = Math.ceil(50 + (res / 2))
    upFileProgress.value = progress > 100 ? 100 : progress
  })
  socket.value.on('down_file_progress', (res) => {
    upFileProgress.value = res
  })
}

const openRootChild = (item) => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  const { name, type } = item
  if (isDir(type)) {
    childDirLoading.value = true
    paths.value.length = 2
    paths.value[1] = name
    $nextTick(() => {
      if (childDirRef.value) childDirRef.value.scrollTo(0, 0)
    })
    openDir()
    filterKey.value = ''
  } else {
    $message.warning(`暂不支持打开文件${ name } ${ type }`)
  }
}

const openTarget = (item) => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  const { name, type, size } = item
  if (isDir(type)) {
    paths.value.push(name)
    $nextTick(() => {
      if (childDirRef.value) childDirRef.value.scrollTo(0, 0)
    })
    openDir()
  } else if (isFile(type)) {
    if (size / 1024 / 1024 > 1) return $message.warning('暂不支持打开1M及以上文件, 请下载本地查看')
    const path = getPath(name)
    socket.value.emit('down_file', { path, name, size, target: 'preview' })
  } else {
    $message.warning(`暂不支持打开文件${ name } ${ type }`)
  }
}

const handleSaveCode = (code) => {
  let file = new TextEncoder('utf-8').encode(code)
  let name = filename.value
  const fullPath = getPath(name)
  const targetPath = curPath.value
  socket.value.emit('up_file', { targetPath, fullPath, name, file })
}

const handleClosedCode = () => {
  filename.value = ''
  originalCode.value = ''
}

const selectFile = (item) => {
  if (isMobile()) openTarget(item)
  curTarget.value = item
}

const handleReturn = () => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  if (paths.value.length === 1) return
  paths.value.pop()
  openDir()
}

const handleRefresh = () => {
  openDir()
}

const handleDownload = () => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  if (curTarget.value === null) return $message.warning('先选择一个文件')
  const { name, size, type } = curTarget.value
  if (isDir(type)) return $message.error('暂不支持下载文件夹')
  $messageBox.confirm(`确认下载：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(() => {
    childDirLoading.value = true
    const path = getPath(name)
    if (isDir(type)) {
      // '暂不支持下载文件夹'
    } else if (isFile(type)) {
      showFileProgress.value = true
      socket.value.emit('down_file', { path, name, size, target: 'down' })
    } else {
      $message.error('不支持下载的文件类型')
    }
  })
}

const handleDelete = () => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  if (curTarget.value === null) return $message.warning('先选择一个文件(夹)')
  const { name, type } = curTarget.value
  $messageBox.confirm(`确认删除：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(() => {
    childDirLoading.value = true
    const path = getPath(name)
    forbiddenAction.value = true
    if (isDir(type)) {
      socket.value.emit('rm_dir', path)
    } else {
      socket.value.emit('rm_file', path)
    }
  })
}

const handleUploadFiles = async (event) => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  let { files } = event.target

  forbiddenAction.value = true
  for (let file of files) {
    try {
      const targetFilePath = getPath(file.name)
      await uploadFile(file, targetFilePath)
    } catch (error) {
      $message.error(`${ file.name }上传失败: ${ error }`)
    }
  }
  $notification.success({
    title: '文件上传完成',
    message: '上传操作完成, 请确认服务器文件是否上传成功',
    duration: 30000
  })
  forbiddenAction.value = false
  event.target.value = ''
  uploadFileRef.value = null
}

const handleUploadDir = async (event) => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  let { files } = event.target
  if (files.length === 0) return $message.warning('不允许上传空文件夹')
  files = Array.from(files)
  // console.log(files)
  // 文件夹可能嵌套, 需先创建文件夹
  let foldersName = files.map(file => file.webkitRelativePath.split('/').slice(0, -1).join('/'))
  if (foldersName.length === 0) return $message.warning('不允许上传空文件夹')
  // console.log(foldersName)
  let targetDirPath = curPath.value
  forbiddenAction.value = true
  socket.value.emit('create_remote_dir', { targetDirPath, foldersName })
  socket.value.once('create_remote_dir_exists', (res) => {
    $message.error(res)
    event.target.value = ''
    uploadDirRef.value = null
    forbiddenAction.value = false
  })
  function computedUploadDirProgress(path) {
    // $message.success('创建服务器文件夹中...')
    // console.log(path)
    showDirProgress.value = true
    curUploadDirName.value = path
  }
  $message.success('创建服务器文件夹中...')
  socket.value.on('create_remote_dir_progress', computedUploadDirProgress)
  socket.value.once('create_remote_dir_success', async () => {
    socket.value.off('create_remote_dir_progress', computedUploadDirProgress)
    showDirProgress.value = false
    curUploadDirName.value = ''
    $message.success('服务器文件夹创建成功, 开始上传文件')
    for (let [index, file,] of files.entries()) {
      let fullFilePath = getPath(`${ foldersName[index] }/${ file.name }`)
      console.log('fullFilePath: ', fullFilePath)
      try {
        await uploadFile(file, fullFilePath)
      } catch (error) {
        $message.error(`${ file.name }上传失败: ${ error }`)
      }
    }
    $notification.success({
      title: '文件夹上传完成',
      message: '上传操作完成, 请确认服务器文件夹是否上传成功',
      duration: 30000
    })
    forbiddenAction.value = false
    event.target.value = ''
    uploadDirRef.value = null
  })
}

const uploadFile = (file, targetFilePath) => {
  return new Promise((resolve, reject) => {
    if (!file) return reject('file is not defined')
    let reader = new FileReader()
    reader.onload = async () => {
      const { name } = file
      const targetDirPath = curPath.value
      curUploadFileName.value = name
      const size = file.size
      if (size === 0) return reject('文件大小为0KB, 无法上传')
      socket.value.emit('create_cache_dir', { targetDirPath, name })
      socket.value.once('create_cache_success', async () => {
        let start = 0
        let end = 0
        const range = 1024 * 512 // 每段512KB
        let fileIndex = 0
        let multipleFlag = false
        try {
          upFileProgress.value = 0
          showFileProgress.value = true
          const totalSliceCount = Math.ceil(size / range)
          while (end < size) {
            fileIndex++
            end += range
            const sliceFile = file.slice(start, end)
            start = end
            await uploadSliceFile({ name, sliceFile, fileIndex })
            upFileProgress.value = parseInt((fileIndex / totalSliceCount * 100) / 2)
          }
          socket.value.emit('up_file_slice_over', { name, targetFilePath, range, size })
          socket.value.once('up_file_success', () => {
            if (multipleFlag) return
            handleRefresh()
            resetFileStatusFlag()
            multipleFlag = true
            resolve()
          })
          socket.value.once('up_file_fail', (res) => {
            if (multipleFlag) return
            $message.error(res)
            handleRefresh()
            resetFileStatusFlag()
            multipleFlag = true
            reject()
          })
        } catch (err) {
          reject(err)
          const errMsg = `上传失败, ${ err }`
          $message.error(errMsg)
          handleRefresh()
          resetFileStatusFlag()
        }
      })
    }
    reader.readAsArrayBuffer(file)
  })
}

const resetFileStatusFlag = () => {
  upFileProgress.value = 0
  curUploadFileName.value = ''
  showFileProgress.value = false
  childDirLoading.value = false
}

const uploadSliceFile = (fileInfo) => {
  return new Promise((resolve, reject) => {
    socket.value.emit('up_file_slice', fileInfo)
    socket.value.once('up_file_slice_success', () => {
      resolve()
    })
    socket.value.once('up_file_slice_fail', () => {
      reject('分片文件上传失败')
    })
    socket.value.once('not_exists_dir', (errMsg) => {
      reject(errMsg)
    })
  })
}

const openDir = (path = '', tips = true) => {
  childDirLoading.value = true
  curTarget.value = null
  socket.value.emit('open_dir', path || curPath.value, tips)
}

const getPath = (name = '') => {
  return curPath.value.length === 1 ? `/${ name }` : `${ curPath.value }/${ name }`
}

const handleShowPathInput = () => {
  showPathInput.value = true
  pathInput.value = curPath.value
  $nextTick(() => {
    pathInputRef.value.focus()
  })
}
const handleInputPath = () => {
  if (forbiddenAction.value) return $message.warning('需等待当前任务完成')
  // socket.value.emit('input_path', curPath.value)
  showPathInput.value = false
  openDir(pathInput.value)
}

defineExpose({
  openDir
})

</script>

<style lang="scss" scoped>
.sftp_tab_container {
  position: relative;
  background: #ffffff;
  border: 1px solid var(--el-border-color);
  .adjust {
    user-select: none;
    position: absolute;
    top: -3px;
    width: 100%;
    height: 5px;
    background: var(--el-color-primary);
    opacity: 0.3;
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
        background-color: var(--el-fill-color-light);
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
        .filter_input {
          width: 200px;
          min-width: 200px;
          margin: 0 20px 0 10px;
        }
        .path_input {
          width: 450px;
          min-width: 450px;
        }
        .path {
          flex: 1;
          user-select: all;
          cursor: pointer;
          &:hover {
            color: var(--el-color-primary);
          }
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
          padding: 5px 0 5px 3px;
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
      min-width: 200px;
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
