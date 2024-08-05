<template>
  <div ref="terminalRefs" class="terminal_tab_container" />
</template>

<script setup>
import { ref, onMounted, computed, onBeforeUnmount, getCurrentInstance } from 'vue'
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
  }
})

const emit = defineEmits(['inputCommand',])

const socket = ref(null)
const term = ref(null)
const command = ref('')
const timer = ref(null)
const fitAddon = ref(null)
const searchBar = ref(null)
const isManual = ref(false)
const terminalRefs = ref(null)

const token = computed(() => $store.token)

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
  let terminal = new Terminal({
    rendererType: 'dom',
    bellStyle: 'sound',
    convertEol: true,
    cursorBlink: true,
    disableStdin: false,
    fontSize: 18,
    minimumContrastRatio: 7,
    allowTransparency: true,
    theme: {
      foreground: '#ECECEC',
      background: '#000000', // 'transparent',
      // cursor: 'help',
      selection: '#ff9900',
      lineHeight: 20
    }
  })
  term.value = terminal
  terminal.open(terminalRefs.value)
  terminal.writeln('\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.')
  terminal.writeln('\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.')
  terminal.focus()
  onSelectionChange()
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

const onData = () => {
  socket.value.on('output', (str) => {
    term.value.write(str)
  })
  term.value.onData((key) => {
    let acsiiCode = key.codePointAt()
    if (acsiiCode === 22) return handlePaste()
    if (acsiiCode === 6) return searchBar.value.show()
    emit('inputCommand', key)
    socket.value.emit('input', key)
  })
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

  // background-image: url('@/assets/bg.jpg');
  // background-size: cover;
  // background-repeat: no-repeat;

  :deep(.xterm) {
    height: 100%;
  }

  :deep(.xterm-viewport),
  :deep(.xterm-screen) {
    padding: 0 0 0 10px;
    border-radius: var(--el-border-radius-base);
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
