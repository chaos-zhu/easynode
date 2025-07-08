<template>
  <div class="sftp_v2_container">
    <!-- 连接状态显示 -->
    <div v-if="connectionStatus !== 'connected'" class="connection_status">
      <div v-if="connectionStatus === 'connecting'" class="status_connecting">
        <el-icon class="is-loading"><Loading /></el-icon>
        <span>正在连接 SFTP...</span>
      </div>
      <div v-else-if="connectionStatus === 'reconnecting'" class="status_reconnecting">
        <el-icon class="is-loading"><Loading /></el-icon>
        <span>重新连接中...</span>
      </div>
      <div v-else-if="connectionStatus === 'failed'" class="status_failed">
        <el-icon class="error_icon"><WarningFilled /></el-icon>
        <div class="error_content">
          <h3>SFTP连接失败</h3>
          <p>{{ connectionError || '请检查服务端状态或网络连接' }}</p>
          <el-button type="primary" size="small" @click="connectSftp">重新连接</el-button>
        </div>
      </div>
    </div>

    <!-- 正常内容区域（连接成功时显示） -->
    <template v-if="connectionStatus === 'connected'">
      <!-- 工具栏：上传 / 新建 / 压缩 -->
      <div class="tool_bar">
        <!-- 上传 -->
        <el-dropdown trigger="click">
          <el-button type="" size="small">
            上传 <el-icon><ArrowDown /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleUpload('file')">上传文件</el-dropdown-item>
              <el-dropdown-item @click="handleUpload('folder')">上传文件夹</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>

        <!-- 新建 -->
        <div style="position: relative;">
          <el-dropdown trigger="click">
            <el-button ref="newBtnRef" size="small">
              新建 <el-icon><ArrowDown /></el-icon>
            </el-button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item @click="handleNew('file')">新建文件</el-dropdown-item>
                <el-dropdown-item @click="handleNew('folder')">新建文件夹</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <!-- 隐藏的触发元素，用于 Popover 定位 -->
          <div ref="createPopoverRef" style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none;" />
        </div>

        <!-- 收藏 -->
        <el-dropdown v-if="hasFavorites" trigger="click">
          <el-button type="" size="small">
            收藏 <el-icon><ArrowDown /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu class="favorite_dropdown">
              <el-dropdown-item
                v-for="favorite in favoriteList"
                :key="favorite._id"
                class="favorite_item"
                @click="navigateToFavorite(favorite)"
              >
                <div class="favorite_content">
                  <span class="favorite_path" :title="favorite.path">{{ favorite.path }}</span>
                  <el-icon
                    class="delete_icon"
                    title="删除收藏"
                    @click.stop="removeFavorite(favorite)"
                  >
                    <Delete />
                  </el-icon>
                </div>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>

      <!-- 路径栏：当前路径 + 操作按钮 -->
      <div class="path_bar">
        <el-icon class="action_icon" @click="goParent"><ArrowLeft /></el-icon>
        <template v-if="!isEditingPath">
          <div ref="breadcrumbRef" class="breadcrumb_wrap">
            <span
              v-for="(seg, idx) in breadcrumb"
              :key="idx"
              class="breadcrumb_seg"
              @click="handleBreadcrumb(idx)"
            >
              <template v-if="idx!==0">
                <el-icon><ArrowRight /></el-icon>
              </template>
              <span v-if="idx===0">
                <el-icon><HomeFilled /></el-icon>
                <span v-if="seg !== '/' && seg !== '~'">{{ seg }}</span>
              </span>
              <span v-else>{{ seg }}</span>
            </span>
          </div>
        </template>
        <template v-else>
          <el-input
            v-model="pathInput"
            size="small"
            class="path_input"
            @keyup.enter="confirmPathInput"
            @blur="cancelEditPath"
          />
        </template>
        <el-icon class="action_icon" title="编辑路径" @click="toggleEditPath"><Edit /></el-icon>
        <el-icon class="action_icon" title="复制当前路径" @click="copyCurrentPath"><DocumentCopy /></el-icon>
        <el-icon class="action_icon" title="刷新" @click="refresh"><Refresh /></el-icon>
        <el-icon class="action_icon" :title="showHidden ? '隐藏隐藏文件' : '显示隐藏文件'" @click="toggleHidden">
          <View v-if="showHidden" />
          <Hide v-else />
        </el-icon>
        <el-icon
          v-if="hasDownloadTasks"
          class="action_icon download_icon"
          :title="`下载管理 - 正在下载 ${activeDownloadTasks.length} 个任务`"
          @click="showDownloadManager"
        >
          <Download />
        </el-icon>
        <el-icon
          v-if="hasUploadTasks"
          class="action_icon upload_icon"
          :title="`上传管理 - 正在上传 ${activeUploadTasks.length} 个任务`"
          @click="showUploadManager"
        >
          <Upload />
        </el-icon>
      </div>

      <!-- 文件列表 -->
      <el-table
        ref="tableRef"
        v-loading="loading"
        :data="fileList"
        height="100%"
        size="small"
        :default-sort="{ prop: 'name' }"
        class="file_table"
        element-loading-text="loading..."
        @row-click="onRowClick"
        @row-contextmenu="onRowContextMenu"
        @selection-change="onSelectionChange"
      >
        <el-table-column type="selection" width="32" />
        <el-table-column
          label="名称"
          width="auto"
          max-width="200"
          show-overflow-tooltip
        >
          <template #default="{ row }">
            <div class="file_name_cell">
              <img :src="getIcon(row.type)" class="file_icon">
              <template v-if="isEditing(row)">
                <el-input
                  v-model="editingName"
                  size="small"
                  class="rename_input"
                  @click.stop
                  @keyup.enter.stop="confirmRename(row)"
                  @keyup.esc.stop="cancelRename"
                />
                <el-icon class="rename_icon" @click.stop="confirmRename(row)"><Check /></el-icon>
                <el-icon class="rename_icon" @click.stop="cancelRename"><CloseIcon /></el-icon>
              </template>
              <template v-else>
                <span class="file_name" v-text="row.name" />
                <el-icon
                  class="star_icon"
                  :class="{ 'favorited': isFavorited(row) }"
                  :title="isFavorited(row) ? '取消收藏' : '收藏'"
                  @click.stop="toggleFavorite(row)"
                >
                  <StarFilled v-if="isFavorited(row)" />
                  <Star v-else />
                </el-icon>
              </template>
            </div>
          </template>
        </el-table-column>
        <el-table-column
          prop="size"
          label="大小"
          :formatter="sizeFormatter"
          width="70"
        />
        <el-table-column
          prop="modifyTime"
          label="修改时间"
          width="80"
          :formatter="timeFormatter"
        />
      <!-- 权限列已隐藏，根据需求可再启用 -->
      </el-table>

      <!-- 新建文件/文件夹 Popover（虚拟触发） -->
      <el-popover
        v-model:visible="showCreatePopover"
        :virtual-ref="createPopoverRef"
        width="260"
        trigger="manual"
        placement="bottom-start"
        popper-class="sftp_create_popover"
      >
        <template #default>
          <el-input
            ref="createInputRef"
            v-model="createName"
            size="small"
            :placeholder="createType === 'folder' ? '输入文件夹名称' : '输入文件名称'"
            @keyup.enter="confirmCreate"
          />
          <div class="sftp_popover_actions">
            <el-button size="small" @click="showCreatePopover = false">取消</el-button>
            <el-button size="small" type="primary" @click="confirmCreate">确认</el-button>
          </div>
        </template>
      </el-popover>

      <!-- 隐藏的文件选择器 -->
      <input
        ref="uploadInputRef"
        type="file"
        multiple
        style="display: none"
        @change="handleFileSelect"
      >
      <input
        ref="uploadDirInputRef"
        type="file"
        webkitdirectory
        style="display: none"
        @change="handleDirSelect"
      >

      <!-- 文本编辑器 -->
      <TextEditor
        v-model="showTextEditor"
        :file-path="textEditorConfig.filePath"
        :file-name="textEditorConfig.fileName"
        :file-size="textEditorConfig.fileSize"
        :socket="socket"
        @saved="onTextFileSaved"
      />

      <!-- 图片预览 -->
      <ImagePreview
        v-model="showImagePreview"
        :image-src="imagePreviewConfig.imageSrc"
        :file-name="imagePreviewConfig.fileName"
        :file-size="imagePreviewConfig.fileSize"
        :file-path="imagePreviewConfig.filePath"
        @download="onImageDownload"
      />

      <!-- 下载任务管理对话框 -->
      <el-dialog
        v-model="showDownloadDialog"
        title="下载管理"
        width="600px"
        :close-on-click-modal="true"
      >
        <el-alert type="success" :closable="false" style="margin-bottom: 16px;">
          <template #title>
            <p style="font-size: 12px;"> 下列文件只在本次会话保留,连接断开后自动清理 </p>
          </template>
        </el-alert>
        <div class="download_manager_container">
          <!-- 正在下载的任务 -->
          <div v-if="activeDownloadTasks.length > 0" class="download_section">
            <h4 class="section_title">正在下载 ({{ activeDownloadTasks.length }})</h4>
            <div class="download_task_list">
              <div
                v-for="task in activeDownloadTasks"
                :key="task.taskId"
                class="download_task_item"
              >
                <div class="task_header">
                  <div class="file_info">
                    <el-icon class="file_icon"><Download /></el-icon>
                    <span class="file_name" :title="task.fileName">{{ task.fileName }}</span>
                  </div>
                  <el-button
                    size="small"
                    type="danger"
                    @click="cancelDownload(task.taskId)"
                  >
                    取消
                  </el-button>
                </div>

                <div class="progress_info">
                  <el-progress
                    :percentage="task.progress"
                    :show-text="false"
                    :stroke-width="6"
                    status="success"
                  />
                  <div class="progress_details">
                    <span class="progress_text">
                      {{ formatSize(task.downloadedSize) }} / {{ formatSize(task.totalSize) }}
                      ({{ task.progress.toFixed(1) }}%)
                    </span>
                    <span class="speed_text">
                      {{ formatSpeed(task.speed) }} · {{ formatTime(task.eta) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 已完成的任务 -->
          <div v-if="completedDownloadTasks.length > 0" class="download_section">
            <h4 class="section_title">已完成 ({{ completedDownloadTasks.length }})</h4>
            <div class="download_task_list">
              <div
                v-for="task in completedDownloadTasks"
                :key="task.taskId"
                class="download_task_item completed"
              >
                <div class="task_header">
                  <div class="file_info">
                    <el-icon class="file_icon success"><Check /></el-icon>
                    <span class="file_name" :title="task.fileName">{{ task.fileName }}</span>
                  </div>
                  <div class="task_actions">
                    <el-button
                      size="small"
                      type="primary"
                      @click="downloadFile(task)"
                    >
                      下载
                    </el-button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 无任务时的提示 -->
          <div v-if="!hasDownloadTasks" class="no_tasks">
            <el-icon class="empty_icon"><Download /></el-icon>
            <p>暂无下载任务</p>
          </div>
        </div>

        <template #footer>
          <el-button @click="showDownloadDialog = false">关闭</el-button>
        </template>
      </el-dialog>

      <!-- 上传任务管理对话框 -->
      <el-dialog
        v-model="showUploadDialog"
        title="上传管理"
        width="600px"
        :close-on-click-modal="true"
      >
        <div class="upload_manager_container">
          <!-- 正在上传的任务 -->
          <div v-if="activeUploadTasks.length > 0" class="upload_section">
            <h4 class="section_title">正在上传 ({{ activeUploadTasks.length }})</h4>
            <div class="upload_task_list">
              <div
                v-for="task in activeUploadTasks"
                :key="task.taskId"
                class="upload_task_item"
              >
                <div class="task_header">
                  <div class="file_info">
                    <el-icon class="file_icon"><Upload /></el-icon>
                    <span class="file_name" :title="task.fileName">{{ task.fileName }}</span>
                  </div>
                  <el-button
                    size="small"
                    type="danger"
                    @click="cancelUpload(task.taskId)"
                  >
                    取消
                  </el-button>
                </div>

                <div class="progress_info">
                  <!-- 分片上传进度条 -->
                  <div class="progress_section">
                    <div class="progress_label">
                      上传到面板: {{ formatSize(task.chunkUploadedSize) }} / {{ formatSize(task.chunkTotalSize) }}
                      ({{ task.chunkProgress.toFixed(1) }}%)
                    </div>
                    <el-progress
                      :percentage="task.chunkProgress"
                      :show-text="false"
                      :stroke-width="4"
                      status="success"
                    />
                  </div>

                  <!-- SFTP传输进度条 -->
                  <div class="progress_section">
                    <div class="progress_label">
                      <template v-if="task.stage === 'merging'">
                        合并文件中...
                      </template>
                      <template v-else-if="task.stage === 'transferring'">
                        传输到服务器: {{ formatSize(task.sftpUploadedSize) }} / {{ formatSize(task.sftpTotalSize) }}
                        ({{ task.sftpProgress.toFixed(1) }}%)
                      </template>
                      <template v-else>
                        传输到服务器: 0 B / {{ formatSize(task.sftpTotalSize) }} (0.0%)
                      </template>
                    </div>
                    <el-progress
                      :percentage="task.sftpProgress"
                      :show-text="false"
                      :stroke-width="4"
                      :status="task.stage === 'merging' ? 'warning' : ''"
                    />
                  </div>

                  <!-- 速度和时间信息 -->
                  <div class="progress_details">
                    <span class="progress_text">
                      总进度: {{ task.progress.toFixed(1) }}%
                    </span>
                    <span class="speed_text">
                      <template v-if="task.stage === 'merging'">
                        合并中...
                      </template>
                      <template v-else-if="task.stage === 'transferring' && task.speed > 0">
                        {{ formatSpeed(task.speed) }} · {{ formatTime(task.eta) }}
                      </template>
                      <template v-else-if="task.speed > 0">
                        {{ formatSpeed(task.speed) }} · {{ formatTime(task.eta) }}
                      </template>
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 已完成的任务 -->
          <div v-if="completedUploadTasks.length > 0" class="upload_section">
            <h4 class="section_title">已完成 ({{ completedUploadTasks.length }})</h4>
            <div class="upload_task_list">
              <div
                v-for="task in completedUploadTasks"
                :key="task.taskId"
                class="upload_task_item completed"
              >
                <div class="task_header">
                  <div class="file_info">
                    <el-icon class="file_icon success"><Check /></el-icon>
                    <span class="file_name" :title="task.fileName">{{ task.fileName }}</span>
                  </div>
                  <div class="task_actions">
                    <span class="completed_text">上传完成</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 失败的任务 -->
          <div v-if="failedUploadTasks.length > 0" class="upload_section">
            <h4 class="section_title">上传失败 ({{ failedUploadTasks.length }})</h4>
            <div class="upload_task_list">
              <div
                v-for="task in failedUploadTasks"
                :key="task.taskId"
                class="upload_task_item failed"
              >
                <div class="task_header">
                  <div class="file_info">
                    <el-icon class="file_icon error"><WarningFilled /></el-icon>
                    <span class="file_name" :title="task.fileName">{{ task.fileName }}</span>
                  </div>
                  <div class="task_actions">
                    <el-button
                      size="small"
                      type="primary"
                      @click="retryUpload(task)"
                    >
                      重试
                    </el-button>
                    <el-button
                      size="small"
                      type="danger"
                      @click="removeUploadTask(task.taskId)"
                    >
                      删除
                    </el-button>
                  </div>
                </div>
                <div class="error_info">
                  <span class="error_text">错误: {{ task.error }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- 无任务时的提示 -->
          <div v-if="!hasUploadTasks" class="no_tasks">
            <el-icon class="empty_icon"><Upload /></el-icon>
            <p>暂无上传任务</p>
          </div>
        </div>

        <template #footer>
          <div class="upload_dialog_footer">
            <el-button @click="clearCompletedTasks">清空已完成</el-button>
            <el-button @click="showUploadDialog = false">关闭</el-button>
          </div>
        </template>
      </el-dialog>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, getCurrentInstance, nextTick } from 'vue'
import { ArrowDown, ArrowLeft, Refresh, View, Hide, Edit, ArrowRight, HomeFilled, Check, Close as CloseIcon, Download, Upload, DocumentCopy, Loading, WarningFilled, Star, StarFilled, Delete } from '@element-plus/icons-vue'
import socketIo from 'socket.io-client'
import dirIcon from '@/assets/image/system/dir.png'
import linkIcon from '@/assets/image/system/link.png'
import fileIcon from '@/assets/image/system/file.png'
import unknowIcon from '@/assets/image/system/unknow.png'
import { useContextMenu } from '@/composables/useContextMenu'
import TextEditor from '@/components/text-editor/index.vue'
import ImagePreview from '@/components/image-preview/index.vue'

const props = defineProps({
  hostId: {
    type: String,
    required: true
  }
})

// 组件实例上下文
const { proxy: { $store, $message, $serviceURI, $messageBox } } = getCurrentInstance()

// 路径 & 隐藏文件显示
const currentPath = ref('/')
const SHOW_HIDDEN_KEY = 'easynode_show_hidden_files'
const showHidden = ref(JSON.parse(localStorage.getItem(SHOW_HIDDEN_KEY) ?? 'true'))
watch(showHidden, (val) => {
  localStorage.setItem(SHOW_HIDDEN_KEY, JSON.stringify(val))
  refresh()
})

// Socket & 列表
const socket = ref(null)
const token = computed(() => $store.token)
const loading = ref(false)

// 连接状态管理
const connectionStatus = ref('connecting') // connecting, connected, failed, reconnecting
const connectionError = ref('')

// 路径切换状态管理
const previousPath = ref('') // 用于错误回滚
const pendingPath = ref('') // 待确认的路径

const fileListRaw = ref([])

function getRank(item) {
  const isHidden = item.name.startsWith('.')
  const isDir = item.type === 'd'
  const isLink = item.type === 'l'
  if (isHidden && isDir) return 0 // hidden dir
  if (isDir && item.name === 'root') return 1 // root directory special
  if (isHidden) return 2 // hidden file
  if (isDir) return 3 // visible dir
  if (isLink) return 4 // link
  return 5 // regular file
}

const fileList = computed(() => {
  const base = showHidden.value ? fileListRaw.value.slice() : fileListRaw.value.filter(it => !it.name.startsWith('.'))
  return base.sort((a, b) => {
    const r = getRank(a) - getRank(b)
    if (r !== 0) return r
    return a.name.localeCompare(b.name)
  })
})
const selectedRows = ref([])
const tableRef = ref(null)

// 上传 & 新建 (Popover)
const showCreatePopover = ref(false)
const createType = ref('folder') // 'folder' | 'file'
const createName = ref('')
const createPopoverRef = ref(null) // Popover定位元素
const newBtnRef = ref(null)
const createInputRef = ref(null)

// 上下文菜单
const { showMenu } = useContextMenu()

// 下载相关状态
const showDownloadDialog = ref(false)
const downloadTasks = ref(new Map()) // taskId -> 下载任务信息

// 上传相关状态
const showUploadDialog = ref(false)
const uploadTasks = ref(new Map()) // taskId -> 上传任务信息
const uploadInputRef = ref(null) // 文件选择器引用
const uploadDirInputRef = ref(null) // 文件夹选择器引用

// 收藏相关状态
const favoriteList = ref([]) // 收藏列表

// 文本编辑器相关状态
const showTextEditor = ref(false)
const textEditorConfig = ref({
  filePath: '',
  fileName: '',
  fileSize: 0
})

// 图片预览相关状态
const showImagePreview = ref(false)
const imagePreviewConfig = ref({
  imageSrc: '',
  fileName: '',
  fileSize: 0,
  filePath: ''
})

const hasDownloadTasks = computed(() => downloadTasks.value.size > 0)

// 计算属性：正在进行的下载任务列表
const activeDownloadTasks = computed(() => {
  return Array.from(downloadTasks.value.values()).filter(task => task.status === 'downloading')
})

// 计算属性：已完成的下载任务列表
const completedDownloadTasks = computed(() => {
  return Array.from(downloadTasks.value.values()).filter(task => task.status === 'completed')
})

// 上传任务相关计算属性
const hasUploadTasks = computed(() => uploadTasks.value.size > 0)

// 计算属性：正在进行的上传任务列表
const activeUploadTasks = computed(() => {
  return Array.from(uploadTasks.value.values()).filter(task => task.status === 'uploading')
})

// 计算属性：已完成的上传任务列表
const completedUploadTasks = computed(() => {
  return Array.from(uploadTasks.value.values()).filter(task => task.status === 'completed')
})

// 计算属性：失败的上传任务列表
const failedUploadTasks = computed(() => {
  return Array.from(uploadTasks.value.values()).filter(task => task.status === 'failed')
})

// 计算属性：是否有收藏
const hasFavorites = computed(() => favoriteList.value.length > 0)

//----------------------------------
// 初始化
//----------------------------------
onMounted(() => {
  connectSftp()
})

onUnmounted(() => {
  if (socket.value) {
    socket.value.removeAllListeners()
    socket.value.close()
    socket.value = null
  }
  // 清空路径状态
  previousPath.value = ''
  pendingPath.value = ''
})

//----------------------------------
// Socket 连接 & 目录操作
//----------------------------------

const connectSftp = () => {
  const { io } = socketIo

  // 清理旧的socket连接
  if (socket.value) {
    socket.value.removeAllListeners()
    socket.value.close()
    socket.value = null
  }

  connectionStatus.value = connectionStatus.value === 'connected' ? 'reconnecting' : 'connecting'
  connectionError.value = ''
  loading.value = true

  socket.value = io($serviceURI, {
    path: '/sftp-v2',
    forceNew: true,
    reconnectionAttempts: 0 // 禁用socket.io自带的重连，我们自己控制
  })

  socket.value.on('connect', () => {
    socket.value.emit('ws_sftp', { hostId: props.hostId, token: token.value })

    socket.value.on('connect_success', ({ rootList, isRootUser, currentPath: serverCurrentPath }) => {
      fileListRaw.value = rootList
      // 根据用户权限设置正确的初始路径
      currentPath.value = serverCurrentPath || (isRootUser ? '/' : '~')
      // 清空路径状态
      previousPath.value = ''
      pendingPath.value = ''
      connectionStatus.value = 'connected'
      loading.value = false
      console.log('SFTP连接成功, 初始路径:', currentPath.value, ', 是否root用户:', isRootUser)
      // 获取收藏列表
      getFavoriteList()
    })

    socket.value.on('connect_fail', (msg) => {
      connectionStatus.value = 'failed'
      connectionError.value = msg
      loading.value = false
      // 清空路径状态
      previousPath.value = ''
      pendingPath.value = ''
    })

    socket.value.on('dir_ls', (dirLs, path) => {
      fileListRaw.value = dirLs
      loading.value = false

      // 确认路径切换成功
      if (path) {
        currentPath.value = path
        previousPath.value = '' // 清空之前的路径
        pendingPath.value = '' // 清空待确认路径
      }
    })

    socket.value.on('not_exists_dir', (msg) => {
      if (msg) $message.warning(msg)
      loading.value = false

      // 回滚到之前的路径
      if (previousPath.value) {
        currentPath.value = previousPath.value
        previousPath.value = '' // 清空
        pendingPath.value = '' // 清空
      }
    })

    socket.value.on('rename_success', () => {
      $message.success('重命名成功')
      loading.value = false
      cancelRename()
    })

    socket.value.on('rename_fail', (msg) => {
      $message.error(`重命名失败: ${ msg }`)
      loading.value = false
      cancelRename()
    })

    socket.value.on('delete_success', () => {
      $message.success('删除成功')
      loading.value = false
    })

    socket.value.on('delete_fail', (msg) => {
      $message.error(`删除失败: ${ msg }`)
      loading.value = false
    })

    socket.value.on('move_success', () => {
      $message.success('移动成功')
      loading.value = false
    })

    socket.value.on('move_fail', (msg) => {
      $message.error(`移动失败: ${ msg }`)
      loading.value = false
    })

    socket.value.on('copy_success', () => {
      $message.success('复制成功')
      loading.value = false
    })

    socket.value.on('copy_fail', (msg) => {
      $message.error(`复制失败: ${ msg }`)
      loading.value = false
    })

    socket.value.on('create_success', (msg) => {
      $message.success(msg || '创建成功')
      loading.value = false
      refresh()
    })

    socket.value.on('create_fail', (msg) => {
      $message.error(`创建失败: ${ msg }`)
      loading.value = false
    })

    socket.value.on('compress_success', (msg) => {
      $message.success(msg || '压缩成功')
      loading.value = false
      refresh()
    })

    socket.value.on('compress_fail', (msg) => {
      $message.error(`压缩失败: ${ msg }`)
      loading.value = false
    })

    socket.value.on('decompress_success', (msg) => {
      $message.success(msg || '解压成功')
      loading.value = false
      refresh()
    })

    socket.value.on('decompress_fail', (msg) => {
      $message.error(`解压失败: ${ msg }`)
      loading.value = false
    })

    // 收藏相关事件
    socket.value.on('favorites_list', (favorites) => {
      favoriteList.value = favorites
    })

    socket.value.on('favorite_added', (message) => {
      $message.success(message || '收藏成功')
      getFavoriteList()
      // 刷新文件列表以更新星标显示
      refresh()
    })

    socket.value.on('favorite_removed', (message) => {
      $message.success(message || '取消收藏成功')
      getFavoriteList()
      // 刷新文件列表以更新星标显示
      refresh()
    })

    socket.value.on('favorite_error', (message) => {
      $message.error(`收藏操作失败: ${ message }`)
    })

    // 软链接解析相关事件
    socket.value.on('symlink_resolved', ({ realPath, isDirectory, symlinkPath }) => {
      console.log('解析软链接成功:', realPath, isDirectory, symlinkPath)
      loading.value = false

      if (isDirectory) {
        // 软链接指向目录，导航到真实目录
        switchToPath(realPath, true)
        $message.success(`已跳转到软链接指向的目录: ${ realPath }`)
      } else {
        // 软链接指向文件，尝试打开文件
        const fileName = realPath.split('/').pop()

        // 检查是否为图片文件
        if (isImageFile(fileName)) {
          // 使用socket请求图片数据
          loading.value = true
          socket.value.emit('read_image', {
            filePath: realPath,
            fileSize: 0 // 软链接文件大小需要从服务端获取
          })
        } else if (isTextFile(fileName)) {
          // 检查是否为文本文件
          textEditorConfig.value = {
            filePath: realPath,
            fileName: fileName,
            fileSize: 0 // 软链接文件大小需要单独获取
          }
          showTextEditor.value = true
        } else {
          $message.info(`软链接指向文件: ${ realPath }，暂不支持在线预览`)
        }
      }
    })

    socket.value.on('symlink_resolve_error', ({ error, symlinkPath }) => {
      loading.value = false
      console.error('解析软链接失败:', error, symlinkPath)
      $message.error(`解析软链接失败: ${ error }`)
    })

    // 下载相关事件
    socket.value.on('download_started', ({ taskId, fileName }) => {
      const newTask = {
        taskId,
        fileName,
        progress: 0,
        downloadedSize: 0,
        totalSize: 0,
        speed: 0,
        eta: 0,
        status: 'downloading',
        startTime: Date.now()
      }
      downloadTasks.value.set(taskId, newTask)
      loading.value = false
      showDownloadDialog.value = true
    })

    socket.value.on('download_progress', ({ taskId, progress, downloadedSize, totalSize, speed, eta }) => {
      const task = downloadTasks.value.get(taskId)
      if (task) {
        task.progress = progress
        task.downloadedSize = downloadedSize
        task.totalSize = totalSize
        task.speed = speed
        task.eta = eta
      }
    })

    socket.value.on('download_ready', ({ taskId, fileName }) => {
      const task = downloadTasks.value.get(taskId)
      if (task) {
        task.status = 'completed'
        task.progress = 100
        task.downloadUrl = `/sftp-cache/${ taskId }/${ encodeURIComponent(fileName) }`
        downloadFile(task)
      }
    })

    socket.value.on('download_fail', (msg) => {
      $message.error(`下载失败: ${ msg }`)
      loading.value = false
      // 清理失败的任务
      for (const [taskId, task,] of downloadTasks.value) {
        if (task.status === 'downloading') {
          downloadTasks.value.delete(taskId)
          break
        }
      }
    })

    socket.value.on('download_cancelled', ({ taskId }) => {
      downloadTasks.value.delete(taskId)
    })

    // 上传相关事件
    socket.value.on('upload_started', ({ taskId, fileName }) => {
      const task = uploadTasks.value.get(taskId)
      if (task) {
        task.status = 'uploading'
        showUploadDialog.value = true
        $message.success(`开始上传: ${ fileName }`)
      }
    })

    socket.value.on('upload_progress', ({ taskId, chunkProgress, chunkUploadedSize, chunkTotalSize, sftpProgress, sftpUploadedSize, sftpTotalSize, speed, eta, stage }) => {
      const task = uploadTasks.value.get(taskId)
      if (task) {
        // 分片上传进度
        task.chunkProgress = chunkProgress || 0
        task.chunkUploadedSize = chunkUploadedSize || 0
        task.chunkTotalSize = chunkTotalSize || task.totalSize

        // SFTP传输进度
        task.sftpProgress = sftpProgress || 0
        task.sftpUploadedSize = sftpUploadedSize || 0
        task.sftpTotalSize = sftpTotalSize || task.totalSize

        // 其他信息
        task.speed = speed || 0
        task.eta = eta || 0
        task.stage = stage || 'uploading'

        // 计算总体进度（分片上传50% + SFTP传输50%）
        task.progress = (task.chunkProgress * 0.5) + (task.sftpProgress * 0.5)
      }
    })

    socket.value.on('upload_complete', ({ taskId, fileName }) => {
      const task = uploadTasks.value.get(taskId)
      if (task) {
        task.status = 'completed'
        task.progress = 100
        $message.success(`上传完成: ${ fileName }`)
        // 刷新文件列表
        refresh()
      }
    })

    socket.value.on('upload_fail', ({ taskId, error }) => {
      const task = uploadTasks.value.get(taskId)
      if (task) {
        task.status = 'failed'
        task.error = error
        $message.error(`上传失败: ${ error }`)
      }
    })

    socket.value.on('upload_cancelled', ({ taskId }) => {
      uploadTasks.value.delete(taskId)
    })

    // socket.value.on('upload_chunk_success', ({ taskId, chunkIndex }) => {
    //   // 分片上传成功，无需特殊处理
    // })

    socket.value.on('upload_chunk_fail', ({ taskId, chunkIndex, error }) => {
      const task = uploadTasks.value.get(taskId)
      if (task) {
        task.status = 'failed'
        task.error = `分片 ${ chunkIndex } 上传失败: ${ error }`
        $message.error(task.error)
      }
    })

    // SSH连接错误处理
    socket.value.on('shell_connection_error', ({ message, code }) => {
      console.error('SFTP连接shell终端错误：', message, 'Code:', code)
      connectionStatus.value = 'failed'
      connectionError.value = message
      loading.value = false
    })

    // 图片预览相关事件
    socket.value.on('image_content', ({ imageUrl, filePath, fileName, fileSize }) => {
      console.log('收到图片URL:', { filePath, fileName, fileSize, imageUrl })

      if (!imageUrl) {
        $message.error('图片URL为空')
        loading.value = false
        return
      }

      // 更新图片预览配置
      imagePreviewConfig.value = {
        imageSrc: imageUrl,
        fileName: fileName || filePath.split('/').pop(),
        fileSize,
        filePath
      }

      // 显示图片预览
      showImagePreview.value = true
      loading.value = false
    })

    socket.value.on('image_read_error', ({ error, filePath }) => {
      console.error('图片读取错误:', error, filePath)
      $message.error(`图片预览失败: ${ error }`)
      loading.value = false
    })
  })

  // 添加断开连接监听，实现自动重连
  socket.value.on('disconnect', (reason) => {
    console.warn('SFTP连接断开:', reason)
    // 清空路径状态
    previousPath.value = ''
    pendingPath.value = ''

    if (connectionStatus.value === 'connected') {
      // 只有在之前连接成功的情况下才自动重连
      setTimeout(() => {
        if (connectionStatus.value !== 'connected') {
          connectSftp()
        }
      }, 2000) // 2秒后重连
    }
  })

  socket.value.on('connect_error', (err) => {
    console.error('sftp-v2 websocket 连接错误：', err)
    connectionStatus.value = 'failed'
    connectionError.value = 'WebSocket连接失败，请检查网络或服务器状态'
    loading.value = false
    // 清空路径状态
    previousPath.value = ''
    pendingPath.value = ''
  })
}

const openDir = (path = currentPath.value, tips = true) => {
  if (!socket.value) return
  socket.value.emit('open_dir', path, tips)
  loading.value = true
}

// 安全的路径切换函数
const switchToPath = (newPath, tips = true) => {
  if (!socket.value) return

  // 保存当前路径用于可能的回滚
  previousPath.value = currentPath.value
  pendingPath.value = newPath

  // 发送路径切换请求
  socket.value.emit('open_dir', newPath, tips)
  loading.value = true
}

//----------------------------------
// 文件操作相关（占位实现）
//----------------------------------
const refresh = () => {
  // 刷新当前目录，不需要路径验证，直接使用openDir
  openDir(currentPath.value, false)
}

const goParent = () => {
  const path = currentPath.value

  // 已经在根目录或home目录，无法再向上
  if (path === '/' || path === '~') return

  let newPath

  // 处理绝对路径
  if (path.startsWith('/')) {
    const arr = path.split('/').filter(Boolean)
    arr.pop()
    newPath = arr.length === 0 ? '/' : '/' + arr.join('/')
  }
  // 处理相对路径（从~开始）
  else if (path.startsWith('~')) {
    if (path === '~' || path === '~/') {
      return // 已经在home目录
    }
    const relativePart = path.substring(2) // 去掉 '~/' 前缀
    const arr = relativePart.split('/').filter(Boolean)
    arr.pop()
    newPath = arr.length === 0 ? '~' : '~/' + arr.join('/')
  }
  // 其他情况
  else {
    const arr = path.split('/').filter(Boolean)
    arr.pop()
    newPath = arr.length === 0 ? '/' : '/' + arr.join('/')
  }

  // 使用安全的路径切换
  switchToPath(newPath)
}

const toggleHidden = () => {
  showHidden.value = !showHidden.value
}

//================= 路径面包屑 & 编辑 ==================
const isEditingPath = ref(false)
const pathInput = ref('')

const breadcrumb = computed(() => {
  const path = currentPath.value

  // 处理特殊路径
  if (path === '/' || path === '~') {
    return [path === '/' ? '/' : '~',]
  }

  // 处理绝对路径
  if (path.startsWith('/')) {
    const segs = path.split('/').filter(Boolean)
    return ['/', ...segs,]
  }

  // 处理相对路径（从~开始）
  if (path.startsWith('~')) {
    if (path === '~') return ['~',]
    const segs = path.substring(2).split('/').filter(Boolean) // 去掉 '~/' 前缀
    return ['~', ...segs,]
  }

  // 其他情况，按原来的逻辑处理
  const segs = path.split('/').filter(Boolean)
  return ['/', ...segs,]
})

const breadcrumbRef = ref(null)

function scrollToEnd() {
  nextTick(() => {
    const el = breadcrumbRef.value
    if (el) el.scrollLeft = el.scrollWidth
  })
}

watch(currentPath, () => scrollToEnd())

const handleBreadcrumb = (idx) => {
  const segments = breadcrumb.value
  let newPath

  if (idx === 0) {
    // 点击第一个段（根目录或home目录）
    newPath = segments[0] // '/' 或 '~'
  } else {
    // 点击其他段
    if (segments[0] === '/') {
      // 绝对路径
      const segs = segments.slice(1, idx + 1)
      newPath = '/' + segs.join('/')
    } else if (segments[0] === '~') {
      // 相对路径（从home开始）
      if (idx === 1) {
        newPath = '~/' + segments[1]
      } else {
        const segs = segments.slice(1, idx + 1)
        newPath = '~/' + segs.join('/')
      }
    } else {
      // 其他情况，按原来的逻辑处理
      const segs = segments.slice(1, idx + 1)
      newPath = '/' + segs.join('/')
    }
  }

  // 使用安全的路径切换
  switchToPath(newPath, true)
}

const toggleEditPath = () => {
  isEditingPath.value = true
  pathInput.value = currentPath.value
  nextTick(() => {
    const inputEl = document.querySelector('.path_input input')
    inputEl && inputEl.focus()
  })
}

const confirmPathInput = () => {
  if (!pathInput.value) return
  isEditingPath.value = false
  // 使用安全的路径切换
  switchToPath(pathInput.value, true)
}

const cancelEditPath = () => {
  isEditingPath.value = false
}

const copyCurrentPath = () => {
  navigator.clipboard.writeText(currentPath.value).then(() => {
    $message.success('路径已复制')
  }).catch(() => {
    $message.error('复制失败')
  })
}

const handleUpload = (type) => {
  if (type === 'file') {
    // 触发文件选择器
    uploadInputRef.value?.click()
  } else if (type === 'folder') {
    // 触发文件夹选择器
    uploadDirInputRef.value?.click()
  }
}

const handleNew = (type) => {
  createType.value = type
  createName.value = ''
  showCreatePopover.value = true

  // 等待 Popover 完全显示后再聚焦
  setTimeout(() => {
    if (createInputRef.value) {
      createInputRef.value.focus()
    }
  }, 100)
}

const confirmCreate = () => {
  if (!createName.value.trim()) return
  if (!socket.value) return

  loading.value = true
  showCreatePopover.value = false

  socket.value.emit('create_item', {
    dirPath: currentPath.value,
    name: createName.value.trim(),
    type: createType.value // 'folder' or 'file'
  })
}

//----------------------------------
// 列表事件
//----------------------------------
const onRowClick = (row) => {
  // 文件夹 → 进入下级
  if (row.type === 'd') {
    let newPath
    const currentPathValue = currentPath.value

    if (currentPathValue === '/') {
      newPath = `/${ row.name }`
    } else if (currentPathValue === '~') {
      newPath = `~/${ row.name }`
    } else if (currentPathValue.endsWith('/')) {
      newPath = `${ currentPathValue }${ row.name }`
    } else {
      newPath = `${ currentPathValue }/${ row.name }`
    }

    // 清理多余的斜杠
    newPath = newPath.replace(/\/+/g, '/')

    // 使用安全的路径切换
    switchToPath(newPath, true)
  } else if (row.type === 'l') {
    // 软链接 → 解析真实路径
    handleSymlinkClick(row)
  } else {
    // 文件 → 根据文件类型处理
    handleFileOpen(row)
  }
}

const onSelectionChange = (rows) => {
  selectedRows.value = rows
}

const isArchiveFile = (filename) => {
  return /(\.zip|\.tar\.gz|\.tgz|\.tar|\.rar)$/i.test(filename)
}

// 判断是否为图片文件
const isImageFile = (filename) => {
  const imageExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif',
  ]

  // 获取文件扩展名
  const ext = filename.split('.').pop()?.toLowerCase()

  // 检查是否在图片扩展名列表中
  return ext && imageExtensions.includes(ext)
}

// 判断是否为文本文件
const isTextFile = (filename) => {
  const textExtensions = [
    'txt', 'log', 'md', 'markdown', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'config',
    'js', 'ts', 'jsx', 'tsx', 'vue', 'html', 'css', 'scss', 'sass', 'less', 'styl',
    'py', 'java', 'cpp', 'c', 'h', 'hpp', 'cs', 'php', 'rb', 'go', 'rs', 'swift', 'kt',
    'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
    'sql', 'dockerfile', 'makefile', 'cmake', 'gradle', 'properties',
    'gitignore', 'gitattributes', 'editorconfig', 'prettierrc', 'eslintrc', 'tsconfig',
  ]

  // 获取文件扩展名
  const ext = filename.split('.').pop()?.toLowerCase()

  // 检查是否在文本扩展名列表中
  if (ext && textExtensions.includes(ext)) {
    return true
  }

  // 检查无扩展名的常见文本文件
  const commonTextFiles = [
    'readme', 'license', 'changelog', 'todo', 'authors', 'contributors',
    'makefile', 'dockerfile', 'gemfile', 'rakefile', 'gulpfile', 'gruntfile',
  ]

  return commonTextFiles.includes(filename.toLowerCase())
}

// 处理文件打开
const handleFileOpen = (row) => {
  // 检查是否为图片文件
  if (isImageFile(row.name)) {
    // 检查图片文件大小限制（10MB）
    const maxImageSize = 10 * 1024 * 1024 // 10MB
    if (row.size > maxImageSize) {
      $message.warning(`图片过大（${ sizeFormatter(row, null, row.size) }），仅支持预览小于10MB的图片`)
      return
    }

    // 打开图片预览
    let fullPath
    const currentPathValue = currentPath.value

    if (currentPathValue === '/' || currentPathValue === '~') {
      fullPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
    } else {
      fullPath = `${ currentPathValue }/${ row.name }`
    }

    // 清理路径
    fullPath = fullPath.replace(/\/+/g, '/')

    // 使用socket请求图片数据
    loading.value = true
    socket.value.emit('read_image', {
      filePath: fullPath,
      fileSize: row.size
    })

    return
  }

  // 检查文件大小限制（1MB）
  const maxFileSize = 1024 * 1024 // 1MB
  if (row.size > maxFileSize) {
    $message.warning(`文件过大（${ sizeFormatter(row, null, row.size) }），仅支持编辑小于1MB的文件`)
    return
  }

  // 检查是否为文本文件
  if (isTextFile(row.name)) {
    // 打开文本编辑器
    let fullPath
    const currentPathValue = currentPath.value

    if (currentPathValue === '/' || currentPathValue === '~') {
      fullPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
    } else {
      fullPath = `${ currentPathValue }/${ row.name }`
    }

    // 清理路径
    fullPath = fullPath.replace(/\/+/g, '/')

    textEditorConfig.value = {
      filePath: fullPath,
      fileName: row.name,
      fileSize: row.size
    }

    showTextEditor.value = true
  } else {
    // 非文本文件，暂时提示
    $message.info(`文件 "${ row.name }" 暂不支持在线预览`)
  }
}

// 处理软链接点击
const handleSymlinkClick = (row) => {
  if (!socket.value) return

  loading.value = true
  let symlinkPath
  const currentPathValue = currentPath.value

  if (currentPathValue === '/' || currentPathValue === '~') {
    symlinkPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
  } else {
    symlinkPath = `${ currentPathValue }/${ row.name }`
  }

  // 清理路径
  symlinkPath = symlinkPath.replace(/\/+/g, '/')

  // 请求解析软链接的真实路径
  socket.value.emit('resolve_symlink', {
    symlinkPath: symlinkPath
  })
}

// ============== Rename ==============
const editingRow = ref(null)
const editingName = ref('')

const isEditing = (row) => editingRow.value === row

const startRename = (row) => {
  editingRow.value = row
  editingName.value = row.name
  nextTick(() => {
    const inputEl = document.querySelector('.rename_input input')
    inputEl && inputEl.focus()
  })
}

const confirmRename = (row) => {
  const newName = editingName.value.trim()
  if (!newName || newName === row.name) return cancelRename()
  loading.value = true
  socket.value.emit('rename', { dirPath: currentPath.value, oldName: row.name, newName })
}

const cancelRename = () => {
  editingRow.value = null
  editingName.value = ''
}

function getIcon(type) {
  return ({ d: dirIcon, l: linkIcon, '-': fileIcon })[type] || unknowIcon
}

const onRowContextMenu = (row, _column, event) => {
  event.preventDefault()
  // 自动切换当前行的选中状态，确保右键操作作用于选中集合
  if (!selectedRows.value.includes(row)) {
    tableRef.value.clearSelection()
    tableRef.value.toggleRowSelection(row, true)
  }

  // 检查是否为多选状态
  const isMultiSelected = selectedRows.value.length > 1

  const items = []

  // 始终显示下载菜单（支持单文件和多文件下载）
  items.push({
    label: '下载',
    onClick: () => handleDownload(row)
  })

  items.push(
    {
      label: '复制到...',
      onClick: () => handleCopy(row)
    },
    {
      label: '移动到...',
      onClick: () => handleMove(row)
    },
    {
      label: '压缩',
      onClick: () => handleCompress(row)
    }
  )

  // 解压功能只在单选且为压缩文件时显示
  if (!isMultiSelected && row.type === '-' && isArchiveFile(row.name)) {
    items.push({
      label: '解压',
      onClick: () => handleDecompress(row)
    })
  }

  items.push({
    label: '删除',
    onClick: () => handleDelete(row)
  })

  // 重命名只在单选时显示
  if (!isMultiSelected) {
    items.push({
      label: '重命名',
      onClick: () => startRename(row)
    })
  }

  items.push({
    label: '复制路径',
    onClick: () => {
      let fullPath
      const currentPathValue = currentPath.value

      if (currentPathValue === '/' || currentPathValue === '~') {
        fullPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
      } else {
        fullPath = `${ currentPathValue }/${ row.name }`
      }

      // 清理路径
      fullPath = fullPath.replace(/\/+/g, '/')

      navigator.clipboard.writeText(fullPath)
      $message.success('已复制路径')
    }
  })

  showMenu(event, items)
}

//----------------------------------
// 格式化器
//----------------------------------

function sizeFormatter(row, column, cellValue) {
  const bytes = Number(cellValue)
  if (isNaN(bytes) || bytes === 0) return '-'
  const KB = 1024, MB = KB * 1024, GB = MB * 1024, TB = GB * 1024
  if (bytes < MB) return (bytes / KB).toFixed(1) + ' KB'
  if (bytes < GB) return (bytes / MB).toFixed(1) + ' MB'
  if (bytes < TB) return (bytes / GB).toFixed(1) + ' GB'
  return (bytes / TB).toFixed(1) + ' TB'
}

function timeFormatter(row, column, cellValue) {
  if (!cellValue) return ''
  const date = new Date(Number(cellValue))
  const pad = (n) => n.toString().padStart(2, '0')
  const Y = date.getFullYear()
  const M = pad(date.getMonth() + 1)
  const D = pad(date.getDate())
  const h = pad(date.getHours())
  const m = pad(date.getMinutes())
  const s = pad(date.getSeconds())
  return `${ Y }-${ M }-${ D } ${ h }:${ m }:${ s }`
}

const handleDelete = (row) => {
  const targets = selectedRows.value.length > 1 && selectedRows.value.includes(row) ? selectedRows.value : [row,]

  // 格式化文件名，长文件名进行截断
  const formatFileName = (name) => {
    if (name.length <= 50) return name
    return name.substring(0, 25) + '...' + name.substring(name.length - 22)
  }

  const namesStr = targets.map(t => formatFileName(t.name)).join('\n')
  const fileCount = targets.length

  const message = fileCount === 1
    ? `确认删除以下文件(夹)：\n${ namesStr }`
    : `确认删除以下 ${ fileCount } 个文件(夹)：\n${ namesStr }`

  $messageBox.confirm(message, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'warning',
    customClass: 'delete_confirm_dialog'
  }).then(() => {
    loading.value = true
    socket.value.emit('delete_batch', { dirPath: currentPath.value, targets: targets.map(t=>({ name:t.name, type:t.type })) })
  })
}

const handleMove = (row) => {
  const targets = selectedRows.value.length > 1 && selectedRows.value.includes(row) ? selectedRows.value : [row,]
  $messageBox.prompt('', '移动到...', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    inputType: 'text',
    inputValue: currentPath.value === '/' ? '/' : currentPath.value + '/',
    inputPlaceholder: '目标路径',
    inputValidator: (v)=> !!v || '请输入目标路径'
  }).then(({ value }) => {
    const destDir = value.trim()
    if (!destDir) return
    loading.value = true
    if (targets.length === 1) {
      const t = targets[0]
      socket.value.emit('move', { dirPath: currentPath.value, destDir, name: t.name })
    } else {
      socket.value.emit('move_batch', { dirPath: currentPath.value, destDir, targets: targets.map(t=>({ name:t.name })) })
    }
  })
}

const handleCopy = (row) => {
  const targets = selectedRows.value.length > 1 && selectedRows.value.includes(row) ? selectedRows.value : [row,]
  $messageBox.prompt('', '复制到...', {
    inputType: 'text',
    inputValue: currentPath.value === '/' ? '/' : currentPath.value + '/',
    inputPlaceholder: '目标路径',
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    inputValidator: (v)=> !!v || '请输入目标路径'
  }).then(({ value }) => {
    const destDir = value.trim()
    if (!destDir) return
    loading.value = true
    socket.value.emit('copy_server_batch', { dirPath: currentPath.value, destDir, targets: targets.map(t=>({ name:t.name })) })
  })
}

const handleCompress = (row) => {
  const targets = selectedRows.value.length > 1 && selectedRows.value.includes(row) ? selectedRows.value : [row,]
  const defaultName = targets.length === 1 ?
    `${ targets[0].name }.tar.gz` :
    `archive-${ Date.now() }.tar.gz`

  $messageBox.prompt('', '压缩文件', {
    inputType: 'text',
    inputValue: defaultName,
    inputPlaceholder: '压缩文件名（建议以.tar.gz结尾）',
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    inputValidator: (v) => !!v?.trim() || '请输入压缩文件名'
  }).then(({ value }) => {
    const archiveName = value.trim()
    if (!archiveName) return

    loading.value = true
    socket.value.emit('compress_files', {
      dirPath: currentPath.value,
      targets: targets.map(t => ({ name: t.name, type: t.type })),
      archiveName
    })
  })
}

const handleDecompress = (row) => {
  // 解压功能只对单个压缩文件有效
  if (row.type !== '-' || !isArchiveFile(row.name)) {
    $message.error('只能解压压缩文件')
    return
  }

  // 获取文件名（去掉扩展名）用于创建同名文件夹
  const baseName = row.name.replace(/\.(tar\.gz|tgz|tar|zip)$/i, '')

  $messageBox.confirm('', '选择解压方式', {
    confirmButtonText: '解压到当前文件夹',
    cancelButtonText: '解压到同名文件夹',
    message: `文件: ${ row.name }\n\n`,
    type: 'question',
    showCancelButton: true,
    cancelButtonClass: 'el-button--primary',
    confirmButtonClass: 'el-button--success'
  }).then(() => {
    // 解压到当前文件夹
    loading.value = true
    socket.value.emit('decompress_file', {
      dirPath: currentPath.value,
      fileName: row.name,
      mode: 'current'
    })
  }).catch(() => {
    // 解压到同名文件夹
    loading.value = true
    socket.value.emit('decompress_file', {
      dirPath: currentPath.value,
      fileName: row.name,
      mode: 'folder',
      folderName: baseName
    })
  })
}

// 下载功能
const handleDownload = (row) => {
  // 支持单文件和多文件下载
  const targets = selectedRows.value.length > 1 && selectedRows.value.includes(row)
    ? selectedRows.value.map(r => ({ name: r.name, type: r.type }))
    : [{ name: row.name, type: row.type },]

  loading.value = true
  socket.value.emit('download_request', {
    dirPath: currentPath.value,
    targets
  })
}

// 取消下载
const cancelDownload = (taskId) => {
  if (taskId) {
    socket.value.emit('download_cancel', { taskId })
  }
}

// 显示下载任务管理器
const showDownloadManager = () => {
  showDownloadDialog.value = true
}

// 显示上传任务管理器
const showUploadManager = () => {
  showUploadDialog.value = true
}

// 手动下载文件
const downloadFile = (task) => {
  if (task.downloadUrl) {
    window.open(task.downloadUrl, '_blank')
    $message.success(`开始下载: ${ task.fileName }`)
  }
}

// 格式化文件大小
const formatSize = (bytes) => {
  if (!bytes || bytes === 0) return '0 B'
  const KB = 1024, MB = KB * 1024, GB = MB * 1024, TB = GB * 1024
  if (bytes < KB) return bytes + ' B'
  if (bytes < MB) return (bytes / KB).toFixed(1) + ' KB'
  if (bytes < GB) return (bytes / MB).toFixed(1) + ' MB'
  if (bytes < TB) return (bytes / GB).toFixed(1) + ' GB'
  return (bytes / TB).toFixed(1) + ' TB'
}

// 格式化速度
const formatSpeed = (bytesPerSec) => {
  return formatSize(bytesPerSec) + '/s'
}

// 格式化时间
const formatTime = (seconds) => {
  if (!seconds || seconds <= 0) return '计算中...'
  if (seconds < 60) return Math.round(seconds) + ' 秒'
  if (seconds < 3600) return Math.round(seconds / 60) + ' 分钟'
  return Math.round(seconds / 3600) + ' 小时'
}

// 收藏相关功能
const isFavorited = (row) => {
  let fullPath
  const currentPathValue = currentPath.value

  if (currentPathValue === '/' || currentPathValue === '~') {
    fullPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
  } else {
    fullPath = `${ currentPathValue }/${ row.name }`
  }

  // 清理路径
  fullPath = fullPath.replace(/\/+/g, '/')

  return favoriteList.value.some(fav => fav.path === fullPath)
}

const toggleFavorite = (row) => {
  if (!socket.value) return

  let fullPath
  const currentPathValue = currentPath.value

  if (currentPathValue === '/' || currentPathValue === '~') {
    fullPath = `${ currentPathValue === '/' ? '' : currentPathValue }/${ row.name }`
  } else {
    fullPath = `${ currentPathValue }/${ row.name }`
  }

  // 清理路径
  fullPath = fullPath.replace(/\/+/g, '/')

  const isCurrentlyFavorited = isFavorited(row)

  if (isCurrentlyFavorited) {
    // 取消收藏
    socket.value.emit('remove_favorite', {
      hostId: props.hostId,
      path: fullPath
    })
  } else {
    // 添加收藏
    socket.value.emit('add_favorite', {
      hostId: props.hostId,
      path: fullPath,
      name: row.name,
      type: row.type === 'd' ? 'folder' : 'file'
    })
  }
}

const getFavoriteList = () => {
  if (!socket.value) return
  socket.value.emit('get_favorites', { hostId: props.hostId })
}

const removeFavorite = (favoriteItem) => {
  if (!socket.value) return
  socket.value.emit('remove_favorite', {
    hostId: props.hostId,
    path: favoriteItem.path
  })
}

const navigateToFavorite = (favorite) => {
  if (favorite.type === 'folder') {
    // 导航到文件夹
    switchToPath(favorite.path, true)
  } else {
    // 文件：检查文件类型
    if (isImageFile(favorite.name)) {
      // 图片文件：直接打开预览
      loading.value = true
      socket.value.emit('read_image', {
        filePath: favorite.path,
        fileSize: 0 // 收藏中没有保存大小信息，从服务端获取
      })
    } else if (isTextFile(favorite.name)) {
      // 文本文件：直接打开编辑器
      textEditorConfig.value = {
        filePath: favorite.path,
        fileName: favorite.name,
        fileSize: 0
      }

      // 先切换到文件所在目录，然后打开编辑器
      const dirPath = favorite.path.substring(0, favorite.path.lastIndexOf('/')) || '/'
      switchToPath(dirPath, true)
      showTextEditor.value = true
    } else {
      // 其他文件：导航到文件所在目录
      const dirPath = favorite.path.substring(0, favorite.path.lastIndexOf('/')) || '/'
      switchToPath(dirPath, true)
    }
  }
}

// 文本文件保存成功回调
const onTextFileSaved = () => {
  refresh()
  showTextEditor.value = false
}

// 图片下载处理
const onImageDownload = (imageData) => {
  // 直接下载图片文件
  const { fileName, filePath } = imageData
  const targets = [{ name: fileName, type: '-' },]

  loading.value = true
  const currentPathValue = filePath.substring(0, filePath.lastIndexOf('/')) || '/'

  socket.value.emit('download_request', {
    dirPath: currentPathValue,
    targets
  })
}

// 上传相关功能
const handleFileSelect = (event) => {
  const files = Array.from(event.target.files)
  if (files.length === 0) return

  console.log('选择的文件:', files)

  // 检查是否有正在进行的任务
  if (activeUploadTasks.value.length > 0) {
    $message.warning('请等待当前上传任务完成后再添加新任务')
    event.target.value = ''
    return
  }

  // 开始上传所有选中的文件
  files.forEach(file => {
    startFileUpload(file)
  })

  // 重置input value，允许选择相同文件
  event.target.value = ''
}

const handleDirSelect = (event) => {
  const files = Array.from(event.target.files)
  if (files.length === 0) return

  console.log('选择的文件夹:', files)

  // 检查是否有正在进行的任务
  if (activeUploadTasks.value.length > 0) {
    $message.warning('请等待当前上传任务完成后再添加新任务')
    event.target.value = ''
    return
  }

  // 开始上传文件夹中的所有文件
  files.forEach(file => {
    startFileUpload(file, file.webkitRelativePath)
  })

  // 重置input value，允许选择相同文件夹
  event.target.value = ''
}

// 开始文件上传
const startFileUpload = (file, relativePath = null) => {
  // 生成任务ID
  const taskId = Date.now() + '-' + Math.random().toString(36).slice(2)

  // 确定目标路径
  let targetPath
  if (relativePath) {
    // 文件夹上传：保持相对路径结构
    targetPath = currentPath.value === '/'
      ? `/${ relativePath }`
      : `${ currentPath.value }/${ relativePath }`
  } else {
    // 单文件上传：直接放到当前目录
    targetPath = currentPath.value === '/'
      ? `/${ file.name }`
      : `${ currentPath.value }/${ file.name }`
  }

  // 创建上传任务
  const uploadTask = {
    taskId,
    fileName: file.name,
    originalFile: file,
    targetPath,

    // 总体进度
    progress: 0,

    // 分片上传进度
    chunkProgress: 0,
    chunkUploadedSize: 0,
    chunkTotalSize: file.size,

    // SFTP传输进度
    sftpProgress: 0,
    sftpUploadedSize: 0,
    sftpTotalSize: file.size,

    // 其他属性
    totalSize: file.size,
    speed: 0,
    eta: 0,
    status: 'pending',
    stage: 'uploading',
    startTime: Date.now(),
    error: null
  }

  uploadTasks.value.set(taskId, uploadTask)

  // 开始上传
  performFileUpload(uploadTask)
}

// 执行文件上传
const performFileUpload = async (task) => {
  try {
    if (!socket.value) {
      throw new Error('WebSocket连接未建立')
    }

    // 检查文件大小限制 (1GB)
    const maxFileSize = 1024 * 1024 * 1024 // 1GB
    if (task.totalSize > maxFileSize) {
      throw new Error(`文件过大（${ formatSize(task.totalSize) }），单个文件不能超过1GB`)
    }

    // 发送上传开始事件
    socket.value.emit('upload_start', {
      taskId: task.taskId,
      fileName: task.fileName,
      fileSize: task.totalSize,
      targetPath: task.targetPath
    })

    // 读取文件并分片上传
    const reader = new FileReader()
    reader.onload = async (e) => {
      const arrayBuffer = e.target.result
      const chunkSize = 512 * 1024 // 512KB per chunk
      const totalChunks = Math.ceil(arrayBuffer.byteLength / chunkSize)

      console.log(`开始分片上传: ${ task.fileName }, 总分片数: ${ totalChunks }`)

      // 分片上传
      for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize
        const end = Math.min(start + chunkSize, arrayBuffer.byteLength)
        const chunk = arrayBuffer.slice(start, end)

        // 发送分片
        socket.value.emit('upload_chunk', {
          taskId: task.taskId,
          chunkIndex: i,
          chunkData: chunk,
          totalChunks,
          isLastChunk: i === totalChunks - 1
        })

        // 等待分片上传确认
        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => {
            reject(new Error('分片上传超时'))
          }, 30000) // 30秒超时

          const handleSuccess = ({ taskId: responseTaskId, chunkIndex }) => {
            if (responseTaskId === task.taskId && chunkIndex === i) {
              clearTimeout(timeout)
              socket.value.off('upload_chunk_success', handleSuccess)
              socket.value.off('upload_chunk_fail', handleFail)
              resolve()
            }
          }

          const handleFail = ({ taskId: responseTaskId, chunkIndex, error }) => {
            if (responseTaskId === task.taskId && chunkIndex === i) {
              clearTimeout(timeout)
              socket.value.off('upload_chunk_success', handleSuccess)
              socket.value.off('upload_chunk_fail', handleFail)
              reject(new Error(error))
            }
          }

          socket.value.on('upload_chunk_success', handleSuccess)
          socket.value.on('upload_chunk_fail', handleFail)
        })
      }

      console.log(`分片上传完成: ${ task.fileName }`)
    }

    reader.onerror = () => {
      throw new Error('文件读取失败')
    }

    reader.readAsArrayBuffer(task.originalFile)

  } catch (error) {
    console.error('上传文件失败:', error)
    // 直接使用传入的task参数，无需重新获取
    task.status = 'failed'
    task.error = error.message
    $message.error(`上传失败: ${ error.message }`)
  }
}

// 上传任务管理函数
const cancelUpload = (taskId) => {
  const task = uploadTasks.value.get(taskId)
  if (task && task.status === 'uploading') {
    // 通知服务器取消上传
    socket.value?.emit('upload_cancel', { taskId })

    // 删除本地任务
    uploadTasks.value.delete(taskId)
  }
}

const retryUpload = (task) => {
  if (task.originalFile) {
    // 删除失败的任务
    uploadTasks.value.delete(task.taskId)

    // 重新开始上传
    startFileUpload(task.originalFile, task.targetPath.includes('/') ? task.targetPath.split('/').slice(0, -1).join('/') : null)
    $message.info('重新开始上传...')
  }
}

const removeUploadTask = (taskId) => {
  uploadTasks.value.delete(taskId)
}

const clearCompletedTasks = () => {
  const completedTasks = Array.from(uploadTasks.value.entries())
    .filter(([_, task,]) => task.status === 'completed')

  completedTasks.forEach(([taskId,]) => {
    uploadTasks.value.delete(taskId)
  })

  if (completedTasks.length > 0) {
    $message.success(`已清空 ${ completedTasks.length } 个完成任务`)
  }
}
</script>

<style lang="scss" scoped>
.sftp_v2_container {
  display: flex;
  flex-direction: column;
  height: 100%;

  .tool_bar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 10px;
    border-bottom: 1px solid var(--el-border-color);
  }

  .path_bar {
    height: 30px;
    padding: 0 10px;
    display: flex;
    align-items: center;
    border-bottom: 1px solid var(--el-border-color);

    .breadcrumb_wrap {
      line-height: 30px;
      flex: 1;
      display: flex;
      align-items: center;
      white-space: nowrap;
      overflow-x: auto;
      overflow-y: hidden;
      -ms-overflow-style: none; /* IE/Edge */
      scrollbar-width: none; /* Firefox */
      &::-webkit-scrollbar { display: none; }

      .breadcrumb_seg {
        cursor: pointer;
        user-select: none;
        display: flex;
        align-items: center;
        color: var(--el-color-primary);
        & > span {
          margin-top: -2px;
        }
        .separator {
          margin: 0 2px;
          width: 14px;
          height: 14px;
          color: var(--el-text-color-regular);
        }
        svg {
          width: 16px;
          height: 16px;
        }
      }
    }

    .path_input {
      flex: 1;
    }
    .action_icon {
      cursor: pointer;
      font-size: 16px;
      margin-left: 12px;

      &:first-of-type {
        margin: 0 8px 0 0;
      }

      &:hover {
        color: var(--el-color-primary);
      }

      &.download_icon {
        color: var(--el-color-success);
        animation: pulse 1.5s ease-in-out infinite;
      }

      &.upload_icon {
        color: var(--el-color-success);
        animation: pulse 1.5s ease-in-out infinite;
      }
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.6; }
    }
  }

  .file_table {
    flex: 1;
    min-width: 0; // 防止表格撑宽
    overflow: auto;
  }

  .file_name_cell {
    display: flex;
    align-items: center;
    cursor: pointer;
    position: relative;
    min-width: 0; // 允许flex子元素缩小

    .file_icon {
      width: 16px;
      height: 16px;
      margin-right: 4px;
      flex-shrink: 0; // 图标不缩小
    }
    .file_name {
      color: var(--el-color-primary);
      flex: 1;
      min-width: 0; // 允许文本缩小
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      padding-right: 18px; // 为星标留出空间
      user-select: none;
    }
    .rename_input {
      width: 120px;
      margin-right: 4px;
    }
    .rename_icon {
      cursor: pointer;
      margin-left: 2px;
      font-size: 14px;
      color: var(--el-color-success);
      &:last-child { color: var(--el-color-danger); }
    }
    .star_icon {
      position: absolute;
      right: -4px;
      cursor: pointer;
      font-size: 14px;
      color: var(--el-color-warning);
      flex-shrink: 0; // 星标不缩小
      opacity: 0; // 默认隐藏
      transition: opacity 0.2s ease; // 平滑过渡

      // 已收藏的文件始终显示星标
      &.favorited {
        opacity: 1;
      }
    }

    // 鼠标悬停时显示星标
    &:hover .star_icon {
      opacity: 1;
    }
  }

  .sftp_popover_actions {
    margin-top: 12px;
    text-align: right;
  }

  // 连接状态样式
  .connection_status {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100%;
    min-height: 300px;

    .status_connecting,
    .status_reconnecting {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 12px;
      color: var(--el-color-primary);

      .el-icon {
        font-size: 32px;
      }

      span {
        font-size: 16px;
      }
    }

    .status_failed {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 16px;
      max-width: 400px;
      text-align: center;

      .error_icon {
        font-size: 48px;
        color: var(--el-color-danger);
      }

      .error_content {
        h3 {
          margin: 0 0 8px 0;
          font-size: 18px;
          color: var(--el-text-color-primary);
        }

        p {
          margin: 0 0 16px 0;
          color: var(--el-text-color-regular);
          line-height: 1.5;
        }
      }
    }
  }
}
</style>

<style>
/* 全局样式，为 Popover 指定的 popper-class 生效 */
.sftp_create_popover .sftp_popover_actions {
  margin-top: 12px;
}

/* 下载管理器样式 */
.download_manager_container {
  max-height: 60vh;
  overflow-y: auto;
}

/* 上传管理器样式 */
.upload_manager_container {
  max-height: 60vh;
  overflow-y: auto;
}

.upload_section {
  margin-bottom: 24px;
}

.upload_section:last-child {
  margin-bottom: 0;
}

.upload_task_list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.upload_task_item {
  border: 1px solid var(--el-border-color-light);
  border-radius: 6px;
  padding: 12px;
  margin-bottom: 8px;
  background-color: var(--el-bg-color-page);
}

.upload_task_item.completed {
  border-color: var(--el-color-success-light-7);
  background-color: var(--el-color-success-light-9);
}

.upload_task_item.failed {
  border-color: var(--el-color-danger-light-7);
  background-color: var(--el-color-danger-light-9);
}

.upload_task_item .file_icon.error {
  color: var(--el-color-danger);
}

.upload_task_item .error_info {
  margin-top: 8px;
  padding: 8px;
  border-radius: 4px;
  background-color: var(--el-color-danger-light-9);
  border: 1px solid var(--el-color-danger-light-7);
}

.upload_task_item .error_text {
  color: var(--el-color-danger);
  font-size: 12px;
}

.upload_dialog_footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.download_section {
  margin-bottom: 24px;
}

.download_section:last-child {
  margin-bottom: 0;
}

.section_title {
  margin: 0 0 12px 0;
  font-size: 14px;
  font-weight: 500;
  color: var(--el-text-color-primary);
}

.download_task_list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.download_task_item {
  border: 1px solid var(--el-border-color-light);
  border-radius: 6px;
  padding: 12px;
  margin-bottom: 8px;
  background-color: var(--el-bg-color-page);
}

.download_task_item.completed {
  border-color: var(--el-color-success-light-7);
  background-color: var(--el-color-success-light-9);
}

.task_header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-width: 0; /* 允许flex子元素缩小 */
}

.file_info {
  display: flex;
  align-items: center;
  flex: 1;
  min-width: 0; /* 允许flex子元素缩小 */
}

.file_icon {
  margin-right: 8px;
  color: var(--el-color-primary);
  font-size: 16px;
  flex-shrink: 0; /* 图标不缩小 */
}

.file_icon.success {
  color: var(--el-color-success);
}

.file_name {
  font-weight: 500;
  color: var(--el-text-color-primary);
  flex: 1;
  min-width: 0; /* 允许文本缩小 */
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  padding-right: 8px; /* 为按钮留出空间 */
}

.completed_text {
  color: var(--el-color-success);
  font-size: 12px;
  font-weight: 500;
}

.task_actions {
  display: flex;
  gap: 8px;
  align-items: center;
  flex-shrink: 0; /* 按钮区域不缩小 */
}

.progress_info {
  margin-top: 8px;
}

.progress_section {
  margin-bottom: 8px;
}

.progress_section:last-of-type {
  margin-bottom: 0;
}

.progress_label {
  font-size: 11px;
  color: var(--el-text-color-regular);
  margin-bottom: 4px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.progress_details {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 6px;
  font-size: 12px;
}

.progress_text {
  color: var(--el-text-color-regular);
}

.speed_text {
  color: var(--el-text-color-secondary);
}

.no_tasks {
  text-align: center;
  padding: 40px 20px;
  color: var(--el-text-color-secondary);
}

.empty_icon {
  font-size: 48px;
  color: var(--el-color-info-light-5);
  margin-bottom: 12px;
}

/* 收藏下拉菜单样式 */
.favorite_dropdown {
  width: 250px !important;

  .favorite_item {
    .favorite_content {
      display: flex;
      justify-content: space-between;
      align-items: center;
      width: 100%;

      .favorite_path {
        flex: 1;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        margin-right: 8px;
      }

      .delete_icon {
        color: var(--el-color-danger);
        cursor: pointer;
        font-size: 14px;
        opacity: 0;
        transition: opacity 0.3s ease;

        &:hover {
          color: var(--el-color-danger-dark-2);
        }
      }
    }

    &:hover .favorite_content .delete_icon {
      opacity: 1;
    }
  }
}

/* 删除确认对话框样式 */
.delete_confirm_dialog {
  .el-message-box__content {
    max-height: 300px;
    overflow-y: auto;
    word-break: break-all;
    white-space: pre-wrap;
  }

  .el-message-box__message {
    font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
    font-size: 13px;
    line-height: 1.5;
  }
}
</style>
