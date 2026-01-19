<template>
  <el-dialog
    v-model="visible"
    width="68%"
    :top="'3vh'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :before-close="handleClose"
    :show-close="false"
    append-to-body
  >
    <template #header>
      <div class="dialog-header">
        <span class="dialog-title">{{ title }}</span>
        <el-button
          link
          size="small"
          class="close-button"
          @click="closeDialog"
        >
          <el-icon><Close /></el-icon>
        </el-button>
      </div>
    </template>
    <div class="log-viewer-container">
      <!-- 工具栏 -->
      <div class="viewer-toolbar">
        <div class="toolbar-item">
          <label>自动换行</label>
          <el-switch v-model="wordWrapEnabled" size="small" @change="toggleWordWrap" />
        </div>

        <div class="toolbar-item">
          <label>缩略图</label>
          <el-switch v-model="minimapEnabled" size="small" @change="toggleMinimap" />
        </div>

        <div class="toolbar-item">
          <label>自动滚动</label>
          <el-switch v-model="autoScrollEnabled" size="small" />
        </div>

        <div class="toolbar-item">
          <el-button
            size="small"
            :icon="RefreshRight"
            @click="manualRefresh"
          >
            手动刷新
          </el-button>
        </div>
      </div>

      <div
        v-loading="loading"
        class="viewer-wrapper"
        element-loading-text="加载中..."
      >
        <div ref="editorContainer" class="monaco-editor" />
      </div>

      <!-- 底部信息栏 -->
      <div class="viewer-footer">
        <div class="footer-info">
          <span class="info-item">行数: {{ lineCount }}</span>
          <span class="info-item">大小: {{ formatSize(contentSize) }}</span>
          <span v-if="lastUpdateTime" class="info-item">
            最后更新: {{ lastUpdateTime }}
          </span>
        </div>
        <el-button size="small" @click="closeDialog">
          关闭
        </el-button>
      </div>
    </div>
  </el-dialog>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { Close, RefreshRight } from '@element-plus/icons-vue'
import * as monaco from 'monaco-editor'
import useStore from '@/store'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false
  },
  content: {
    type: String,
    default: ''
  },
  title: {
    type: String,
    default: '日志查看器'
  },
  language: {
    type: String,
    default: 'plaintext'
  }
})

const emit = defineEmits(['update:modelValue', 'refresh',])

const store = useStore()

const visible = ref(false)
const loading = ref(false)
const editorContainer = ref(null)
const lineCount = ref(0)
const contentSize = ref(0)
const lastUpdateTime = ref('')

// 工具栏选项 - 根据系统主题设置默认编辑器主题
const getDefaultTheme = () => {
  return store.isDark ? 'vs-dark' : 'vs'
}

const selectedTheme = ref(getDefaultTheme())
const wordWrapEnabled = ref(true)
const minimapEnabled = ref(true)
const autoScrollEnabled = ref(true)

let editor = null
let disposables = []
let refreshTimer = null
let previousScrollPosition = 0

const formatSize = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB',]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const initEditor = () => {
  if (!editorContainer.value) return

  editor = monaco.editor.create(editorContainer.value, {
    value: props.content,
    language: props.language,
    theme: selectedTheme.value,
    fontSize: 13,
    wordWrap: wordWrapEnabled.value ? 'on' : 'off',
    automaticLayout: true,
    scrollBeyondLastLine: false,
    readOnly: true,
    minimap: {
      enabled: minimapEnabled.value
    },
    lineNumbers: 'on',
    glyphMargin: false,
    folding: false,
    lineDecorationsWidth: 0,
    lineNumbersMinChars: 4,
    renderLineHighlight: 'none',
    scrollbar: {
      useShadows: false,
      verticalHasArrows: false,
      horizontalHasArrows: false,
      vertical: 'visible',
      horizontal: 'visible',
      verticalScrollbarSize: 10,
      horizontalScrollbarSize: 10
    },
    contextmenu: true,
    selectOnLineNumbers: true
  })

  // 监听滚动事件，记录用户滚动位置
  editor.onDidScrollChange((e) => {
    previousScrollPosition = e.scrollTop
  })

  disposables.push(editor)
}

const updateContent = (newContent) => {
  if (!editor) return

  const currentContent = editor.getValue()
  if (currentContent === newContent) return

  // 检查用户是否在底部
  const isAtBottom = isScrollAtBottom()

  // 更新内容
  editor.setValue(newContent)

  // 更新统计信息
  lineCount.value = editor.getModel().getLineCount()
  contentSize.value = new Blob([newContent,]).size
  lastUpdateTime.value = new Date().toLocaleTimeString()

  // 如果启用自动滚动且用户在底部，则滚动到底部
  if (autoScrollEnabled.value && isAtBottom) {
    nextTick(() => {
      scrollToBottom()
    })
  }
}

const isScrollAtBottom = () => {
  if (!editor) return false

  try {
    const scrollTop = editor.getScrollTop()
    const scrollHeight = editor.getScrollHeight()
    const clientHeight = editorContainer.value?.clientHeight || 0
    const threshold = 100 // 距离底部100px以内认为是在底部

    return scrollTop + clientHeight >= scrollHeight - threshold
  } catch (error) {
    return false
  }
}

const scrollToBottom = () => {
  if (!editor) return

  try {
    const lineCount = editor.getModel().getLineCount()
    editor.revealLine(lineCount, monaco.editor.ScrollType.Smooth)
  } catch (error) {
    console.warn('滚动到底部失败:', error)
  }
}

const manualRefresh = () => {
  emit('refresh')
  ElMessage.success('已请求刷新日志')
}

const startAutoRefresh = (immediate = false) => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
  }

  // 如果需要立即刷新，先执行一次
  if (immediate) {
    emit('refresh')
  }

  // 固定使用3秒刷新间隔
  refreshTimer = setInterval(() => {
    emit('refresh')
  }, 3000)
}

const stopAutoRefresh = () => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
}

// 工具栏功能函数
const toggleWordWrap = (enabled) => {
  if (editor) {
    editor.updateOptions({
      wordWrap: enabled ? 'on' : 'off'
    })
  }
}

const toggleMinimap = (enabled) => {
  if (editor) {
    editor.updateOptions({
      minimap: {
        enabled
      }
    })
  }
}

const handleClose = (done) => {
  done()
}

const closeDialog = () => {
  visible.value = false
}

// 监听 visible 变化
watch(visible, (newVal) => {
  emit('update:modelValue', newVal)
  if (newVal) {
    // 对话框打开时更新主题设置
    selectedTheme.value = getDefaultTheme()

    nextTick(() => {
      initEditor()
      updateContent(props.content)

      // 首次打开强制滚动到底部
      if (autoScrollEnabled.value) {
        setTimeout(() => {
          scrollToBottom()
        }, 300)
      }

      // 启动自动刷新（固定3秒间隔），不立即刷新，因为外部已经请求过一次
      startAutoRefresh(false)
    })
  } else {
    stopAutoRefresh()
    if (editor) {
      disposables.forEach(d => {
        if (d && typeof d.dispose === 'function') {
          d.dispose()
        }
      })
      disposables = []
      editor.dispose()
      editor = null
    }
  }
})

watch(() => props.modelValue, (newVal) => {
  visible.value = newVal
})

// 监听内容变化
watch(() => props.content, (newContent) => {
  if (editor && visible.value) {
    updateContent(newContent)
  }
})

// 监听系统主题变化
watch(() => store.isDark, (newIsDark) => {
  const newTheme = newIsDark ? 'vs-dark' : 'vs'
  selectedTheme.value = newTheme
  if (editor) {
    monaco.editor.setTheme(newTheme)
  }
})

onMounted(() => {
  visible.value = props.modelValue
})

onUnmounted(() => {
  stopAutoRefresh()
  if (editor) {
    disposables.forEach(d => {
      if (d && typeof d.dispose === 'function') {
        d.dispose()
      }
    })
    editor.dispose()
  }
})
</script>

<style lang="scss" scoped>
.log-viewer-container {
  display: flex;
  flex-direction: column;
  height: 88vh;

  .viewer-toolbar {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 8px 16px;
    border-bottom: 1px solid var(--el-border-color-light);
    background-color: var(--el-bg-color-page);
    flex-wrap: wrap;

    .toolbar-item {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;

      label {
        color: var(--el-text-color-regular);
        font-weight: 500;
        white-space: nowrap;
      }

      .el-select {
        width: 140px;
      }
    }
  }

  .viewer-wrapper {
    flex: 1;
    position: relative;

    .monaco-editor {
      height: 100%;
      border: 1px solid var(--el-border-color-light);
    }
  }

  .viewer-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 16px;
    border-top: 1px solid var(--el-border-color-light);
    background-color: var(--el-bg-color-page);

    .footer-info {
      display: flex;
      gap: 16px;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      .info-item {
        display: flex;
        align-items: center;
      }
    }
  }
}

.dialog-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;

  .dialog-title {
    font-size: 16px;
    font-weight: 500;
    color: var(--el-text-color-primary);
  }

  .close-button {
    padding: 4px;
    border: none;
    background: none;

    &:hover {
      background-color: var(--el-color-danger-light-8);
      color: var(--el-color-danger);
    }
  }
}
</style>