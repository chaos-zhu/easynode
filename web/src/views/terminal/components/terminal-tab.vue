<template>
  <div class="terminal_tab_container">
    <div
      ref="terminalRef"
      class="terminal_container"
      @contextmenu.prevent="handleRightClick"
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

const { io } = socketIo
const { proxy: { $api, $store, $serviceURI, $notification, $router, $message } } = getCurrentInstance()

const props = defineProps({
  host: {
    required: true,
    type: String
  },
  fontSize: {
    required: false,
    default: 18,
    type: Number
  },
  theme: {
    required: true,
    type: Object
  },
  background: {
    required: true,
    type: [String, null,]
  }
})

const emit = defineEmits(['inputCommand', 'cdCommand',])

const socket = ref(null)
// const commandHistoryList = ref([])
const term = ref(null)
const command = ref('')
const timer = ref(null)
const fitAddon = ref(null)
const searchBar = ref(null)
const isManual = ref(false)
const terminal = ref(null)
const terminalRef = ref(null)

const token = computed(() => $store.token)
const theme = computed(() => props.theme)
const fontSize = computed(() => props.fontSize)
const background = computed(() => props.background)

watch(theme, () => {
  nextTick(() => {
    if (!background.value) terminal.value.options.theme = theme.value
    else terminal.value.options.theme = { ...theme.value, background: '#00000080' }
  })
})

watch(fontSize, () => {
  nextTick(() => {
    terminal.value.options.fontSize = fontSize.value
    fitAddon.value.fit()
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

const getCommand = async () => {
  let { data } = await $api.getCommand(props.host)
  if (data) command.value = data
}

const connectIO = () => {
  const { host } = props
  socket.value = io($serviceURI, {
    path: '/terminal',
    forceNew: false,
    reconnectionAttempts: 1
  })

  socket.value.on('connect', () => {
    console.log('/terminal socket已连接：', socket.value.id)
    socket.value.emit('create', { host, token: token.value })
    socket.value.on('connect_success', () => {
      onData()
      socket.value.on('connect_terminal', () => {
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
    socket.value.on('create_fail', (message) => {
      console.error(message)
      $notification({
        title: '创建失败',
        message,
        type: 'error'
      })
    })
    socket.value.on('token_verify_fail', () => {
      $notification({
        title: 'Error',
        message: 'token校验失败，请重新登录',
        type: 'error'
      })
      $router.push('/login')
    })
    socket.value.on('connect_fail', (message) => {
      console.error(message)
      $notification({
        title: '终端连接失败',
        message,
        type: 'error'
      })
    })
  })

  socket.value.on('disconnect', () => {
    console.warn('terminal websocket 连接断开')
    if (!isManual.value) reConnect()
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

const reConnect = () => {
  socket.value.close && socket.value.close()
  $message.warning('终端连接断开')
  // $messageBox.alert(
  //   '<strong>终端连接断开</strong>',
  //   'Error',
  //   {
  //     dangerouslyUseHTMLString: true,
  //     confirmButtonText: '刷新页面'
  //   }
  // ).then(() => {
  //   location.reload()
  // })
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
  timer.value = setTimeout(() => {
    let temp = []
    let panes = Array.from(document.getElementsByClassName('el-tab-pane'))
    panes.forEach((item, index) => {
      temp[index] = item.style.display
      item.style.display = 'block'
    })
    fitAddon.value?.fit()
    panes.forEach((item, index) => {
      item.style.display = temp[index]
    })
    let { rows, cols } = term.value
    socket.value?.emit('resize', { rows, cols })
    focusTab()
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
    let str = term.value.getSelection()
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
  socket.value.on('output', (str) => {
    term.value.write(str)
    terminalText.value += str
    // console.log(terminalText.value)
  })
  term.value.onData((key) => {
    let acsiiCode = key.codePointAt()
    if (acsiiCode === 22) return handlePaste()
    if (acsiiCode === 6) return searchBar.value.show()
    enterTimer.value = setTimeout(() => {
      if (enterTimer.value) clearTimeout(enterTimer.value)
      if (key === '\r') { // Enter
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
    })
    emit('inputCommand', key)
    socket.value.emit('input', key)
  })
}

const handleRightClick = async () => {
  try {
    const clipboardText = await navigator.clipboard.readText()
    if (!clipboardText) return
    // 移除多余空格与换行符
    const formattedText = clipboardText.trim().replace(/\s+/g, ' ').replace(/\n/g, '')
    if (formattedText.includes('rm -rf /')) return $message.warning(`高危指令,禁止粘贴: ${ formattedText }` )
    socket.value.emit('input', clipboardText)
  } catch (error) {
    $message.warning('右键默认粘贴行为,需要https支持')
  }
}

const handleClear = () => {
  term.value.clear()
}

const handlePaste = async () => {
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
  socket.value.emit('input', command)
}

onMounted(async () => {
  createLocalTerminal()
  await getCommand()
  connectIO()
})

onBeforeUnmount(() => {
  isManual.value = true
  socket.value?.close()
  window.removeEventListener('resize', handleResize)
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

    :deep(.xterm-viewport),
    :deep(.xterm-screen) {
      padding: 0 0 0 10px;
      border-radius: var(--el-border-radius-base);
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
