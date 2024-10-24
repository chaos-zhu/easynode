<template>
  <div class="terminal_tab_container">
    <div
      ref="terminalRef"
      class="terminal_container"
      @contextmenu="handleRightClick"
    />
    <!-- <div class="terminal_command_history">
      <CommandHistory :list="commandHistoryList" />
    </div> -->
  </div>
</template>

<script setup>
import { ref, onMounted, computed, onBeforeUnmount, getCurrentInstance, watch, nextTick } from 'vue'
// import CommandHistory from './command_history.vue'
import { Terminal } from '@xterm/xterm'
import '@xterm/xterm/css/xterm.css'
import { FitAddon } from '@xterm/addon-fit'
import { SearchAddon } from '@xterm/addon-search'
// import { SearchBarAddon } from 'xterm-addon-search-bar'
import { WebLinksAddon } from '@xterm/addon-web-links'
import socketIo from 'socket.io-client'
import themeList from 'xterm-theme'
import { terminalStatus } from '@/utils/enum'

const { CONNECTING, CONNECT_SUCCESS, CONNECT_FAIL } = terminalStatus

const { io } = socketIo
const { proxy: { $api, $store, $serviceURI, $notification, $router, $message } } = getCurrentInstance()

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
  }
})

const emit = defineEmits(['inputCommand', 'cdCommand', 'ping-data', 'reset-long-press',])

const socket = ref(null)
// const commandHistoryList = ref([])
const term = ref(null)
const initCommand = ref('')
const timer = ref(null)
const pingTimer = ref(null)
const fitAddon = ref(null)
// const searchBar = ref(null)

const socketConnected = ref(false)
const curStatus = ref(CONNECTING)
const terminal = ref(null)
const terminalRef = ref(null)

const token = computed(() => $store.token)
const theme = computed(() => themeList[$store.terminalConfig.themeName])
const fontSize = computed(() => $store.terminalConfig.fontSize)
const background = computed(() => $store.terminalConfig.background)
const hostObj = computed(() => props.hostObj)
const hostId = computed(() => hostObj.value.id)
const host = computed(() => hostObj.value.host)
const menuCollapse = computed(() => $store.menuCollapse)
const quickCopy = computed(() => $store.terminalConfig.quickCopy)
const quickPaste = computed(() => $store.terminalConfig.quickPaste)
const autoExecuteScript = computed(() => $store.terminalConfig.autoExecuteScript)
const autoReconnect = computed(() => $store.terminalConfig.autoReconnect)
const isPlusActive = computed(() => $store.isPlusActive)
const isLongPressCtrl = computed(() => props.longPressCtrl)
const isLongPressAlt = computed(() => props.longPressAlt)

watch(menuCollapse, () => {
  nextTick(() => {
    handleResize()
  })
})

watch(theme, () => {
  nextTick(() => {
    if (!background.value) terminal.value.options.theme = theme.value
    else terminal.value.options.theme = { ...theme.value, background: '#00000080' }
  })
})

watch(fontSize, () => {
  nextTick(() => {
    terminal.value.options.fontSize = fontSize.value
    handleResize()
  })
})

watch(background, (newVal) => {
  nextTick(() => {
    if (newVal) {
      terminal.value.options.theme = { ...theme.value, background: '#00000080' }
      terminalRef.value.style.backgroundImage = background.value?.startsWith('http') ? `url(${ background.value })` : `${ background.value }`
      // terminalRef.value.style.backgroundImage = `linear-gradient(rgba(0, 0, 0, 0.15), rgba(0, 0, 0, 0.15)), url(${ background.value })`
    } else {
      terminal.value.options.theme = theme.value
      terminalRef.value.style.backgroundImage = null
    }
  })
}, { immediate: true })

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
  socket.value = io($serviceURI, {
    path: '/terminal',
    forceNew: false,
    reconnection: false,
    reconnectionAttempts: 0
  })
  socket.value.on('connect', () => {
    console.log('/terminal socket已连接：', hostId.value)

    socketConnected.value = true
    socket.value.emit('create', { hostId: hostId.value, token: token.value })
    socket.value.on('connect_terminal_success', () => {
      socket.value.on('output', (str) => {
        term.value.write(str)
        terminalText.value += str
      })
      socket.value.on('connect_shell_success', () => {
        curStatus.value = CONNECT_SUCCESS
        shellResize()
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
      emit('ping-data', Object.assign({ ip: host.value }, pingMs))
    })

    socket.value.on('token_verify_fail', () => {
      $notification({ title: 'Error', message: 'token校验失败，请重新登录', type: 'error' })
      $router.push('/login')
    })

    socket.value.on('terminal_print_info', (msg) => {
      term.value.write(`${ msg }\r\n`)
    })

    socket.value.on('connect_close', () => {
      curStatus.value = CONNECT_FAIL
      term.value.write('\r\n\x1b[91m终端主动断开连接, 回车重新发起连接\x1b[0m')
    })

    socket.value.on('connect_terminal_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      term.value.write(`\r\n\x1b[91m连接终端失败: ${ message }, 回车重新发起连接\x1b[0m`)
    })

    socket.value.on('create_terminal_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      term.value.write(`\r\n\x1b[91m创建终端失败: ${ message }, 回车重新发起连接\x1b[0m`)
    })

  })

  socket.value.on('disconnect', (reason) => {
    console.warn('terminal websocket 连接断开:', reason)
    switch (reason) {
      case 'io server disconnect':
        reconnectTerminal(true, '服务端主动断开连接')
        break
      // case 'io client disconnect': // 客户端主动断开连接
      //   break
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
    term.value.write('\r\n\x1b[91mError: 连接失败,请检查EasyNode服务端是否正常\x1b[0m \r\n')
    $notification({
      title: '连接失败',
      message: '请检查EasyNode服务端是否正常',
      type: 'error'
    })
  })
}

const reconnectTerminal = (isCommonTips = false, tips) => {
  socket.value.removeAllListeners()
  socket.value.close()
  socket.value = null
  curStatus.value = CONNECT_FAIL
  socketConnected.value = false
  if (isCommonTips) {
    if (isPlusActive.value && autoReconnect.value) {
      term.value.write(`\r\n\x1b[91m${ tips },自动重连中...\x1b[0m \r\n`)
      connectIO()
    } else {
      term.value.write(`\r\n\x1b[91mError: ${ tips },请重新连接。([功能项->本地设置->快捷操作]中开启自动重连)\x1b[0m \r\n`)
    }
  } else {
    term.value.write(`\n${ tips } \n`)
    connectIO()
  }
}

const createLocalTerminal = () => {
  let terminalInstance = new Terminal({
    rendererType: 'dom',
    bellStyle: 'sound',
    convertEol: true,
    cursorBlink: true,
    disableStdin: false,
    minimumContrastRatio: 7,
    allowTransparency: true,
    fontFamily: 'Cascadia Code, Menlo, monospace',
    fontSize: fontSize.value,
    theme: theme.value
  })
  term.value = terminalInstance
  terminalInstance.open(terminalRef.value)
  terminalInstance.writeln('\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.')
  terminalInstance.writeln('\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.')
  terminalInstance.focus()
  onSelectionChange()
  onFindText()
  onWebLinks()
  onResize()
  terminal.value = terminalInstance
}

const shellResize = () => {
  fitAddon.value.fit()
  let { rows, cols } = term.value
  socket.value?.emit('resize', { rows, cols })
}
const onResize = () => {
  fitAddon.value = new FitAddon()
  term.value.loadAddon(fitAddon.value)
  window.addEventListener('resize', handleResize)
}

const handleResize = () => {
  if (timer.value) clearTimeout(timer.value)
  timer.value = setTimeout(async () => {
    // 由于非当前的el-tab-pane的display属性为none, 调用fitAddon.value?.fit()时无法获取宽高，因此先展示，再fit，最后再隐藏
    let temp = []
    let panes = Array.from(document.getElementsByClassName('el-tab-pane'))
    panes.forEach((item, index) => {
      temp[index] = item.style.display
      item.style.display = 'block'
    })
    shellResize()
    panes.forEach((item, index) => {
      item.style.display = temp[index]
    })
  }, 200)
}

const onWebLinks = () => {
  term.value.loadAddon(new WebLinksAddon())
}

// :TODO: 重写终端搜索功能
const onFindText = () => {
  const searchAddon = new SearchAddon()
  // searchBar.value = new SearchBarAddon({ searchAddon })
  term.value.loadAddon(searchAddon)
  // term.value.loadAddon(searchBar.value)
}

const onSelectionChange = () => {
  term.value.onSelectionChange(() => {
    if (!quickCopy.value) return
    let str = term.value.getSelection()
    console.log(str)
    if (!str) return
    const text = new Blob([str,], { type: 'text/plain' })
    const item = new ClipboardItem({
      'text/plain': text
    })
    navigator.clipboard.write([item,])
  })
}

const terminalText = ref(null)
const enterTimer = ref(null)

function filterAnsiSequences(str) {
  // 使用正则表达式移除ANSI转义序列
  // return str.replace(/\x1b\[[0-9;]*m|\x1b\[?[\d;]*[A-HJKSTfmin]/g, '')
  // eslint-disable-next-line
  return str.replace(/\x1b\[[0-9;]*[mGK]|(\x1b\][0-?]*[0-7;]*\x07)|(\x1b[\[\]()#%;][0-9;?]*[0-9A-PRZcf-ntqry=><])/g, '')
}

// 处理 Backspace，删除前一个字符
function applyBackspace(text) {
  let result = []
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '\b') {
      if (result.length > 0) {
        result.pop()
      }
    } else {
      result.push(text[i])
    }
  }
  return result.join('')
}

function extractLastCdPath(text) {
  const regex = /cd\s+([^\s]+)(?=\s|$)/g
  let lastMatch
  let match
  regex.lastIndex = 0
  while ((match = regex.exec(text)) !== null) {
    lastMatch = match
  }
  return lastMatch ? lastMatch[1] : null
}

const onData = () => {
  term.value.onData((key) => {
    if (!socket.value || !socketConnected.value) return

    if ('\r' === key && curStatus.value === CONNECT_FAIL) {
      reconnectTerminal(false, '重新连接中...')
      return
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
    // if (acsiiCode === 6) return searchBar.value.show() // Ctrl + F
    enterTimer.value = setTimeout(() => {
      if (enterTimer.value) clearTimeout(enterTimer.value)
      if (key === '\r') { // Enter
        if (curStatus.value === CONNECT_SUCCESS) {
          let cleanText = applyBackspace(filterAnsiSequences(terminalText.value))
          const lines = cleanText.split('\n')
          // console.log('lines: ', lines)
          const lastLine = lines[lines.length - 1].trim()
          // console.log('lastLine: ', lastLine)
          // 截取最后一个提示符后的内容（'$'或'#'后的内容）
          const commandStartIndex = lastLine.lastIndexOf('#') + 1
          const commandText = lastLine.substring(commandStartIndex).trim()
          // eslint-disable-next-line
          const cdPath = extractLastCdPath(commandText)

          if (cdPath) {
            console.log('cd command path:', cdPath)
            let firstChar = cdPath.charAt(0)
            if (!['/',].includes(firstChar)) return console.log('err fullpath:', cdPath) // 后端依赖不支持 '~'
            emit('cdCommand', cdPath)
          }
          terminalText.value = ''
        }
      }
    })
    if (curStatus.value !== CONNECT_SUCCESS) return
    emit('inputCommand', key)
    socket.value.emit('input', key)
  })
}

const handleRightClick = async (e) => {
  if (!quickPaste.value) return
  e.preventDefault()
  try {
    const clipboardText = await navigator.clipboard.readText()
    if (!clipboardText) return
    // 移除多余空格与换行符
    const formattedText = clipboardText.trim().replace(/\s+/g, ' ')
    // console.log(formattedText)
    if (formattedText.includes('rm -rf /')) return $message.warning(`高危指令,禁止粘贴: ${ formattedText }`)
    const safeText = formattedText.replace(/\r?\n|\r/g, '')
    // console.log(safeText)
    socket.value.emit('input', safeText)
  } catch (error) {
    $message.warning('右键默认粘贴行为,需要https支持')
  }
}

const handleClear = () => {
  term.value.clear()
}

const handlePaste = async () => {
  if (!quickPaste.value) return
  let key = await navigator.clipboard.readText()
  emit('inputCommand', key)
  socket.value.emit('input', key)
  term.value.focus()
}

const focusTab = () => {
  term.value.blur()
  setTimeout(() => {
    term.value.focus()
  }, 200)
}

const inputCommand = (command) => {
  command = command + (autoExecuteScript.value ? '\n' : '')
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
  socket.value?.close()
  window.removeEventListener('resize', handleResize)
  clearInterval(pingTimer.value)
})

defineExpose({
  focusTab,
  handleResize,
  inputCommand,
  handleClear
})
</script>

<style lang="scss" scoped>
.terminal_tab_container {
  min-height: 200px;
  position: relative;
  .terminal_container {
    background-size: 100% 100%;
    background-repeat: no-repeat;

    :deep(.xterm) {
      height: 100%;
    }

    :deep(.xterm-viewport) {
      overflow-y: auto;
    }

    :deep(.xterm-screen) {
      padding: 0 0 0 10px;
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
