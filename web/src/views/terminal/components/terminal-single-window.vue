<template>
  <div ref="containerRef" class="single_window_container">
    <div
      v-if="isPlusActive"
      class="terminal_panels_wrapper"
      :style="containerStyle"
      :class="{ 'scroll_mode': props.layoutMode === 'scroll' }"
    >
      <!-- @click="handlePanelClick(panel.terminal.key)" -->
      <div
        v-for="(panel, index) in layoutPanels"
        :key="panel.terminal.key"
        :class="['terminal_panel', { 'active': focusedTerminalKey === panel.terminal.key }]"
        :style="panel.style"
      >
        <!-- 终端标题栏 -->
        <div class="terminal_header">
          <div class="terminal_title">
            <span class="terminal_index">{{ String(index + 1).padStart(2, '0') }}</span>
            <span
              class="terminal_status"
              :style="{ background: getStatusColor(panel.terminal.status) }"
            />
            <span class="terminal_name">{{ panel.terminal.name }}</span>
            <span :class="['script_input_icon', { 'active': scriptInputStates[panel.terminal.key] }]" @click="handleShowScriptInput(panel)">
              <svg-icon name="icon-daima" class="icon" />
            </span>
          </div>
          <div class="terminal_close" @click.stop="handleCloseTerminal(panel.terminal.key)">
            <el-icon class="close_icon"><Close /></el-icon>
          </div>
        </div>

        <!-- 终端内容区域 -->
        <div class="terminal_content">
          <Terminal
            :ref="el => setTerminalRef(el, panel.terminal.key)"
            :host-obj="panel.terminal"
            :long-press-ctrl="longPressCtrl"
            :long-press-alt="longPressAlt"
            :auto-focus="focusedTerminalKey === panel.terminal.key"
            :is-single-window="true"
            @input-command="(cmd, uid) => handleInputCommand(cmd, uid, panel.terminal.key)"
            @ping-data="getPingData"
            @reset-long-press="resetLongPress"
            @tab-focus="handleTabFocus"
          />
        </div>
        <el-dialog
          v-model="scriptInputStates[panel.terminal.key]"
          title="脚本输入"
          top="20vh"
          width="60%"
          height="50vh"
          :modal="false"
          draggable
          center
          :close-on-click-modal="false"
          class="script_input_dialog"
          @close="handleCloseScriptInput(panel)"
        >
          <ScriptInput :host-id="panel.terminal.id" @exec-command="handleExecCommand(panel, $event)" />
        </el-dialog>
      </div>

      <!-- 拖拽分割线 -->
      <div
        v-for="divider in dividers"
        :key="divider.id"
        :class="['resize_divider', divider.direction]"
        :style="divider.style"
        @mousedown="handleDividerMouseDown($event, divider)"
      />
    </div>
    <div v-else class="not_plus_active_wrapper">
      <PlusLimitTip />
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
import { Close } from '@element-plus/icons-vue'
import Terminal from './terminal.vue'
import { terminalStatusList } from '@/utils/enum'
import ScriptInput from './script-input.vue'
import PlusLimitTip from '@/components/common/PlusLimitTip.vue'

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  },
  isSyncAllSession: {
    type: Boolean,
    default: false
  },
  isPlusActive: {
    type: Boolean,
    default: false
  },
  longPressCtrl: {
    type: Boolean,
    default: false
  },
  longPressAlt: {
    type: Boolean,
    default: false
  },
  layoutMode: {
    type: String,
    default: 'grid'
  }
})

// 容器引用
const containerRef = ref(null)

const emit = defineEmits(['close-terminal', 'terminal-input', 'ping-data', 'reset-long-press',])

// 响应式数据
const focusedTerminalKey = ref(null)
const terminalRefs = ref({})
const isDragging = ref(false)
const dragInfo = ref(null)
const panelSizes = ref({}) // 存储每个面板的大小信息
const scriptInputStates = ref({}) // 存储每个终端的脚本输入dialog状态

// 计算属性
const containerStyle = computed(() => {
  const terminals = props.terminalTabs
  if (!terminals.length) return { width: '100%', height: '100%', position: 'relative' }

  const count = terminals.length

  if (count >= 5) {
    if (props.layoutMode === 'scroll') {
      // 横向滚动模式：每个终端最小500px宽，高度自适应容器
      const minTerminalWidth = 500
      const gap = 8 // 终端之间的间距
      const totalWidth = count * minTerminalWidth + (count - 1) * gap

      return {
        width: `${ totalWidth }px`,
        height: '100%', // 高度自适应容器
        position: 'relative'
      }
    }
    // 一屏展示模式：原有逻辑
    let cols = Math.ceil(Math.sqrt(count))
    let rows = Math.ceil(count / cols)

    const minTerminalHeight = 120
    const containerHeight = containerRef.value?.clientHeight || 600
    const maxRows = Math.floor(containerHeight / minTerminalHeight)

    if (rows > maxRows) {
      rows = maxRows
      cols = Math.ceil(count / rows)
    }

    const actualHeight = rows * minTerminalHeight

    return {
      width: '100%',
      height: actualHeight > containerHeight ? `${ actualHeight }px` : '100%',
      position: 'relative'
    }
  }
  // 对于1-4个终端，设置合适的最小高度
  const minTerminalHeight = 250
  const gap = 8
  let minContainerHeight = minTerminalHeight

  if (count === 2) {
    minContainerHeight = minTerminalHeight // 水平分割，高度保持250px
  } else if (count === 3) {
    minContainerHeight = minTerminalHeight // 左右分割，高度保持250px
  } else if (count === 4) {
    minContainerHeight = minTerminalHeight * 2 + gap // 2x2网格，高度为510px
  }

  const containerHeight = containerRef.value?.clientHeight || 600

  // 只有当容器高度不足时才设置固定高度（显示滚动条）
  if (containerHeight < minContainerHeight) {
    return {
      width: '100%',
      height: `${ minContainerHeight }px`,
      position: 'relative'
    }
  }

  return { width: '100%', height: '100%', position: 'relative' }
})

// 布局计算
const layoutPanels = computed(() => {
  const terminals = props.terminalTabs
  if (!terminals.length) return []

  return calculateLayout(terminals)
})

// 分割线计算
const dividers = computed(() => {
  const terminals = props.terminalTabs
  if (terminals.length <= 1) return []

  // 横向滚动模式下不需要分割线
  if (terminals.length >= 5 && props.layoutMode === 'scroll') {
    return []
  }

  return calculateDividers(terminals)
})

// 布局算法 - Tmux风格的二分法
const calculateLayout = (terminals) => {
  const panels = []
  const count = terminals.length

  // 定义间距大小
  const gap = 8 // 8px间距

  if (count === 1) {
    // 单个终端占满整个容器
    panels.push({
      terminal: terminals[0],
      style: {
        position: 'absolute',
        left: '0px',
        top: '0px',
        width: '100%',
        height: '100%'
      }
    })
  } else if (count === 2) {
    // 两个终端水平分割，添加间距
    const width = panelSizes.value.split1 || 50
    const leftWidth = `calc(${ width }% - ${ gap/2 }px)`
    const rightLeft = `calc(${ width }% + ${ gap/2 }px)`
    const rightWidth = `calc(${ 100 - width }% - ${ gap/2 }px)`

    panels.push({
      terminal: terminals[0],
      style: {
        position: 'absolute',
        left: '0px',
        top: '0px',
        width: leftWidth,
        height: '100%'
      }
    })
    panels.push({
      terminal: terminals[1],
      style: {
        position: 'absolute',
        left: rightLeft,
        top: '0px',
        width: rightWidth,
        height: '100%'
      }
    })
  } else if (count === 3) {
    // 三个终端：左侧50% + 右侧垂直分割，添加间距
    const leftWidth = panelSizes.value.split1 || 50
    const rightTopHeight = panelSizes.value.split2 || 50

    const leftPanelWidth = `calc(${ leftWidth }% - ${ gap/2 }px)`
    const rightPanelLeft = `calc(${ leftWidth }% + ${ gap/2 }px)`
    const rightPanelWidth = `calc(${ 100 - leftWidth }% - ${ gap/2 }px)`
    const rightTopHeight_calc = `calc(${ rightTopHeight }% - ${ gap/2 }px)`
    const rightBottomTop = `calc(${ rightTopHeight }% + ${ gap/2 }px)`
    const rightBottomHeight = `calc(${ 100 - rightTopHeight }% - ${ gap/2 }px)`

    panels.push({
      terminal: terminals[0],
      style: {
        position: 'absolute',
        left: '0px',
        top: '0px',
        width: leftPanelWidth,
        height: '100%'
      }
    })
    panels.push({
      terminal: terminals[1],
      style: {
        position: 'absolute',
        left: rightPanelLeft,
        top: '0px',
        width: rightPanelWidth,
        height: rightTopHeight_calc
      }
    })
    panels.push({
      terminal: terminals[2],
      style: {
        position: 'absolute',
        left: rightPanelLeft,
        top: rightBottomTop,
        width: rightPanelWidth,
        height: rightBottomHeight
      }
    })
  } else if (count === 4) {
    // 四个终端：2x2网格，添加间距
    const leftWidth = panelSizes.value.split1 || 50
    const topHeight = panelSizes.value.split2 || 50

    const leftPanelWidth = `calc(${ leftWidth }% - ${ gap/2 }px)`
    const rightPanelLeft = `calc(${ leftWidth }% + ${ gap/2 }px)`
    const rightPanelWidth = `calc(${ 100 - leftWidth }% - ${ gap/2 }px)`
    const topPanelHeight = `calc(${ topHeight }% - ${ gap/2 }px)`
    const bottomPanelTop = `calc(${ topHeight }% + ${ gap/2 }px)`
    const bottomPanelHeight = `calc(${ 100 - topHeight }% - ${ gap/2 }px)`

    panels.push({
      terminal: terminals[0],
      style: {
        position: 'absolute',
        left: '0px',
        top: '0px',
        width: leftPanelWidth,
        height: topPanelHeight
      }
    })
    panels.push({
      terminal: terminals[1],
      style: {
        position: 'absolute',
        left: rightPanelLeft,
        top: '0px',
        width: rightPanelWidth,
        height: topPanelHeight
      }
    })
    panels.push({
      terminal: terminals[2],
      style: {
        position: 'absolute',
        left: '0px',
        top: bottomPanelTop,
        width: leftPanelWidth,
        height: bottomPanelHeight
      }
    })
    panels.push({
      terminal: terminals[3],
      style: {
        position: 'absolute',
        left: rightPanelLeft,
        top: bottomPanelTop,
        width: rightPanelWidth,
        height: bottomPanelHeight
      }
    })
  } else if (count >= 5) {
    if (props.layoutMode === 'scroll') {
      // 横向滚动模式：每个终端固定500*350px，水平排列
      const minTerminalWidth = 500
      const gap = 8 // 终端之间的间距

      for (let i = 0; i < count; i++) {
        panels.push({
          terminal: terminals[i],
          style: {
            position: 'absolute',
            left: `${ i * (minTerminalWidth + gap) }px`,
            top: '0px',
            width: `${ minTerminalWidth }px`,
            height: '100%' // 高度自适应容器
          }
        })
      }
    } else {
      // 一屏展示模式：动态网格布局，最后一行均分空位
      let cols = Math.ceil(Math.sqrt(count))
      let rows = Math.ceil(count / cols)

      // 限制最小高度：每个终端至少250px高度（包含标题栏32px）
      const minTerminalHeight = 250
      const containerHeight = containerRef.value?.clientHeight || 600
      const maxRows = Math.floor(containerHeight / minTerminalHeight)

      // 如果行数超过最大限制，调整列数
      if (rows > maxRows) {
        rows = maxRows
        cols = Math.ceil(count / rows)
      }

      for (let i = 0; i < count; i++) {
        const row = Math.floor(i / cols)
        const col = i % cols

        // 判断是否为最后一行
        const isLastRow = row === rows - 1
        // 最后一行的终端数量
        const lastRowCount = count - (rows - 1) * cols

        if (isLastRow && lastRowCount < cols) {
          // 最后一行终端数量不足，均分整个宽度
          const lastRowWidth = 100 / lastRowCount
          panels.push({
            terminal: terminals[i],
            style: {
              position: 'absolute',
              left: `${ col * lastRowWidth }%`,
              top: `${ row * (100 / rows) }%`,
              width: `${ lastRowWidth }%`,
              height: `${ 100 / rows }%`,
              minHeight: `${ minTerminalHeight }px`
            }
          })
        } else {
          // 非最后一行或最后一行已满，使用标准网格布局
          const colWidth = 100 / cols
          panels.push({
            terminal: terminals[i],
            style: {
              position: 'absolute',
              left: `${ col * colWidth }%`,
              top: `${ row * (100 / rows) }%`,
              width: `${ colWidth }%`,
              height: `${ 100 / rows }%`,
              minHeight: `${ minTerminalHeight }px`
            }
          })
        }
      }
    }
  }

  return panels
}

// 分割线计算
const calculateDividers = (terminals) => {
  const dividers = []
  const count = terminals.length

  if (count === 2) {
    // 垂直分割线，位于间距中间
    const leftWidth = panelSizes.value.split1 || 50
    dividers.push({
      id: 'divider-1',
      direction: 'vertical',
      style: {
        position: 'absolute',
        left: `calc(${ leftWidth }% - 1px)`, // 分割线2px宽，-1px让它居中在间距中
        top: '0px',
        width: '2px',
        height: '100%',
        cursor: 'col-resize',
        backgroundColor: 'var(--el-border-color)',
        zIndex: 5 // 降低z-index，让活动终端边框可见
      }
    })
  } else if (count === 3) {
    // 垂直分割线 + 水平分割线，都位于间距中间
    const leftWidth = panelSizes.value.split1 || 50
    const rightTopHeight = panelSizes.value.split2 || 50

    dividers.push({
      id: 'divider-1',
      direction: 'vertical',
      style: {
        position: 'absolute',
        left: `calc(${ leftWidth }% - 1px)`,
        top: '0px',
        width: '2px',
        height: '100%',
        cursor: 'col-resize',
        backgroundColor: 'var(--el-border-color)',
        zIndex: 5
      }
    })
    dividers.push({
      id: 'divider-2',
      direction: 'horizontal',
      style: {
        position: 'absolute',
        left: `calc(${ leftWidth }% + 4px)`, // 右侧面板的左边界 + 间距的一半
        top: `calc(${ rightTopHeight }% - 1px)`,
        width: `calc(${ 100 - leftWidth }% - 8px)`, // 右侧面板的宽度
        height: '2px',
        cursor: 'row-resize',
        backgroundColor: 'var(--el-border-color)',
        zIndex: 5
      }
    })
  } else if (count === 4) {
    // 垂直分割线 + 水平分割线，都位于间距中间
    const leftWidth = panelSizes.value.split1 || 50
    const topHeight = panelSizes.value.split2 || 50

    dividers.push({
      id: 'divider-1',
      direction: 'vertical',
      style: {
        position: 'absolute',
        left: `calc(${ leftWidth }% - 1px)`,
        top: '0px',
        width: '2px',
        height: '100%',
        cursor: 'col-resize',
        backgroundColor: 'var(--el-border-color)',
        zIndex: 5
      }
    })
    dividers.push({
      id: 'divider-2',
      direction: 'horizontal',
      style: {
        position: 'absolute',
        left: '0px',
        top: `calc(${ topHeight }% - 1px)`,
        width: '100%',
        height: '2px',
        cursor: 'row-resize',
        backgroundColor: 'var(--el-border-color)',
        zIndex: 5
      }
    })
  }
  // 对于5个及以上的终端，暂时不提供拖拽调整功能（网格布局的分割线tmd有点复杂，先不搞了）

  return dividers
}

// 工具函数
const getStatusColor = (status) => {
  return terminalStatusList.find(item => item.value === status)?.color || 'gray'
}

const setTerminalRef = (el, key) => {
  if (el) {
    terminalRefs.value[key] = el
  }
}

// 事件处理
const handlePanelClick = (terminalKey) => {
  focusedTerminalKey.value = terminalKey
  nextTick(() => {
    terminalRefs.value[terminalKey]?.focusTab()
  })
}

const handleCloseTerminal = (terminalKey) => {
  emit('close-terminal', terminalKey)

  // 关闭终端后，延迟触发resize确保布局重新计算
  nextTick(() => {
    setTimeout(() => {
      Object.values(terminalRefs.value).forEach(ref => {
        ref?.handleResize()
      })
    }, 150)
  })
}

const handleInputCommand = (cmd, uid, terminalKey) => {
  // 如果启用了同步所有会话，则同步输入到其他终端
  if (props.isSyncAllSession) {
    Object.keys(terminalRefs.value).forEach(key => {
      if (key !== terminalKey && terminalRefs.value[key]?.$?.uid !== uid) {
        terminalRefs.value[key]?.inputCommand(cmd, true)
      }
    })
  }

  emit('terminal-input', cmd, uid, terminalKey)
}

const handleTabFocus = (uid) => {
  // 通过uid找到对应的终端key
  const terminal = props.terminalTabs.find(t =>
    terminalRefs.value[t.key]?.$?.uid === uid
  )
  if (terminal) {
    focusedTerminalKey.value = terminal.key
  }
}

const getPingData = (data) => {
  emit('ping-data', data)
}

const resetLongPress = () => {
  emit('reset-long-press')
}

// 拖拽相关
const handleDividerMouseDown = (event, divider) => {
  if (isDragging.value) return

  isDragging.value = true
  dragInfo.value = {
    dividerId: divider.id,
    direction: divider.direction,
    startX: event.clientX,
    startY: event.clientY,
    containerRect: event.currentTarget.parentElement.getBoundingClientRect()
  }

  document.addEventListener('mousemove', handleMouseMove)
  document.addEventListener('mouseup', handleMouseUp)
  event.preventDefault()
}

const handleMouseMove = (event) => {
  if (!isDragging.value || !dragInfo.value) return

  const { dividerId, direction, containerRect } = dragInfo.value
  const count = props.terminalTabs.length

  if (direction === 'vertical') {
    const newPercent = ((event.clientX - containerRect.left) / containerRect.width) * 100

    // 限制最小大小 100px
    const minPercent = (100 / containerRect.width) * 100
    const maxPercent = 100 - minPercent

    const clampedPercent = Math.max(minPercent, Math.min(maxPercent, newPercent))

    if (dividerId === 'divider-1') {
      panelSizes.value.split1 = clampedPercent
    }
  } else if (direction === 'horizontal') {
    const newPercent = ((event.clientY - containerRect.top) / containerRect.height) * 100

    // 对于3个和4个终端的情况，需要考虑每个终端的最小高度250px
    if (count === 3) {
      const minTerminalHeight = 250 // 每个终端最小高度250px

      // 对于3个终端，右侧是垂直分割的两个终端
      // 计算最小和最大百分比，确保右侧上下两个终端都不小于250px
      const minPercentForTop = (minTerminalHeight / containerRect.height) * 100
      const maxPercentForTop = 100 - minPercentForTop

      const clampedPercent = Math.max(minPercentForTop, Math.min(maxPercentForTop, newPercent))

      if (dividerId === 'divider-2') {
        panelSizes.value.split2 = clampedPercent
      }
    } else if (count === 4) {
      const minTerminalHeight = 250 // 每个终端最小高度250px

      // 对于4个终端(2x2网格)
      // 计算最小和最大百分比，确保上下两行都不小于250px
      const minPercentForTop = (minTerminalHeight / containerRect.height) * 100
      const maxPercentForTop = 100 - minPercentForTop

      const clampedPercent = Math.max(minPercentForTop, Math.min(maxPercentForTop, newPercent))

      if (dividerId === 'divider-2') {
        panelSizes.value.split2 = clampedPercent
      }
    } else {
      // 其他情况使用原有逻辑
      const minPercent = (100 / containerRect.height) * 100
      const maxPercent = 100 - minPercent

      const clampedPercent = Math.max(minPercent, Math.min(maxPercent, newPercent))

      if (dividerId === 'divider-2') {
        panelSizes.value.split2 = clampedPercent
      }
    }
  }

  // 触发终端重新计算大小
  nextTick(() => {
    Object.values(terminalRefs.value).forEach(ref => {
      ref?.handleResize()
    })
  })
}

const handleShowScriptInput = (panel) => {
  console.log('handleShowScriptInput', panel)
  scriptInputStates.value[panel.terminal.key] = true
}

const handleCloseScriptInput = (panel) => {
  scriptInputStates.value[panel.terminal.key] = false
}

const handleExecCommand = (panel, command) => {
  scriptInputStates.value[panel.terminal.key] = false
  terminalRefs.value[panel.terminal.key].inputCommand(command)
}

const handleMouseUp = () => {
  isDragging.value = false
  dragInfo.value = null
  document.removeEventListener('mousemove', handleMouseMove)
  document.removeEventListener('mouseup', handleMouseUp)

  // 拖拽完成后再次触发resize确保终端尺寸正确
  nextTick(() => {
    setTimeout(() => {
      Object.values(terminalRefs.value).forEach(ref => {
        ref?.handleResize()
      })
    }, 100)
  })
}

// 同步输入处理已移至 handleInputCommand 中

// 生命周期
onMounted(() => {
  if (props.terminalTabs.length > 0) {
    focusedTerminalKey.value = props.terminalTabs[0].key
  }
})

onBeforeUnmount(() => {
  document.removeEventListener('mousemove', handleMouseMove)
  document.removeEventListener('mouseup', handleMouseUp)
})

// 监听终端变化
watch(() => props.terminalTabs, (newTabs, oldTabs) => {
  if (newTabs.length > 0 && !focusedTerminalKey.value) {
    focusedTerminalKey.value = newTabs[0].key
  }

  // 清理已关闭终端的引用和脚本输入状态
  Object.keys(terminalRefs.value).forEach(key => {
    if (!newTabs.find(tab => tab.key === key)) {
      delete terminalRefs.value[key]
      delete scriptInputStates.value[key]
    }
  })

  // 如果终端数量发生变化，重置面板大小并触发resize
  if (oldTabs && newTabs.length !== oldTabs.length) {
    // 重置面板大小到默认值
    panelSizes.value = {}

    // 延迟触发resize确保布局更新完成
    nextTick(() => {
      setTimeout(() => {
        Object.values(terminalRefs.value).forEach(ref => {
          ref?.handleResize()
        })
      }, 100)
    })
  }
}, { immediate: true })

// 监听布局变化
watch(layoutPanels, () => {
  // 布局变化时触发resize
  nextTick(() => {
    setTimeout(() => {
      Object.values(terminalRefs.value).forEach(ref => {
        ref?.handleResize()
      })
    }, 50)
  })
}, { deep: true })

// 监听终端数量变化，重新计算布局
watch(() => props.terminalTabs.length, () => {
  // 延迟重新计算以确保容器尺寸已更新
  nextTick(() => {
    setTimeout(() => {
      // 先触发布局重新计算
      containerStyle.value
      // 然后触发终端resize
      Object.values(terminalRefs.value).forEach(ref => {
        ref?.handleResize()
      })
    }, 100)
  })
})

// 监听布局模式变化
watch(() => props.layoutMode, () => {
  // 重置面板大小
  panelSizes.value = {}

  // 延迟重新计算以确保布局更新完成
  nextTick(() => {
    setTimeout(() => {
      Object.values(terminalRefs.value).forEach(ref => {
        ref?.handleResize()
      })
    }, 100)
  })
})

// 暴露方法
defineExpose({
  focusTerminal: (key) => {
    focusedTerminalKey.value = key
    nextTick(() => {
      terminalRefs.value[key]?.focusTab()
    })
  },
  resizeTerminals: () => {
    Object.values(terminalRefs.value).forEach(ref => {
      ref?.handleResize()
    })
  },
  inputCommand: (command) => {
    // 在单窗口模式下，向当前聚焦的终端输入命令
    if (focusedTerminalKey.value && terminalRefs.value[focusedTerminalKey.value]) {
      terminalRefs.value[focusedTerminalKey.value].focusTab()
      terminalRefs.value[focusedTerminalKey.value].inputCommand(command)

      // 如果启用了同步所有会话，则同步到其他终端
      if (props.isSyncAllSession) {
        Object.keys(terminalRefs.value).forEach(key => {
          if (key !== focusedTerminalKey.value && terminalRefs.value[key]) {
            terminalRefs.value[key].inputCommand(command, true)
          }
        })
      }
    } else {
      // 如果没有聚焦的终端，则使用第一个可用的终端
      const firstKey = Object.keys(terminalRefs.value)[0]
      if (firstKey && terminalRefs.value[firstKey]) {
        terminalRefs.value[firstKey].focusTab()
        terminalRefs.value[firstKey].inputCommand(command)

        // 如果启用了同步所有会话，则同步到其他终端
        if (props.isSyncAllSession) {
          Object.keys(terminalRefs.value).forEach(key => {
            if (key !== firstKey && terminalRefs.value[key]) {
              terminalRefs.value[key].inputCommand(command, true)
            }
          })
        }
      }
    }
  }
})
</script>

<style lang="scss" scoped>
.single_window_container {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: auto; /* 允许滚动 */
}

.terminal_panels_wrapper {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: auto; /* 允许滚动 */

  &.scroll_mode {
    overflow-x: auto; /* 横向滚动 */
    overflow-y: hidden; /* 隐藏垂直滚动条 */
  }
}

.not_plus_active_wrapper {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background-image: url('@/assets/terminal/single-window.png');
  background-size: 100% 100%;
  background-position: center;
  background-repeat: no-repeat;
}

.terminal_panel {
  border: 2px solid transparent;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  min-height: 250px; /* 设置最小高度250px，确保终端有足够空间 */

  &.active {
    border-color: var(--el-color-primary);
  }
}

.terminal_panels_wrapper.scroll_mode .terminal_panel {
  min-height: 0; /* 横向滚动模式下不限制最小高度 */
  height: 100%; /* 完全自适应容器高度 */
}

.terminal_header {
  height: 32px;
  min-height: 32px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 8px;
  background-color: var(--el-fill-color-light);
  border-bottom: 1px solid var(--el-border-color);
  user-select: none;
}

.terminal_title {
  display: flex;
  align-items: center;
  flex: 1;
  min-width: 0;
}

.terminal_index {
  display: inline-block;
  font-size: 11px;
  color: var(--el-text-color-placeholder);
  background-color: var(--el-fill-color);
  padding: 2px 4px;
  border-radius: 2px;
  margin-right: 6px;
  font-weight: 500;
  min-width: 20px;
  text-align: center;
}

.terminal_status {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 6px;
  transition: all 0.5s;
}

.terminal_name {
  font-size: 12px;
  color: var(--el-text-color-regular);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.script_input_icon {
  cursor: pointer;
  margin-left: 6px;
  &.active {
    color: var(--el-color-primary);
  }
  &:hover {
    color: var(--el-color-primary);
  }
}

.terminal_close {
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  border-radius: 2px;
  transition: all 0.2s;

  &:hover {
    background-color: var(--el-color-danger);
    color: white;
  }
}

.close_icon {
  font-size: 12px;
}

.terminal_content {
  flex: 1;
  min-height: 218px; /* 250px - 32px(标题栏) = 218px，确保终端内容区域有足够的高度 */
  overflow: hidden;
}

.terminal_panels_wrapper.scroll_mode .terminal_content {
  min-height: 0; /* 横向滚动模式下不限制最小高度 */
}

.resize_divider {
  background-color: var(--el-border-color);
  transition: background-color 0.2s;

  &:hover {
    background-color: var(--el-color-primary);
  }

  &.vertical {
    cursor: col-resize;
  }

  &.horizontal {
    cursor: row-resize;
  }
}
</style>

<style lang="scss">
.script_input_dialog {
  .el-dialog__body {
    max-height: 50vh;
    overflow-y: auto;
  }
}
</style>