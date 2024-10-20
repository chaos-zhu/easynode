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

const { CONNECTING, RECONNECTING, CONNECT_SUCCESS, CONNECT_FAIL } = terminalStatus

const { io } = socketIo
const { proxy: { $api, $store, $serviceURI, $notification, $router, $message } } = getCurrentInstance()

const props = defineProps({
  hostObj: {
    required: true,
    type: Object
  }
})

const emit = defineEmits(['inputCommand', 'cdCommand', 'ping-data',])

const socket = ref(null)
// const commandHistoryList = ref([])
const term = ref(null)
const command = ref('')
const timer = ref(null)
const pingTimer = ref(null)
const fitAddon = ref(null)
// const searchBar = ref(null)
const hasRegisterEvent = ref(false)

const socketConnected = ref(false)
const curStatus = ref(CONNECTING)
const terminal = ref(null)
const terminalRef = ref(null)

const token = computed(() => $store.token)
const theme = computed(() => themeList[$store.terminalConfig.theme])
const fontSize = computed(() => $store.terminalConfig.fontSize)
const background = computed(() => $store.terminalConfig.background)
const hostObj = computed(() => props.hostObj)
const hostId = computed(() => hostObj.value.id)
const host = computed(() => hostObj.value.host)
const menuCollapse = computed(() => $store.menuCollapse)
const quickCopy = computed(() => $store.terminalConfig.quickCopy)
const quickPaste = computed(() => $store.terminalConfig.quickPaste)
const autoExecuteScript = computed(() => $store.terminalConfig.autoExecuteScript)

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
    // fitAddon.value.fit()
    handleResize()
  })
})

watch(background, (newVal) => {
  nextTick(() => {
    if (newVal) {
      // terminal.value.options.theme.background = '#00000080'
      terminal.value.options.theme = { ...theme.value, background: '#00000080' }
      terminalRef.value.style.backgroundImage = `url(${ background.value })`
      terminalRef.value.style.backgroundImage = `url(${ background.value })`
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
  if (data) command.value = data
}

const connectIO = () => {
  socket.value = io($serviceURI, {
    path: '/terminal',
    forceNew: false,
    reconnectionAttempts: 1
  })
  socket.value.on('connect', () => {
    console.log('/terminal socket已连接：', hostId.value)

    socketConnected.value = true
    socket.value.emit('create', { hostId: hostId.value, token: token.value })
    socket.value.on('connect_terminal_success', () => {
      if (hasRegisterEvent.value) return // 以下事件连接成功后仅可注册一次, 否则会多次触发. 除非socket重连
      hasRegisterEvent.value = true

      socket.value.on('output', (str) => {
        term.value.write(str)
        terminalText.value += str
      })

      socket.value.on('connect_shell_success', () => {
        curStatus.value = CONNECT_SUCCESS
        onResize()
        onFindText()
        onWebLinks()
        if (command.value) socket.value.emit('input', command.value + '\n')
      })

      // socket.value.on('terminal_command_history', (data) => {
      //   console.log(data)
      //   commandHistoryList.value = data
      // })
    })

    if (pingTimer.value) clearInterval(pingTimer.value)
    pingTimer.value = setInterval(() => {
      socket.value.emit('get_ping', host.value)
    }, 3000)
    socket.value.emit('get_ping', host.value) // 获取服务端到客户端的ping值
    socket.value.on('ping_data', (pingMs) => {
      emit('ping-data', Object.assign({ ip: host.value }, pingMs))
    })

    socket.value.on('token_verify_fail', () => {
      $notification({ title: 'Error', message: 'token校验失败，请重新登录', type: 'error' })
      $router.push('/login')
    })

    socket.value.on('connect_close', () => {
      if (curStatus.value === CONNECT_FAIL) return // 连接失败不需要自动重连
      curStatus.value = RECONNECTING
      console.warn('连接断开,3秒后自动重连: ', hostId.value)
      term.value.write('\r\n连接断开,3秒后自动重连...\r\n')
      socket.value.emit('reconnect_terminal')
    })

    socket.value.on('reconnect_terminal_success', () => {
      curStatus.value = CONNECT_SUCCESS
    })

    socket.value.on('create_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      console.error('n创建失败:', hostId.value, message)
      term.value.write(`\r\n创建失败: ${ message }\r\n`)
    })

    socket.value.on('connect_fail', (message) => {
      curStatus.value = CONNECT_FAIL
      console.error('连接失败:', hostId.value, message)
      term.value.write(`\r\n连接失败: ${ message }\r\n`)
    })
  })

  socket.value.on('disconnect', () => {
    console.warn('terminal websocket 连接断开')
    socket.value.removeAllListeners() // 取消所有监听
    // socket.value.off('output') // 取消output监听,取消onData输入监听，重新注册
    curStatus.value = CONNECT_FAIL
    socketConnected.value = false
    term.value.write('\r\nError: 与面板socket连接断开。请关闭此tab，并检查本地与面板连接是否稳定\r\n')
  })

  socket.value.on('connect_error', (err) => {
    console.error('terminal websocket 连接错误：', err)
    $notification({
      title: '终端连接失败',
      message: '请检查socket服务是否正常',
      type: 'error'
    })
  })
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
    // {
    //   foreground: '#ECECEC',
    //   background: '#000000', // 'transparent',
    //   // cursor: 'help',
    //   selection: '#ff9900',
    //   lineHeight: 20
    // }
  })
  term.value = terminalInstance
  terminalInstance.open(terminalRef.value)
  terminalInstance.writeln('\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.')
  terminalInstance.writeln('\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.')
  terminalInstance.focus()
  onSelectionChange()
  terminal.value = terminalInstance
}

const onResize = () => {
  fitAddon.value = new FitAddon()
  term.value.loadAddon(fitAddon.value)
  fitAddon.value.fit()
  let { rows, cols } = term.value
  socket.value.emit('resize', { rows, cols })
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
    fitAddon.value?.fit()
    let { rows, cols } = term.value
    socket.value?.emit('resize', { rows, cols })

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
  // term.value.off('data', listenerInput)
  term.value.onData((key) => {
    if (socketConnected.value === false) return
    let acsiiCode = key.codePointAt()
    // console.log(acsiiCode)
    if (acsiiCode === 22) return handlePaste() // Ctrl + V
    // if (acsiiCode === 6) return searchBar.value.show() // Ctrl + F
    enterTimer.value = setTimeout(() => {
      if (enterTimer.value) clearTimeout(enterTimer.value)
      if (key === '\r') { // Enter
        if (curStatus.value === CONNECT_FAIL) { // 连接失败&&未正在连接，按回车可触发重连
          curStatus.value = CONNECTING
          term.value.write('\r\n连接中...\r\n')
          socket.value.emit('reconnect_terminal')
          return
        }
        if (curStatus.value === CONNECT_SUCCESS) {
          let cleanText = applyBackspace(filterAnsiSequences(terminalText.value))
          const lines = cleanText.split('\n')
          // console.log('lines: ', lines)
          const lastLine = lines[lines.length - 1].trim()
          // console.log('lastLine: ', lastLine)
          // 截取最后一个提示符后的内容（'$'或'#'后的内容）
          const commandStartIndex = lastLine.lastIndexOf('#') + 1
          const commandText = lastLine.substring(commandStartIndex).trim()
          // console.log('Processed command: ', commandText)
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
