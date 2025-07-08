<template>
  <el-dialog
    v-model="showDialog"
    :title="title"
    width="90%"
    top="3vh"
    :close-on-click-modal="false"
    :close-on-press-escape="true"
    :destroy-on-close="true"
    class="image_preview_dialog"
    @closed="onDialogClosed"
  >
    <div class="image_preview_container">
      <!-- 工具栏 -->
      <div class="toolbar">
        <div class="toolbar_left">
          <span class="image_info">{{ imageInfo }}</span>
        </div>
        <div class="toolbar_right">
          <el-button-group>
            <el-button size="small" :disabled="scale <= 0.1" @click="zoomOut">
              <el-icon><ZoomOut /></el-icon>
            </el-button>
            <el-button size="small" @click="resetZoom">
              {{ Math.round(scale * 100) }}%
            </el-button>
            <el-button size="small" :disabled="scale >= 10" @click="zoomIn">
              <el-icon><ZoomIn /></el-icon>
            </el-button>
          </el-button-group>

          <el-button size="small" style="margin-left: 8px;" @click="rotateLeft">
            <el-icon><RefreshLeft /></el-icon>
          </el-button>
          <el-button size="small" @click="rotateRight">
            <el-icon><RefreshRight /></el-icon>
          </el-button>

          <el-button size="small" style="margin-left: 8px;" @click="resetTransform">
            <el-icon><Refresh /></el-icon>
            重置
          </el-button>

          <el-button
            size="small"
            type="primary"
            style="margin-left: 8px;"
            @click="downloadImage"
          >
            <el-icon><Download /></el-icon>
            下载
          </el-button>
        </div>
      </div>

      <!-- 图片预览区域 -->
      <div ref="imageContainer" class="image_container">
        <div
          class="image_wrapper"
          :style="imageWrapperStyle"
          @mousedown="handleMouseDown"
          @wheel="handleWheel"
        >
          <img
            ref="imageRef"
            :src="imageSrc"
            :alt="fileName"
            class="preview_image"
            @load="onImageLoad"
            @error="onImageError"
            @dragstart.prevent
          >
        </div>

        <!-- 加载状态 -->
        <div v-if="loading" class="loading_overlay">
          <el-icon class="is-loading loading_icon"><Loading /></el-icon>
          <p>正在加载图片...</p>
        </div>

        <!-- 错误状态 -->
        <div v-if="error" class="error_overlay">
          <el-icon class="error_icon"><WarningFilled /></el-icon>
          <p>图片加载失败</p>
          <p class="error_message">{{ error }}</p>
        </div>
      </div>

      <!-- 图片信息面板 -->
      <div v-if="imageLoaded" class="info_panel">
        <div class="info_item">
          <label>文件名：</label>
          <span>{{ fileName }}</span>
        </div>
        <div class="info_item">
          <label>文件大小：</label>
          <span>{{ formatFileSize(fileSize) }}</span>
        </div>
        <div class="info_item">
          <label>图片尺寸：</label>
          <span>{{ imageWidth }} × {{ imageHeight }}</span>
        </div>
        <div class="info_item">
          <label>文件类型：</label>
          <span>{{ getFileType(fileName) }}</span>
        </div>
      </div>
    </div>

    <template #footer>
      <el-button @click="closeDialog">关闭</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { ZoomIn, ZoomOut, RefreshLeft, RefreshRight, Refresh, Download, Loading, WarningFilled } from '@element-plus/icons-vue'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false
  },
  imageSrc: {
    type: String,
    required: true
  },
  fileName: {
    type: String,
    required: true
  },
  fileSize: {
    type: Number,
    default: 0
  },
  filePath: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['update:modelValue', 'download',])

// 对话框显示状态
const showDialog = computed({
  get: () => props.modelValue,
  set: (val) => emit('update:modelValue', val)
})

// 图片预览相关状态
const imageRef = ref(null)
const imageContainer = ref(null)
const loading = ref(false)
const error = ref('')
const imageLoaded = ref(false)
const imageWidth = ref(0)
const imageHeight = ref(0)

// 变换状态
const scale = ref(1)
const rotation = ref(0)
const translateX = ref(0)
const translateY = ref(0)

// 拖拽状态
const isDragging = ref(false)
const dragStartX = ref(0)
const dragStartY = ref(0)
const dragStartTranslateX = ref(0)
const dragStartTranslateY = ref(0)

// 计算属性
const title = computed(() => `图片预览 - ${ props.fileName }`)

const imageInfo = computed(() => {
  if (!imageLoaded.value) return ''
  return `${ imageWidth.value } × ${ imageHeight.value } · ${ formatFileSize(props.fileSize) }`
})

const imageWrapperStyle = computed(() => {
  return {
    transform: `translate(-50%, -50%) translate(${ translateX.value }px, ${ translateY.value }px) scale(${ scale.value }) rotate(${ rotation.value }deg)`,
    transformOrigin: 'center center',
    transition: isDragging.value ? 'none' : 'transform 0.3s ease',
    cursor: isDragging.value ? 'grabbing' : 'grab'
  }
})

// 支持的图片格式
const supportedImageTypes = [
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif',
]

// 判断是否为支持的图片格式
const isImageFile = (filename) => {
  const ext = filename.split('.').pop()?.toLowerCase()
  return supportedImageTypes.includes(ext)
}

// 获取文件类型
const getFileType = (filename) => {
  const ext = filename.split('.').pop()?.toLowerCase()
  const typeMap = {
    'jpg': 'JPEG图片',
    'jpeg': 'JPEG图片',
    'png': 'PNG图片',
    'gif': 'GIF动图',
    'bmp': 'BMP图片',
    'webp': 'WebP图片',
    'svg': 'SVG矢量图',
    'ico': 'ICO图标',
    'tiff': 'TIFF图片',
    'tif': 'TIFF图片'
  }
  return typeMap[ext] || '未知格式'
}

// 格式化文件大小
const formatFileSize = (bytes) => {
  if (!bytes || bytes === 0) return '0 B'
  const KB = 1024, MB = KB * 1024, GB = MB * 1024
  if (bytes < KB) return bytes + ' B'
  if (bytes < MB) return (bytes / KB).toFixed(1) + ' KB'
  if (bytes < GB) return (bytes / MB).toFixed(1) + ' MB'
  return (bytes / GB).toFixed(1) + ' GB'
}

// 图片加载完成
const onImageLoad = (e) => {
  console.log('图片加载成功:', {
    naturalWidth: e.target.naturalWidth,
    naturalHeight: e.target.naturalHeight,
    src: e.target.src
  })

  loading.value = false
  error.value = ''
  imageLoaded.value = true
  imageWidth.value = e.target.naturalWidth
  imageHeight.value = e.target.naturalHeight

  // 初始化适合容器的缩放比例
  nextTick(() => {
    fitToContainer()
  })
}

// 图片加载错误
const onImageError = (e) => {
  console.error('图片加载错误详情:', {
    error: e,
    src: e.target.src.substring(0, 100) + '...',
    naturalWidth: e.target.naturalWidth,
    naturalHeight: e.target.naturalHeight
  })

  loading.value = false
  error.value = '图片加载失败，请检查文件格式或网络连接'
  imageLoaded.value = false
}

// 适合容器大小
const fitToContainer = () => {
  if (!imageContainer.value || !imageRef.value) return

  // 获取实际容器尺寸
  const containerRect = imageContainer.value.getBoundingClientRect()
  const containerWidth = containerRect.width
  const containerHeight = containerRect.height

  // 如果容器尺寸无效，使用默认值
  if (containerWidth <= 0 || containerHeight <= 0) {
    return
  }

  const imageAspectRatio = imageWidth.value / imageHeight.value
  const containerAspectRatio = containerWidth / containerHeight

  let newScale = 1

  if (imageAspectRatio > containerAspectRatio) {
    // 图片更宽，按宽度适配
    newScale = (containerWidth * 0.9) / imageWidth.value
  } else {
    // 图片更高，按高度适配
    newScale = (containerHeight * 0.9) / imageHeight.value
  }

  // 限制最大初始缩放
  scale.value = Math.min(newScale, 1)
}

// 缩放控制
const zoomIn = () => {
  scale.value = Math.min(scale.value * 1.2, 10)
}

const zoomOut = () => {
  scale.value = Math.max(scale.value / 1.2, 0.1)
}

const resetZoom = () => {
  scale.value = 1
}

// 旋转控制
const rotateLeft = () => {
  rotation.value -= 90
}

const rotateRight = () => {
  rotation.value += 90
}

// 重置变换
const resetTransform = () => {
  scale.value = 1
  rotation.value = 0
  translateX.value = 0
  translateY.value = 0
}

// 鼠标拖拽处理
const handleMouseDown = (e) => {
  if (e.button !== 0) return // 只处理左键

  isDragging.value = true
  dragStartX.value = e.clientX
  dragStartY.value = e.clientY
  dragStartTranslateX.value = translateX.value
  dragStartTranslateY.value = translateY.value

  document.addEventListener('mousemove', handleMouseMove)
  document.addEventListener('mouseup', handleMouseUp)

  e.preventDefault()
}

const handleMouseMove = (e) => {
  if (!isDragging.value) return

  const deltaX = e.clientX - dragStartX.value
  const deltaY = e.clientY - dragStartY.value

  translateX.value = dragStartTranslateX.value + deltaX
  translateY.value = dragStartTranslateY.value + deltaY
}

const handleMouseUp = () => {
  isDragging.value = false
  document.removeEventListener('mousemove', handleMouseMove)
  document.removeEventListener('mouseup', handleMouseUp)
}

// 鼠标滚轮缩放
const handleWheel = (e) => {
  e.preventDefault()

  const delta = e.deltaY > 0 ? 0.9 : 1.1
  const newScale = scale.value * delta

  if (newScale >= 0.1 && newScale <= 10) {
    scale.value = newScale
  }
}

// 下载图片
const downloadImage = () => {
  emit('download', {
    fileName: props.fileName,
    filePath: props.filePath,
    imageSrc: props.imageSrc
  })
}

// 关闭对话框
const closeDialog = () => {
  showDialog.value = false
}

// 对话框关闭回调
const onDialogClosed = () => {
  // 重置状态
  resetTransform()
  loading.value = false
  error.value = ''
  imageLoaded.value = false
  imageWidth.value = 0
  imageHeight.value = 0
}

// 监听图片源变化
watch(() => props.imageSrc, (newSrc) => {
  if (newSrc) {
    loading.value = true
    error.value = ''
    imageLoaded.value = false
    resetTransform()
  }
}, { immediate: true })

// 监听对话框打开
watch(() => props.modelValue, (newVal) => {
  if (newVal && props.imageSrc) {
    loading.value = true
    error.value = ''
    imageLoaded.value = false
    resetTransform()
  }
})

// 导出工具函数供外部使用
defineExpose({
  isImageFile,
  supportedImageTypes
})
</script>

<style lang="scss" scoped>
.image_preview_container {
  display: flex;
  flex-direction: column;
  height: 75vh;
  min-height: 400px;

  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid var(--el-border-color);
    margin-bottom: 16px;

    .toolbar_left {
      .image_info {
        font-size: 14px;
        color: var(--el-text-color-regular);
      }
    }

    .toolbar_right {
      display: flex;
      align-items: center;
      gap: 8px;
    }
  }

  .image_container {
    flex: 1;
    position: relative;
    overflow: hidden;
    border: 1px solid var(--el-border-color);
    border-radius: 6px;

    .image_wrapper {
      position: absolute;
      top: 50%;
      left: 50%;
      transform-origin: center center;
      will-change: transform;

      .preview_image {
        display: block;
        max-width: none;
        max-height: none;
        pointer-events: none;
        user-select: none;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        border-radius: 4px;
      }
    }

    .loading_overlay,
    .error_overlay {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      background: rgba(255, 255, 255, 0.9);
      backdrop-filter: blur(2px);
      z-index: 10;

      .loading_icon {
        font-size: 32px;
        color: var(--el-color-primary);
        margin-bottom: 12px;
      }

      .error_icon {
        font-size: 32px;
        color: var(--el-color-danger);
        margin-bottom: 12px;
      }

      p {
        margin: 0;
        color: var(--el-text-color-primary);

        &.error_message {
          font-size: 12px;
          color: var(--el-text-color-regular);
          margin-top: 4px;
        }
      }
    }
  }

  .info_panel {
    margin-top: 16px;
    padding: 12px;
    border-radius: 6px;
    background: var(--el-bg-color-page);
    border: 1px solid var(--el-border-color);

    .info_item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 8px;

      &:last-child {
        margin-bottom: 0;
      }

      label {
        font-size: 12px;
        color: var(--el-text-color-regular);
        font-weight: 500;
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-primary);
      }
    }
  }
}
</style>

<style>
/* 全局样式 */
.image_preview_dialog {
  .el-dialog__body {
    padding: 20px;
  }
}
</style>