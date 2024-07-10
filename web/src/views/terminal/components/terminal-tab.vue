<template>
  <header>
    <!-- 功能 -->
    <!-- <el-button type="primary" @click="handleClear">
      清空
    </el-button>
    <el-button type="primary" @click="handlePaste">
      粘贴
    </el-button> -->
  </header>
  <div ref="terminal" class="terminal-container" />
</template>

<script>
import { Terminal } from 'xterm'
import 'xterm/css/xterm.css'
import { FitAddon } from 'xterm-addon-fit'
import { SearchAddon } from 'xterm-addon-search'
import { SearchBarAddon } from 'xterm-addon-search-bar'
import { WebLinksAddon } from 'xterm-addon-web-links'
import socketIo from 'socket.io-client'

const { io } = socketIo
export default {
  name: 'Terminal',
  props: {
    token: {
      required: true,
      type: String
    },
    host: {
      required: true,
      type: String
    }
  },
  data() {
    return {
      socket: null,
      term: null,
      command: '',
      timer: null,
      fitAddon: null,
      searchBar: null,
      isManual: false // 是否手动断开的socket连接
    }
  },
  async mounted() {
    this.createLocalTerminal()
    await this.getCommand()
    this.connectIO()
  },
  beforeUnmount() {
    // this.term.dispose() // 销毁终端
    this.isManual = true
    this.socket?.close() // 关闭socket连接
    window.removeEventListener('resize', this.handleResize) // 移除resize监听
  },
  methods: {
    async getCommand() {
      let { data } = await this.$api.getCommand(this.host)
      if(data) this.command = data
    },
    connectIO() {
      let { host, token } = this
      this.socket = io(this.$serviceURI, {
        path: '/terminal',
        forceNew: false, // 强制新的连接
        reconnectionAttempts: 1 // 尝试重新连接次数
      })
      this.socket.on('connect', () => {
        console.log('/terminal socket已连接：', this.socket.id)
        // 验证身份并连接终端
        this.socket.emit('create', { host, token })
        this.socket.on('connect_success', () => {
          this.onData() // 监听输入输出
          this.socket.on('connect_terminal', () => {
            this.onResize() // 自适应窗口(终端创建完成再适应)
            this.onFindText() // 查找插件
            this.onWebLinks() // link链接识别插件
            if(this.command) this.socket.emit('input', this.command + '\n')
          })
        })
        this.socket.on('create_fail', (message) => {
          console.error(message)
          this.$notification({
            title: '创建失败',
            message,
            type: 'error'
          })
        })
        this.socket.on('token_verify_fail', () => {
          this.$notification({
            title: 'Error',
            message: 'token校验失败，请重新登录',
            type: 'error'
          })
          this.$router.push('/login')
        })
        this.socket.on('connect_fail', (message) => {
          console.error(message)
          this.$notification({
            title: '连接失败',
            message,
            type: 'error'
          })
        })
      })
      this.socket.on('disconnect', () => {
        console.warn('terminal websocket 连接断开')
        if(!this.isManual) this.reConnect()
      })
      this.socket.on('connect_error', (err) => {
        console.error('terminal websocket 连接错误：', err)
        this.$notification({
          title: '终端连接失败',
          message: '请检查socket服务是否正常',
          type: 'error'
        })
      })
    },
    reConnect() {
      this.socket.close && this.socket.close()
      this.$messageBox.alert(
        '<strong>终端连接断开</strong>',
        'Error',
        {
          dangerouslyUseHTMLString: true,
          confirmButtonText: '刷新页面'
        }
      ).then(() => {
        // this.fitAddon && this.fitAddon.dispose()
        // this.term && this.term.dispose()
        // this.connectIO()
        location.reload()
      })
    },
    createLocalTerminal() {
      // https://xtermjs.org/docs/api/terminal/interfaces/iterminaloptions/
      let term = new Terminal({
        rendererType: 'dom', // 渲染类型 canvas dom
        bellStyle: 'sound',
        // bellSound: './tip.mp3',
        convertEol: true, // 启用时，光标将设置为下一行的开头
        cursorBlink: true, // 光标闪烁
        disableStdin: false, // 是否应禁用输入
        fontSize: 18,
        minimumContrastRatio: 7, // 文字对比度
        theme: {
          foreground: '#ECECEC', // 字体
          background: '#000000', // 背景色
          cursor: 'help', // 设置光标
          selection: '#ff9900', // 选择文字颜色
          lineHeight: 20
        }
      })
      this.term = term
      term.open(this.$refs['terminal'])
      term.writeln('\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.')
      term.writeln('\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.')
      // 换行并输入起始符 $
      // term.prompt = () => {
      //   term.write('\r\n\x1b[33m$ \x1b[0m ')
      // }
      term.focus()
      this.onSelectionChange()
    },
    onResize() {
      this.fitAddon = new FitAddon()
      this.term.loadAddon(this.fitAddon)
      this.fitAddon.fit()
      let { rows, cols } = this.term
      this.socket.emit('resize', { rows, cols }) // 首次fit完成后resize一次
      window.addEventListener('resize', this.handleResize)
    },
    handleResize() {
      if(this.timer) clearTimeout(this.timer)
      this.timer = setTimeout(() => {
        let temp = []
        let panes= Array.from(document.getElementsByClassName('el-tab-pane'))
        // 先block
        panes.forEach((item, index) => {
          temp[index] = item.style.display
          item.style.display = 'block'
        })
        this.fitAddon?.fit() // 需要获取元素宽度(而element tab组件会display:none隐藏非当前tab)
        // 还原
        panes.forEach((item, index) => {
          item.style.display = temp[index]
        })
        let { rows, cols } = this.term
        // console.log('resize: ', { rows, cols })
        this.socket?.emit('resize', { rows, cols })
      }, 200)
    },
    onWebLinks() {
      this.term.loadAddon(new WebLinksAddon())
    },
    onFindText() {
      const searchAddon = new SearchAddon()
      this.searchBar = new SearchBarAddon({ searchAddon })
      this.term.loadAddon(searchAddon)
      // searchAddon.findNext('SSH', { decorations: { activeMatchBackground: '#ff0000' } })
      this.term.loadAddon(this.searchBar)
      // this.searchBar.show()
    },
    onSelectionChange() {
      this.term.onSelectionChange(() => {
        let str = this.term.getSelection()
        if(!str) return
        const text = new Blob([str,], { type: 'text/plain' })
        // eslint-disable-next-line no-undef
        const item = new ClipboardItem({
          'text/plain': text
        })
        navigator.clipboard.write([item,])
        // this.$message.success('copy success')
      })
    },
    onData() {
      this.socket.on('output', (str) => {
        this.term.write(str)
      })
      this.term.onData((key) => {
        let acsiiCode = key.codePointAt()
        // console.log(acsiiCode)
        if(acsiiCode === 22) return this.handlePaste() // ctrl + v
        if(acsiiCode === 6) return this.searchBar.show() // ctrl + f
        this.socket.emit('input', key)
      })
      // this.term.onKey(({ key }) => { // , domEvent
      //   // https://blog.csdn.net/weixin_30311605/article/details/98277379
      //   let acsiiCode = key.codePointAt() // codePointAt转换成ASCII码
      //   // console.log({ acsiiCode, domEvent })
      //   if(acsiiCode === 22) return this.handlePaste() // ctrl + v
      //   this.socket.emit('input', key)
      // })
    },
    handleClear() {
      this.term.clear()
    },
    async handlePaste() {
      let str = await navigator.clipboard.readText()
      // this.term.paste(str)
      this.socket.emit('input', str)
      this.term.focus()
    },
    // 供父组件调用
    focusTab() {
      this.term.blur()
      setTimeout(() => {
        this.term.focus()
      }, 200)
    },
    // 供父组件调用
    handleInputCommand(command) {
      this.socket.emit('input', command)
    }
  }
}
</script>

<style lang="scss" scoped>
header {
  position: fixed;
  z-index: 1;
  right: 10px;
  top: 50px;
}
.terminal-container {
  height: 100%;
  :deep(.xterm-viewport), :deep(.xterm-screen) {
    width: 100%!important;
    height: 100%!important;
    // 滚动条整体部分
    &::-webkit-scrollbar {
      height: 5px;
      width: 5px;
      background-color: #ffffff;
    }

    // 底层轨道
    &::-webkit-scrollbar-track {
      background-color: #000;
      border-radius: 0;
    }

    // 滚动滑块
    &::-webkit-scrollbar-thumb {
      border-radius: 5px;
    }

    &::-webkit-scrollbar-thumb:hover {
      background-color: #067ef7;
    }
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
