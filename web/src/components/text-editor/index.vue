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
        <span class="dialog-title">{{ title }} - {{ formatFileSize(fileSize) }}</span>
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
    <div class="text-editor-container">
      <!-- 工具栏 -->
      <div class="editor-toolbar">
        <div class="toolbar-item">
          <label>主题</label>
          <el-select v-model="selectedTheme" size="small" @change="changeTheme">
            <el-option label="High Contrast Dark" value="hc-black" />
            <el-option label="Dark" value="vs-dark" />
            <el-option label="Light" value="vs" />
          </el-select>
        </div>

        <div class="toolbar-item">
          <label>类型</label>
          <el-select v-model="selectedLanguage" size="small" @change="changeLanguage">
            <el-option label="plaintext" value="plaintext" />
            <el-option label="json" value="json" />
            <el-option label="vue" value="vue" />
            <el-option label="typescript" value="typescript" />
            <el-option label="lua" value="lua" />
            <el-option label="markdown" value="markdown" />
            <el-option label="yaml" value="yaml" />
            <el-option label="xml" value="xml" />
            <el-option label="php" value="php" />
            <el-option label="sql" value="sql" />
            <el-option label="go" value="go" />
            <el-option label="html" value="html" />
            <el-option label="javascript" value="javascript" />
            <el-option label="java" value="java" />
            <el-option label="kotlin" value="kotlin" />
            <el-option label="python" value="python" />
            <el-option label="redis" value="redis" />
            <el-option label="shell" value="shell" />
            <el-option label="css" value="css" />
            <el-option label="ini" value="ini" />
          </el-select>
        </div>

        <div class="toolbar-item">
          <label>行尾符</label>
          <el-select v-model="selectedEOL" size="small" @change="changeEOL">
            <el-option label="LF (Linux)" value="LF" />
            <el-option label="CRLF (Windows)" value="CRLF" />
            <el-option label="CR (Mac)" value="CR" />
          </el-select>
        </div>

        <div class="toolbar-item">
          <label>自动换行</label>
          <el-switch v-model="wordWrapEnabled" size="small" @change="toggleWordWrap" />
        </div>

        <div class="toolbar-item">
          <label>缩略图</label>
          <el-switch v-model="minimapEnabled" size="small" @change="toggleMinimap" />
        </div>

        <div v-if="minimapEnabled" class="toolbar-item">
          <label>缩略图大小</label>
          <el-select
            v-model="minimapSize"
            size="small"
            class="size-select"
            @change="changeMinimapSize"
          >
            <el-option label="小" value="small" />
            <el-option label="中" value="medium" />
            <el-option label="大" value="large" />
          </el-select>
        </div>
      </div>

      <div
        v-loading="loading"
        class="editor-wrapper"
        element-loading-text="加载中..."
      >
        <div ref="editorContainer" class="monaco-editor" />
      </div>

      <!-- 底部按钮 -->
      <div class="editor-footer">
        <el-button size="small" @click="closeDialog">
          关闭
        </el-button>
        <el-button size="small" @click="resetFile">
          重置
        </el-button>
        <el-button
          :disabled="!hasChanges"
          type="primary"
          size="small"
          @click="saveFile"
        >
          保存
        </el-button>
      </div>
    </div>
  </el-dialog>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick, computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Close } from '@element-plus/icons-vue'
import * as monaco from 'monaco-editor'
import useStore from '@/store'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false
  },
  filePath: {
    type: String,
    default: ''
  },
  fileName: {
    type: String,
    default: ''
  },
  fileSize: {
    type: Number,
    default: 0
  },
  socket: {
    type: Object,
    default: null
  }
})

const emit = defineEmits(['update:modelValue', 'saved',])

const store = useStore()

const visible = ref(false)
const loading = ref(false)
const hasChanges = ref(false)
const editorContainer = ref(null)
const originalContent = ref('')

// 工具栏选项 - 根据系统主题设置默认编辑器主题
const getDefaultTheme = () => {
  return store.isDark ? 'vs-dark' : 'vs'
}

const selectedTheme = ref(getDefaultTheme())
const selectedLanguage = ref('plaintext')
const selectedEOL = ref('LF')
const wordWrapEnabled = ref(true)
const minimapEnabled = ref(true)
const minimapSize = ref('medium') // 默认中等大小

let editor = null
let disposables = []
let shouldCloseAfterSave = false

const title = computed(() => {
  return `编辑文件 - ${ props.filePath } ${ hasChanges.value ? ' [已变更]' : '' }`
})

// 缩略图配置映射
const minimapConfigs = {
  small: {
    scale: 0.6,
    maxColumn: 80,
    size: 'proportional'
  },
  medium: {
    scale: 1,
    maxColumn: 120,
    size: 'proportional'
  },
  large: {
    scale: 1.5,
    maxColumn: 160,
    size: 'proportional'
  }
}

// 文件类型到语言的映射
const getLanguageFromFileName = (fileName) => {
  const ext = fileName.split('.').pop()?.toLowerCase()
  const languageMap = {
    'js': 'javascript',
    'ts': 'typescript',
    'json': 'json',
    'html': 'html',
    'css': 'css',
    'scss': 'css',
    'sass': 'css',
    'less': 'css',
    'vue': 'vue',
    'jsx': 'javascript',
    'tsx': 'typescript',
    'py': 'python',
    'java': 'java',
    'kt': 'kotlin',
    'php': 'php',
    'go': 'go',
    'lua': 'lua',
    'sh': 'shell',
    'bash': 'shell',
    'zsh': 'shell',
    'fish': 'shell',
    'ps1': 'shell',
    'bat': 'shell',
    'cmd': 'shell',
    'sql': 'sql',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'md': 'markdown',
    'txt': 'plaintext',
    'log': 'plaintext',
    'conf': 'ini',
    'config': 'ini',
    'ini': 'ini',
    'properties': 'ini',
    'redis': 'redis',
    'rdb': 'redis'
  }
  return languageMap[ext] || 'ini'
}

const formatFileSize = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB',]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const initEditor = () => {
  if (!editorContainer.value) return

  const language = getLanguageFromFileName(props.fileName)
  selectedLanguage.value = language

  const minimapConfig = minimapConfigs[minimapSize.value]

  editor = monaco.editor.create(editorContainer.value, {
    value: '',
    language: language,
    theme: selectedTheme.value,
    fontSize: 14,
    wordWrap: wordWrapEnabled.value ? 'on' : 'off',
    automaticLayout: true,
    scrollBeyondLastLine: false,
    minimap: {
      enabled: minimapEnabled.value,
      scale: minimapConfig.scale,
      maxColumn: minimapConfig.maxColumn,
      size: minimapConfig.size
    },
    lineNumbers: 'on',
    glyphMargin: false,
    folding: true,
    lineDecorationsWidth: 0,
    lineNumbersMinChars: 3,
    renderLineHighlight: 'line',
    scrollbar: {
      useShadows: false,
      verticalHasArrows: false,
      horizontalHasArrows: false,
      vertical: 'visible',
      horizontal: 'visible'
    }
  })

  // 监听内容变化
  const onContentChange = editor.onDidChangeModelContent(() => {
    hasChanges.value = editor.getValue() !== originalContent.value
  })

  // 注册快捷键
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
    saveFile()
  })

  disposables.push(onContentChange)
}

const loadFileContent = async () => {
  if (!props.socket) return

  loading.value = true
  try {
    // 请求文件内容
    props.socket.emit('read_file', {
      filePath: props.filePath,
      fileSize: props.fileSize
    })
  } catch (error) {
    console.error('加载文件失败:', error)
  }
}

const saveFile = async () => {
  if (!props.socket || !editor) return

  loading.value = true
  try {
    const content = editor.getValue()
    props.socket.emit('save_file', {
      filePath: props.filePath,
      content: content
    })
  } catch (error) {
    console.error('保存文件失败:', error)
    loading.value = false
  }
}

const handleClose = (done) => {
  if (hasChanges.value) {
    ElMessageBox.confirm(
      '文件已修改，是否保存后关闭？',
      '确认关闭',
      {
        confirmButtonText: '保存并关闭',
        cancelButtonText: '不保存',
        type: 'warning',
        showCancelButton: true,
        cancelButtonClass: 'el-button--info',
        confirmButtonClass: 'el-button--warning'
      }
    ).then(() => {
      // 保存并关闭
      shouldCloseAfterSave = true
      saveFile()
      // 保存成功后会触发 file_saved 事件，在那里关闭
      done()
    }).catch(() => {
      // 不保存直接关闭
      done()
    })
  } else {
    done()
  }
}

const closeDialog = () => {
  if (hasChanges.value) {
    ElMessageBox.confirm(
      '文件已修改，是否保存后关闭？',
      '确认关闭',
      {
        confirmButtonText: '保存并关闭',
        cancelButtonText: '不保存',
        type: 'warning',
        showCancelButton: true,
        cancelButtonClass: 'el-button--info',
        confirmButtonClass: 'el-button--warning'
      }
    ).then(() => {
      // 保存并关闭
      shouldCloseAfterSave = true
      saveFile()
      // 保存成功后会触发 file_saved 事件，在那里关闭
    }).catch(() => {
      // 不保存直接关闭
      visible.value = false
    })
  } else {
    visible.value = false
  }
}

// 工具栏功能函数
const changeTheme = (theme) => {
  if (editor) {
    monaco.editor.setTheme(theme)
  }
}

const changeLanguage = (language) => {
  if (editor) {
    const model = editor.getModel()
    if (model) {
      monaco.editor.setModelLanguage(model, language)
    }
  }
}

const changeEOL = (eol) => {
  if (editor) {
    const model = editor.getModel()
    if (model) {
      const eolSequence = eol === 'LF' ? monaco.editor.EndOfLineSequence.LF :
        eol === 'CRLF' ? monaco.editor.EndOfLineSequence.CRLF :
          monaco.editor.EndOfLineSequence.LF
      model.setEOL(eolSequence)
    }
  }
}

const toggleWordWrap = (enabled) => {
  if (editor) {
    editor.updateOptions({
      wordWrap: enabled ? 'on' : 'off'
    })
  }
}

const toggleMinimap = (enabled) => {
  if (editor) {
    const minimapConfig = minimapConfigs[minimapSize.value]
    editor.updateOptions({
      minimap: {
        enabled,
        scale: minimapConfig.scale,
        maxColumn: minimapConfig.maxColumn,
        size: minimapConfig.size
      }
    })
  }
}

const changeMinimapSize = (size) => {
  if (editor) {
    const config = minimapConfigs[size]
    editor.updateOptions({
      minimap: {
        enabled: minimapEnabled.value,
        scale: config.scale,
        maxColumn: config.maxColumn,
        size: config.size
      }
    })
  }
}

const resetFile = () => {
  if (editor && originalContent.value !== undefined) {
    ElMessageBox.confirm(
      '确认重置文件内容到初始状态？',
      '重置确认',
      {
        confirmButtonText: '确认重置',
        cancelButtonText: '取消',
        type: 'warning'
      }
    ).then(() => {
      editor.setValue(originalContent.value)
      hasChanges.value = false
      ElMessage.success('文件内容已重置')
    }).catch(() => {
      // 取消重置
    })
  }
}

// 监听 socket 事件
const setupSocketListeners = () => {
  if (!props.socket) return

  props.socket.on('file_content', ({ content, filePath }) => {
    if (filePath === props.filePath) {
      originalContent.value = content
      hasChanges.value = false
      if (editor) {
        editor.setValue(content)
      }
      loading.value = false
    }
  })

  props.socket.on('file_saved', ({ filePath }) => {
    if (filePath === props.filePath) {
      originalContent.value = editor.getValue()
      hasChanges.value = false
      loading.value = false
      ElMessage.success('文件保存成功')
      emit('saved', { filePath })

      // 如果是保存并关闭操作，则关闭对话框
      if (shouldCloseAfterSave) {
        shouldCloseAfterSave = false
        visible.value = false
      }
    }
  })

  props.socket.on('file_read_error', ({ error, filePath }) => {
    if (filePath === props.filePath) {
      loading.value = false
      ElMessage.error(`读取文件失败: ${ error }`)
    }
  })

  props.socket.on('file_save_error', ({ error, filePath }) => {
    if (filePath === props.filePath) {
      loading.value = false
      ElMessage.error(`保存文件失败: ${ error }`)
    }
  })
}

const cleanupSocketListeners = () => {
  if (!props.socket) return

  props.socket.off('file_content')
  props.socket.off('file_saved')
  props.socket.off('file_read_error')
  props.socket.off('file_save_error')
}

// 监听 visible 变化
watch(visible, (newVal) => {
  emit('update:modelValue', newVal)
  if (newVal) {
    // 对话框打开时更新主题设置
    selectedTheme.value = getDefaultTheme()

    nextTick(() => {
      initEditor()
      setupSocketListeners()
      loadFileContent()
    })
  } else {
    cleanupSocketListeners()
    if (editor) {
      // 清理 disposables
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

// 监听系统主题变化
watch(() => store.isDark, (newIsDark) => {
  const newTheme = newIsDark ? 'vs-dark' : 'vs'
  selectedTheme.value = newTheme
  // 如果编辑器已初始化，立即应用新主题
  if (editor) {
    monaco.editor.setTheme(newTheme)
  }
})

onMounted(() => {
  visible.value = props.modelValue
})

onUnmounted(() => {
  cleanupSocketListeners()
  if (editor) {
    // 清理 disposables
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
.text-editor-container {
  display: flex;
  flex-direction: column;
  height: 88vh;

  .editor-toolbar {
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

        &.size-select {
          width: 80px;
        }
      }
    }
  }

  .editor-wrapper {
    flex: 1;
    position: relative;

    .monaco-editor {
      height: 100%;
      border: 1px solid var(--el-border-color-light);
    }
  }

  .editor-footer {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    border-top: 1px solid var(--el-border-color-light);
    background-color: var(--el-bg-color-page);
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
