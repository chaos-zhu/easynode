<template>
  <div class="terminal_tab_container">
    <div
      ref="terminalRef"
      class="terminal_container"
      @contextmenu="handleRightClick"
      @mouseup="handleMouseUp"
      @mousedown="emit('tab-focus', uid)"
    />
    <!-- <div class="terminal_command_history">
      <CommandHistory :list="commandHistoryList" />
    </div> -->
    <TerminalSearch
      v-if="term && searchAddon"
      ref="searchBarRef"
      :search-addon="searchAddon"
      :terminal="term"
      @close="handleSearchClose"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, computed, onBeforeUnmount, getCurrentInstance, watch, nextTick } from 'vue'
// import CommandHistory from './command_history.vue'
// 自定义搜索组件，xterm-addon-search-bar已废弃
import TerminalSearch from './terminal-search.vue'
import { Terminal } from '@xterm/xterm'
import '@xterm/xterm/css/xterm.css'
import { CanvasAddon } from '@xterm/addon-canvas'
import { FitAddon } from '@xterm/addon-fit'
import { SearchAddon } from '@xterm/addon-search'
// import { SearchBarAddon } from 'xterm-addon-search-bar'
import { WebLinksAddon } from '@xterm/addon-web-links'
import themeList from 'xterm-theme'
import { terminalStatus } from '@/utils/enum'

import { useContextMenu } from '@/composables/useContextMenu'
import { isDockerId, isDockerComposeYml, generateSocketInstance } from '@/utils'
import useMobileWidth from '@/composables/useMobileWidth'
import { TerminalHighlighter } from '@/utils/highlighter'
import clipboard from '@/utils/clipboard'
import { resolveTerminalRequestId } from '@/composables/agentTerminal'

const { CONNECTING, CONNECT_SUCCESS, CONNECT_FAIL, SUSPENDED } = terminalStatus

const instance = getCurrentInstance()
const { uid } = instance
const { proxy: { $api, $store, $notification, $router, $message, $messageBox } } = instance

const { isMobileScreen } = useMobileWidth()

const props = defineProps({
  hostObj: {
    required: true,
    type: Object
  },
  longPressCtrl: {
    type: Boolean,
    default: false
  },
  longPressAlt: {
    type: Boolean,
    default: false
  },
  isSingleWindow: {
    type: Boolean,
    default: false
  },
  autoFocus: { type: Boolean, default: true },
  // 右侧 AI 面板打开时，避免 xterm 的延迟 focus 抢走输入框焦点。
  suppressFocus: { type: Boolean, default: false },
  showSftpSide: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['inputCommand', 'ping-data', 'reset-long-press', 'tab-focus', 'sync-path-to-sftp', 'request-suspend', 'terminal-ai-input',])

const socket = ref(null)
const aiCommandRequests = new Map()
const AI_CANCEL_CONFIRM_TIMEOUT_MS = 10 * 1000
// const commandHistoryList = ref([])
const term = ref(null)
const highlighter = ref(null)
const initCommand = ref('')
const timer = ref(null)
const pingTimer = ref(null)
const fitAddon = ref(null)
const searchAddon = ref(null)
const searchBarRef = ref(null) // TerminalSearch组件引用
// const searchBar = ref(null)
const socketConnected = ref(false)
const curStatus = ref(CONNECTING)
const sessionId = ref(null) // 会话ID，用于挂起/恢复
const terminalRef = ref(null)
const { showMenu, closeMenu, isVisible } = useContextMenu()

// 临时路径同步回调
const tempPathSyncCallback = ref(null)

const theme = computed(() => themeList[$store.terminalConfig.themeName])
const fontSize = computed(() => $store.terminalConfig.fontSize)
const fontFamily = computed(() => $store.terminalConfig.fontFamily)
const fontColor = computed(() => $store.terminalConfig.fontColor)
const cursorColor = computed(() => $store.terminalConfig.cursorColor)
const selectionColor = computed(() => $store.terminalConfig.selectionColor)
const background = computed(() => $store.terminalConfig.background)
const hostObj = computed(() => props.hostObj)
const hostId = computed(() => hostObj.value.id)
const host = computed(() => hostObj.value.host)
const menuCollapse = computed(() => $store.menuCollapse)
const autoExecuteScript = computed(() => $store.terminalConfig.autoExecuteScript)
const autoReconnect = computed(() => $store.terminalConfig.autoReconnect)
const keywordHighlight = computed(() => $store.terminalConfig.keywordHighlight)
const customHighlightRules = computed(() => $store.terminalConfig.customHighlightRules)
const highlightDebugMode = computed(() => $store.terminalConfig.highlightDebugMode)
const autoShowContextMenu = computed(() => $store.terminalConfig.autoShowContextMenu)
const isPlusActive = computed(() => $store.isPlusActive)
const isLongPressCtrl = computed(() => props.longPressCtrl)
const isLongPressAlt = computed(() => props.longPressAlt)

watch(() => props.suppressFocus, (suppressed) => {
  // xterm 使用隐藏 textarea 接收按键；面板展开时先主动释放它，
  // 再由 AI 输入框接管焦点，避免只显示光标却实际输入到终端。
  if (suppressed) term.value?.blur()
})

// 应用终端主题的公共函数
const applyTerminalTheme = () => {
  if (!term.value || !terminalRef.value) return

  // 构建光标主题
  const cursorTheme = {
    cursor: cursorColor.value || theme.value.cursor,
    cursorAccent: '#000000'
  }

  // 构建完整主题
  const customTheme = {
    ...theme.value,
    ...cursorTheme
  }

  // 应用自定义字体颜色
  if (fontColor.value) {
    customTheme.foreground = fontColor.value
  }

  // 应用自定义选中颜色
  if (selectionColor.value) {
    customTheme.selectionBackground = selectionColor.value
  }

  // 根据背景设置应用主题
  if (background.value) {
    // 有自定义背景：xterm背景透明，使用terminalRef显示背景
    term.value.options.theme = { ...customTheme, background: 'transparent' }
    terminalRef.value.style.backgroundImage = background.value?.startsWith('http')
      ? `url(${ background.value })`
      : `${ background.value }`
    terminalRef.value.style.backgroundColor = ''

    // 设置 viewport 为透明以显示自定义背景
    const viewport = terminalRef.value.querySelector('.xterm-viewport')
    if (viewport) {
      viewport.style.setProperty('background-color', 'transparent', 'important')
    }
  } else {
    // 使用主题背景：清除terminalRef背景，使用xterm主题背景色
    term.value.options.theme = customTheme
    terminalRef.value.style.backgroundImage = ''
    terminalRef.value.style.backgroundColor = ''

    // 设置 viewport 背景色为主题背景色
    const viewport = terminalRef.value.querySelector('.xterm-viewport')
    if (viewport) {
      viewport.style.setProperty('background-color', customTheme.background || '#1e1e1e', 'important')
    }
  }
}

watch(menuCollapse, () => {
  nextTick(() => {
    handleResize()
  })
})

watch(theme, () => nextTick(applyTerminalTheme))
watch(fontColor, () => nextTick(applyTerminalTheme))
watch(cursorColor, () => nextTick(applyTerminalTheme))
watch(selectionColor, () => nextTick(applyTerminalTheme))
watch(background, () => nextTick(applyTerminalTheme), { immediate: true })

watch(fontSize, () => {
  nextTick(() => {
    term.value.options.fontSize = fontSize.value
    handleResize()
  })
})

watch(fontFamily, () => {
  nextTick(() => {
    term.value.options.fontFamily = fontFamily.value
    handleResize()
  })
})

watch(keywordHighlight, (newVal) => {
  if (highlighter.value) {
    highlighter.value.setEnabled(newVal)
  }
})

// 监听自定义高亮规则变化
watch(customHighlightRules, (newRules) => {
  if (highlighter.value) {
    if (highlightDebugMode.value) {
      console.log('自定义高亮规则变化，更新高亮器:', newRules)
    }
    highlighter.value.updateCustomRules(newRules)
  }
}, { deep: true, immediate: true })

// 监听调试模式变化
watch(highlightDebugMode, (newVal) => {
  if (highlighter.value) {
    highlighter.value.setDebugMode(newVal)
  }
})

watch(curStatus, () => {
  console.warn(`status: ${ curStatus.value }`)
  hostObj.value.status = curStatus.value
})

const getCommand = async () => {
  let { data } = await $api.getCommand(hostId.value)
  if (data) initCommand.value = data
}

const connectIO = () => {
  curStatus.value = CONNECTING
  socket.value = generateSocketInstance('/terminal', {
    forceNew: false,
    reconnection: false,
    reconnectionAttempts: 0
  })
  socket.value.on('connect', () => {
    console.log('/terminal socket已连接：', hostId.value)

    socketConnected.value = true

    // 检查是否是恢复会话
    if (hostObj.value.resumeSessionId) {
      // 恢复会话模式：直接尝试恢复
      socket.value.emit('ws_terminal', {
        hostId: hostId.value,
        resumeSessionId: hostObj.value.resumeSessionId
      })
    } else {
      // 正常连接模式：forceNew=true，不自动恢复
      socket.value.emit('ws_terminal', {
        hostId: hostId.value,
        forceNew: true
      })
    }

    // 接收会话ID
    socket.value.on('session_created', ({ sessionId: sid }) => {
      sessionId.value = sid
      console.log('会话已创建:', sid)
    })

    // 处理恢复成功
    socket.value.on('terminal_resumed', ({ sessionId: sid, bufferedOutput }) => {
      sessionId.value = sid
      curStatus.value = CONNECT_SUCCESS

      // 回放缓存的输出
      if (bufferedOutput) {
        if (keywordHighlight.value && highlighter.value) {
          const highlightedStr = highlighter.value.highlightText(bufferedOutput)
          term.value.write(highlightedStr)
        } else {
          term.value.write(bufferedOutput)
        }
      }

      term.value.write('\r\n\x1b[92m═══ 终端已从挂起状态恢复 ═══\x1b[0m\r\n')
      handleResize()

      // 自动发送回车以显示命令提示符
      setTimeout(() => {
        socket.value?.emit('input', '\r')
      }, 100)
    })

    socket.value.on('terminal_connect_success', () => {
      socket.value.on('output', (str) => {
        // 如果有临时路径同步回调，先调用它
        if (tempPathSyncCallback.value) {
          tempPathSyncCallback.value(str)
        }

        if (props.isSingleWindow && !isPlusActive.value) return

        // 使用高亮器处理
        if (keywordHighlight.value && highlighter.value) {
          const highlightedStr = highlighter.value.highlightText(str)
          term.value.write(highlightedStr)
        } else {
          term.value.write(str)
        }
      })
      socket.value.on('terminal_ai_command_echo', ({ command }) => {
        // 服务端执行的是带边界协议的包装命令；这里只展示原始命令。
        if (command) term.value?.write(`${ command }\r\n`)
      })
      socket.value.on('terminal_ai_command_progress', (payload = {}) => {
        aiCommandRequests.get(payload.requestId)?.onProgress?.(payload)
      })
      socket.value.on('terminal_ai_command_result', (payload = {}) => {
        const request = aiCommandRequests.get(payload.requestId)
        if (!request) return
        aiCommandRequests.delete(payload.requestId)
        clearTimeout(request.timeout)
        request.resolve(payload)
      })
      socket.value.on('terminal_connect_shell_success', () => {
        curStatus.value = CONNECT_SUCCESS
        handleResize()
        if (initCommand.value) socket.value.emit('input', initCommand.value + '\n')
      })

      // socket.value.on('terminal_command_history', (data) => {
      //   console.log(data)
      //   commandHistoryList.value = data
      // })
    })

    if (pingTimer.value) clearInterval(pingTimer.value)
    pingTimer.value = setInterval(() => {
      socket.value?.emit('get_ping', host.value)
    }, 3000)
    socket.value.emit('get_ping', host.value) // 获取服务端到客户端的ping值
    socket.value.on('ping_data', (pingMs) => {
      const time = Number(pingMs?.time)
      emit('ping-data', { host: host.value, time: Number.isFinite(time) ? time.toFixed(0) : 0 })
    })

    socket.value.on('terminal_print_info', (msg) => {
      term.value.write(`${ msg }\r\n`)
    })

    socket.value.on('terminal_connect_close', () => {
      curStatus.value = CONNECT_FAIL
      term.value.write('\r\n\x1b[91m终端主动断开连接, 回车重新发起连接\x1b[0m')
    })

    socket.value.on('terminal_connect_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      term.value.write(`\r\n\x1b[91m连接终端失败: ${ message }, 回车重新发起连接\x1b[0m`)
    })

    socket.value.on('terminal_create_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      term.value.write(`\r\n\x1b[91m创建终端失败: ${ message }, 回车重新发起连接\x1b[0m`)
    })

  })

  socket.value.on('disconnect', (reason) => {
    for (const [requestId, request,] of aiCommandRequests.entries()) {
      aiCommandRequests.delete(requestId)
      clearTimeout(request.timeout)
      request.resolve({ ok: false, error: '终端连接已断开，无法读取命令输出' })
    }
    console.warn('terminal websocket 连接断开:', reason)
    switch (reason) {
      case 'io server disconnect':
        reconnectTerminal(true, '服务端主动断开连接')
        break
      case 'io client disconnect': // 客户端主动断开连接
        break
      case 'transport close':
        reconnectTerminal(true, '本地网络连接异常')
        break
      case 'transport error':
        reconnectTerminal(true, '建立连接错误')
        break
      case 'parse error':
        reconnectTerminal(true, '数据解析错误')
        break
      default:
        reconnectTerminal(true, '连接意外断开')
    }
  })

  socket.value.on('connect_error', (err) => {
    console.error('EasyNode服务端连接错误：', err)
    curStatus.value = CONNECT_FAIL
    term.value.write('\r\n\x1b[91mError: 连接失败,请检查EasyNode服务端是否正常, 回车重新发起连接\x1b[0m \r\n')
    $notification({
      title: '服务端连接失败',
      message: '请检查EasyNode服务端是否正常',
      type: 'error'
    })
  })
}

const reconnectTerminal = (isCommonTips = false, tips) => {
  socket.value.removeAllListeners()
  socket.value.close()
  socket.value = null
  socketConnected.value = false
  if (isCommonTips) {
    if (autoReconnect.value) {
      term.value.write(`\r\n\x1b[91m${ tips },自动重连中...\x1b[0m \r\n`)
      connectIO()
    } else {
      term.value.write(`\r\n\x1b[91mError: ${ tips },请重新连接。([终端设置->其他设置]中开启自动重连)\x1b[0m \r\n`)
    }
  } else {
    term.value.write(`\r\n\x1b[91m${ tips }\x1b[0m \r\n`)
    connectIO()
  }
}

const createLocalTerminal = () => {
  let terminalInstance = new Terminal({
    bellStyle: 'sound',
    convertEol: false,
    cursorBlink: true,
    disableStdin: false,
    minimumContrastRatio: 1, // 无对比度要求
    allowTransparency: true,
    allowProposedApi: true, // 搜索装饰
    fontFamily: fontFamily.value,
    fontSize: fontSize.value,
    theme: theme.value,
    scrollback: 10000, // 缓冲行数
    tabStopWidth: 4,
    windowsMode: false, // 禁用Windows模式提升性能
    macOptionIsMeta: true, // macOS优化
    smoothScrollDuration: 0 // 平滑滚动时间
  })

  const canvasAddon = new CanvasAddon()
  // const webglAddon = new WebglAddon()

  // Canvas渲染器错误处理
  // if (canvasAddon.onContextLoss) {
  //   canvasAddon.onContextLoss(() => {
  //     console.warn('Canvas context lost, attempting to recover...')
  //   })
  // }
  // terminalInstance.loadAddon(canvasAddon)
  term.value = terminalInstance
  terminalInstance.open(terminalRef.value)
  !isMobileScreen.value && terminalInstance.loadAddon(canvasAddon)

  // 初始化TerminalHighlighter
  highlighter.value = new TerminalHighlighter(terminalInstance, {
    enabled: keywordHighlight.value,
    debugMode: highlightDebugMode.value || false,
    customRules: customHighlightRules.value
  })

  terminalInstance.writeln('\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.')
  terminalInstance.writeln('\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.')
  if (props.autoFocus && !props.suppressFocus) {
    terminalInstance.focus()
    emit('tab-focus', uid)
  }
  onFindText()
  onWebLinks()
  onResize()

  // 初始化主题设置
  nextTick(() => {
    applyTerminalTheme()
  })
}

const shellResize = () => {
  // 由于非当前的el-tab-pane的display属性为none, 调用fitAddon.value?.fit()时无法获取宽高，因此先展示，再fit，最后再隐藏
  let temp = []
  let panes = Array.from(document.getElementsByClassName('el-tab-pane'))
  panes.forEach((item, index) => {
    temp[index] = item.style.display
    item.style.display = 'block'
  })

  fitAddon.value.fit()
  let { rows, cols } = term.value
  socket.value?.emit('resize', { rows, cols })
  term.value?.scrollToBottom()

  panes.forEach((item, index) => {
    item.style.display = temp[index]
  })
}

const onResize = () => {
  fitAddon.value = new FitAddon()
  term.value.loadAddon(fitAddon.value)
  window.addEventListener('resize', handleResize)
}

const handleResize = () => {
  if (timer.value) clearTimeout(timer.value)
  timer.value = setTimeout(() => {
    shellResize()
  }, 200)
}

const onWebLinks = () => {
  term.value.loadAddon(new WebLinksAddon((event, uri) => {
    if (event.ctrlKey || event.altKey) window.open(uri, '_blank')
  }))
}

// 终端搜索功能
const onFindText = () => {
  searchAddon.value = new SearchAddon()
  term.value.loadAddon(searchAddon.value)
}

// 显示搜索框
const showSearchBar = () => {
  searchBarRef.value?.show()
}

// 关闭搜索框，重新聚焦终端
const handleSearchClose = () => {
  if (!props.suppressFocus) term.value?.focus()
}

const enterTimer = ref(null)

const onData = () => {
  term.value.onData((key) => {
    if ('\r' === key && curStatus.value === CONNECT_FAIL) {
      reconnectTerminal(false, '重新连接中...')
      return
    }
    if (!socket.value || !socketConnected.value) return

    // 检查是否按下ESC键且右键菜单正在显示
    if (key === '\x1b') { // ESC键的ASCII码是27，对应字符是'\x1b'
      if (isVisible.value) return closeMenu()
    }

    if (isLongPressCtrl.value || isLongPressAlt.value) {
      const keyCode = key.toUpperCase().charCodeAt(0)
      console.log('keyCode: ', keyCode)
      const ansiCode = keyCode - 64
      console.log('ansiCode:', ansiCode)
      if (ansiCode >= 1 && ansiCode <= 26) {
        const controlChar = String.fromCharCode(ansiCode)
        socket.value.emit('input', isLongPressCtrl.value ? controlChar : `\x1b${ key }`)
      }
      emit('reset-long-press')
      return
    }

    let acsiiCode = key.codePointAt()
    // console.log(acsiiCode)
    if (acsiiCode === 22) return handlePaste() // Ctrl + V
    if (acsiiCode === 6) return showSearchBar() // Ctrl + F
    enterTimer.value = setTimeout(() => {
      if (enterTimer.value) clearTimeout(enterTimer.value)
    })
    if (curStatus.value !== CONNECT_SUCCESS) return
    emit('inputCommand', key, uid)
    socket.value.emit('input', key)
  })
}

const handleCopySelection = async () => {
  let str = term.value.getSelection().trim()
  if (!str) return

  await clipboard.copy(str)
  term.value.clearSelection()
}

const handleMouseUp = async (e) => {
  if (e.button === 1) return handlePaste() // 鼠标中键粘贴
  if (e.button === 0) {
    let str = term.value.getSelection().trim()
    if (!str) return closeMenu()
    // 根据配置决定是否自动显示右键菜单
    if (autoShowContextMenu.value) {
      handleRightClick(e)
    }
  }
}

const plusTips = () => {
  if (!isPlusActive.value) {
    // $message.warning('Plus功能未激活')
    $messageBox.confirm('Plus功能未激活', 'Warning', {
      confirmButtonText: '前往设置',
      cancelButtonText: '取消',
      type: 'warning'
    })
      .then(async () => {
        $router.push('/setting?tabKey=plus')
      })
    return false
  }
  return true
}

const syncPathToSftp = () => {
  if (curStatus.value !== CONNECT_SUCCESS) {
    $message.warning('终端未连接')
    return
  }

  // 监听一次输出，提取路径
  let outputBuffer = ''
  let pathFound = false

  tempPathSyncCallback.value = (str) => {
    outputBuffer += str

    // 清理ANSI转义序列

    const cleanBuffer = outputBuffer.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '').replace(/\x1b\][^\x07]*\x07/g, '')

    // 查找路径（以/开头的行）
    const lines = cleanBuffer.split(/\r?\n/)
    for (const line of lines) {
      const trimmed = line.trim()

      // 匹配路径：以/开头，长度合理
      if (trimmed.startsWith('/') && !pathFound && trimmed.length > 1 && trimmed.length < 500) {
        // 进一步清理：只保留路径部分，去除可能的提示符
        const pathMatch = trimmed.match(/^(\/[^\s]*?)(?:\s|$)/)
        if (pathMatch) {
          const cleanPath = pathMatch[1]
          pathFound = true
          // 找到路径，通过emit发送给父组件
          emit('sync-path-to-sftp', cleanPath)
          tempPathSyncCallback.value = null
          $message.success(`已同步路径: ${ cleanPath }`)
          break
        }
      }
    }

    // 限制缓冲区大小，防止无限增长
    if (outputBuffer.length > 1000) {
      tempPathSyncCallback.value = null
      if (!pathFound) {
        $message.error('未能获取路径')
      }
    }
  }

  // 设置超时，防止一直监听
  setTimeout(() => {
    if (tempPathSyncCallback.value) {
      tempPathSyncCallback.value = null
      if (!pathFound) {
        $message.error('同步路径超时')
      }
    }
  }, 3000)

  // 延迟发送pwd命令
  setTimeout(() => {
    socket.value.emit('input', 'pwd\n')
  }, 100)
}

const handleRightClick = async (e) => {
  let str = term.value.getSelection().trim()
  const sendToAI = str ? {
    label: '发送到AI会话',
    onClick: () => {
      emit('terminal-ai-input', `\`\`\`shell\n${ str }\n\`\`\`\n`)
      term.value.clearSelection()
    }
  } : null
  const search = {
    label: '查找',
    onClick: () => {
      showSearchBar()
      term.value.clearSelection()
    }
  }
  const paste = {
    label: '粘贴',
    onClick: () => {
      handlePaste()
      term.value.clearSelection()
    }
  }
  const copySelection = str ? {
    label: '复制',
    onClick: async () => {
      await handleCopySelection()
      focusTab()
    }
  } : null
  const pasteSelection = str ? {
    label: '粘贴选中内容',
    onClick: async () => {
      await handleCopySelection()
      handlePaste()
    }
  } : null
  const clear = {
    label: '清屏',
    onClick: () => {
      handleClear()
    }
  }
  const reconnect = {
    label: '重新连接',
    onClick: () => {
      reconnectTerminal(false, '重新连接中...')
      term.value.clearSelection()
      focusTab()
    }
  }
  const syncToSftp = props.showSftpSide ? {
    label: '同步目录到SFTP',
    onClick: () => {
      syncPathToSftp()
      term.value.clearSelection()
      focusTab()
    }
  } : null
  const dockerId = isDockerId(str) ? {
    label: 'docker容器ID',
    children: [
      {
        label: '[plus]检测选中内容可能为docker容器ID',
        disabled: true
      },
      {
        label: `登录: docker exec -it ${ str } sh \n`,
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand(`docker exec -it ${ str } sh \n`)
        }
      },
      {
        label: `停止: docker stop ${ str }`,
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand(`docker stop ${ str } \n`)
        }
      },
      {
        label: `重启: docker restart ${ str }`,
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand(`docker restart ${ str } \n`)
        }
      },
      {
        label: `删除: docker rm -f ${ str }`,
        onClick: () => {
          if (!plusTips()) return
          $messageBox.confirm(`确认删除该容器：${ str }`, 'Warning', {
            confirmButtonText: '确定',
            cancelButtonText: '取消',
            type: 'warning'
          })
            .then(async () => {
              focusTab()
              inputCommand(`docker rm -f ${ str } \n`)
            })
        }
      },
      {
        label: `日志: docker logs -f ${ str }`,
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand(`docker logs --tail=500 -f ${ str }`)
        }
      },
    ]
  } : null

  const dockerComposeYml = isDockerComposeYml(str) ? {
    label: 'docker compose文件',
    children: [
      {
        label: '[plus]检测选中内容可能为docker compose文件',
        disabled: true
      },
      {
        label: '启动: docker compose up -d',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose up -d')
        }
      },
      {
        label: '停止并删除: docker compose down',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose down')
        }
      },
      {
        label: '重启: docker compose restart',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose restart')
        }
      },
      {
        label: '查看日志: docker compose logs -f',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose logs -f')
        }
      },
      {
        label: '拉取新镜像: docker compose pull',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose pull')
        }
      },
      {
        label: '重建: docker compose up -d --force-recreate',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose up -d --force-recreate')
        }
      },
      {
        label: '升级镜像: pull && down && up -d',
        onClick: () => {
          if (!plusTips()) return
          focusTab()
          inputCommand('docker compose pull && docker compose down && docker compose up -d')
        }
      },
    ]
  } : null

  // 挂起选项（仅在已连接状态显示）
  const suspend = curStatus.value === CONNECT_SUCCESS ? {
    label: '挂起',
    onClick: () => {
      emit('request-suspend')
      term.value.clearSelection()
    }
  } : null

  const menu = [
    sendToAI,
    copySelection,
    paste,
    pasteSelection,
    search,
    clear,
    reconnect,
    suspend,
    syncToSftp,
    dockerId,
    dockerComposeYml,
  ].filter(Boolean)
  showMenu(e, menu)
}

const handleClear = () => {
  term.value.clearSelection()
  term.value.clear()
  term.value.focus()
}

const handlePaste = async () => {
  try {
    let key = await clipboard.paste()
    // 规范换行符：无论来自 Windows (\r\n) 还是 Unix (\n)，都统一替换成 \r
    key = key.replace(/\r\n/g, '\r').replace(/\n/g, '\r')
    // 如果粘贴的内容以换行符结尾则去掉换行符(防止自动执行)
    while (key.endsWith('\n')) {
      key = key.slice(0, -1)
    }

    emit('inputCommand', key, uid)
    socket.value.emit('input', key)
    term.value.focus()
    term.value.clearSelection()
  } catch (err) {
    // HTTP环境下无法读取剪贴板,提示用户使用浏览器原生粘贴
    console.warn('剪贴板读取失败,请使用 Ctrl+V 或右键粘贴:', err.message)
    // 不显示错误提示,因为 Ctrl+V 会触发浏览器原生粘贴事件
  }
}

const focusTab = () => {
  if (props.suppressFocus) return
  term.value.blur()
  setTimeout(() => {
    // 部分 tab 切换会留下延迟 focus；再次判断，不能覆盖已打开的 AI 输入框。
    if (props.suppressFocus) return
    term.value.focus()
    emit('tab-focus', uid)
  }, 200)
}

const inputCommand = (command, type = 'input', useBase64 = false) => {
  if (type === 'script') {
    if (useBase64) {
      // 使用Base64管道模式执行
      // 粘贴自 Windows/VSCode 的脚本可能包含 CRLF，先统一为 LF，避免 bash 将 \r 带入 read/case 等逻辑
      const normalizedCommand = command.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
      // 处理 UTF-8 字符：使用现代浏览器的 TextEncoder API
      const utf8Bytes = new TextEncoder().encode(normalizedCommand)
      const encodedScript = btoa(String.fromCharCode(...utf8Bytes))
      command = `tmp_script=$(mktemp /tmp/easynode-script-XXXXXX.sh) && printf '%s' '${ encodedScript }' | base64 -d > "$tmp_script" && chmod +x "$tmp_script" && bash "$tmp_script"; script_status=$?; [ -n "$tmp_script" ] && rm -f "$tmp_script"; unset tmp_script${ autoExecuteScript.value ? '\n' : '' }`
    } else {
      // 直接发送模式：根据脚本执行模式添加换行符
      command = command + (autoExecuteScript.value ? '\n' : '')
    }
  }
  socket.value.emit('input', command)
}

onMounted(async () => {
  createLocalTerminal()
  await getCommand()
  connectIO()
  await nextTick()
  onData()
})

onBeforeUnmount(() => {
  for (const [requestId, request,] of aiCommandRequests.entries()) {
    aiCommandRequests.delete(requestId)
    clearTimeout(request.timeout)
    request.resolve({ ok: false, error: '终端已关闭，无法读取命令输出' })
  }
  socket.value?.close()
  window.removeEventListener('resize', handleResize)
  clearInterval(pingTimer.value)
  tempPathSyncCallback.value = null
})

// 挂起终端
const suspendTerminal = () => {
  if (!plusTips()) return
  return new Promise((resolve) => {
    if (!sessionId.value) {
      $message.warning('会话未建立，无法挂起')
      resolve(false)
      return
    }

    if (curStatus.value !== CONNECT_SUCCESS) {
      $message.warning('终端未连接，无法挂起')
      resolve(false)
      return
    }

    let resolved = false // 防止重复resolve
    let timeoutId = null

    const cleanup = () => {
      if (timeoutId) {
        clearTimeout(timeoutId)
        timeoutId = null
      }
      socket.value?.off('terminal_suspended', onSuspended)
      socket.value?.off('suspend_fail', onFail)
    }

    const onSuspended = () => {
      if (resolved) return
      resolved = true
      cleanup()

      curStatus.value = SUSPENDED

      // 断开WebSocket（不触发重连）
      socket.value.removeAllListeners()
      socket.value.disconnect()
      socket.value = null
      socketConnected.value = false

      resolve(true)
    }

    const onFail = (msg) => {
      if (resolved) return
      resolved = true
      cleanup()

      $message.error(`挂起失败: ${ msg }`)
      resolve(false)
    }

    socket.value.emit('suspend_terminal', { sessionId: sessionId.value })
    socket.value.once('terminal_suspended', onSuspended)
    socket.value.once('suspend_fail', onFail)

    // 超时处理
    timeoutId = setTimeout(() => {
      if (resolved) return
      resolved = true
      cleanup()

      $message.warning('挂起操作超时')
      resolve(false)
    }, 5000)
  })
}

const getTerminalContext = ({ maxLines = 160, maxChars = 12 * 1024 } = {}) => {
  const buffer = term.value?.buffer?.active
  if (!buffer) return ''

  const start = Math.max(0, buffer.length - maxLines)
  const lines = []
  for (let index = start; index < buffer.length; index++) {
    lines.push(buffer.getLine(index)?.translateToString(true) || '')
  }
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop()
  const output = lines.join('\n')
  return output.length > maxChars ? output.slice(-maxChars) : output
}

const executeAiCommand = (command, options = {}) => {
  if (!socket.value?.connected || curStatus.value !== CONNECT_SUCCESS) {
    return { ok: false, error: '终端连接已断开，无法执行指令' }
  }
  const input = String(command || '').trim()
  if (!input) return { ok: false, error: '终端命令不能为空' }

  const requestId = resolveTerminalRequestId(options)
  if (aiCommandRequests.has(requestId)) {
    return Promise.resolve({ ok: false, error: '终端命令请求标识重复，未执行指令' })
  }

  let resolveRequest
  const promise = new Promise((resolve) => {
    resolveRequest = resolve
  })
  const timeout = setTimeout(() => {
    if (!aiCommandRequests.has(requestId)) return
    aiCommandRequests.delete(requestId)
    resolveRequest({ ok: false, error: '等待终端命令结果超时' })
  }, 61 * 60 * 1000)

  aiCommandRequests.set(requestId, {
    resolve: resolveRequest,
    promise,
    timeout,
    cancelPromise: null,
    onProgress: options.onProgress
  })

  try {
    socket.value.emit('ai_terminal_command', { requestId, command: input })
  } catch (error) {
    aiCommandRequests.delete(requestId)
    clearTimeout(timeout)
    resolveRequest({ ok: false, error: `写入终端失败: ${ error.message }` })
  }

  return promise
}

const cancelAiCommand = (requestId) => {
  const request = requestId ? aiCommandRequests.get(requestId) : null
  if (!request) return Promise.resolve({ ok: false, error: '终端命令请求已结束，无法确认中断状态' })
  if (!socket.value?.connected) {
    return Promise.resolve({ ok: false, error: '终端连接已断开，无法确认远端命令已停止' })
  }
  if (request.cancelPromise) return request.cancelPromise

  let confirmTimer
  const timeout = new Promise((resolve) => {
    confirmTimer = setTimeout(() => resolve({
      ok: false,
      error: '在 10 秒内未收到终端结束确认，远端命令可能仍在运行'
    }), AI_CANCEL_CONFIRM_TIMEOUT_MS)
  })

  try {
    socket.value.emit('ai_terminal_command_cancel', { requestId })
  } catch (error) {
    return Promise.resolve({ ok: false, error: `发送中断请求失败: ${ error.message }` })
  }

  request.cancelPromise = Promise.race([
    request.promise.then((result) => result?.ok
      ? { ok: true, exitCode: result.exitCode }
      : { ok: false, error: result?.error || '终端未确认远端命令已停止' }),
    timeout,
  ]).finally(() => clearTimeout(confirmTimer))
  return request.cancelPromise
}

const executeManualCommand = (command) => {
  if (!socket.value?.connected || curStatus.value !== CONNECT_SUCCESS) {
    return { ok: false, error: '终端连接已断开，无法执行指令' }
  }
  const input = String(command || '').trim()
  if (!input) return { ok: false, error: '终端命令不能为空' }
  socket.value.emit('input', `${ input }\n`)
  return { ok: true }
}

const isAiTerminalConnected = () => Boolean(socket.value?.connected && curStatus.value === CONNECT_SUCCESS)

defineExpose({
  focusTab,
  handleResize,
  inputCommand,
  handleClear,
  getTerminalContext,
  executeAiCommand,
  cancelAiCommand,
  executeManualCommand,
  isAiTerminalConnected,
  suspendTerminal, // 新增
  sessionId // 新增
})
</script>

<style lang="scss" scoped>
.terminal_tab_container {
  height: 100%;
  min-height: 200px;
  position: relative;
  .terminal_container {
    background-size: 100% 100%;
    background-repeat: no-repeat;
    :deep(.xterm) {
      height: 100%;
      padding: 8px 8px;
    }

    :deep(.xterm-viewport) {
      overflow-y: auto;
      background-color: transparent !important;
    }

    :deep(.xterm-screen) {
      padding: 0;
    }
  }
  .terminal_command_history {
    width: 200px;
    height: 100%;
    overflow: auto;
    position: absolute;
    top: 0;
    right: 0;
    z-index: 1;
    background-color: #fff;
    border-radius: 6px
  }
}
</style>

<style lang="scss">
.terminals {
  .el-tabs__header {
    padding-left: 55px;
  }
}
</style>
