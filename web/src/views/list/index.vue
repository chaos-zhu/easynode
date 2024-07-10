<template>
  <header>
    <div class="logo-wrap">
      <img src="@/assets/logo.png" alt="logo">
      <h1>EasyNode</h1>
    </div>
    <div>
      <el-button type="primary" @click="hostFormVisible = true">
        新增服务器
      </el-button>
      <el-button type="primary" @click="settingVisible = true">
        功能设置
      </el-button>
      <el-button type="primary" @click="handleHiddenIP">
        {{ hiddenIp ? '显示IP' : '隐藏IP' }}
      </el-button>
      <el-button type="success" plain @click="handleLogout">安全退出</el-button>
    </div>
  </header>
  <section
    v-loading="loading"
    element-loading-background="rgba(122, 122, 122, 0.58)"
  >
    <HostCard
      v-for="(item, index) in hostListStatus"
      :key="index"
      :host-info="item"
      :hidden-ip="hiddenIp"
      @update-list="handleUpdateList"
      @update-host="handleUpdateHost"
    />
  </section>
  <footer>
    <span>Release v1.2.1, Powered by <a href="https://github.com/chaos-zhu/easynode" target="_blank">EasyNode</a></span>
  </footer>
  <HostForm
    v-model:show="hostFormVisible"
    :default-data="updateHostData"
    @update-list="handleUpdateList"
    @closed="updateHostData = null"
  />
  <Setting
    v-model:show="settingVisible"
    @update-list="handleUpdateList"
  />
</template>

<script>
import { io } from 'socket.io-client'
import HostForm from './components/host-form.vue'
import Setting from './components/setting.vue'
import HostCard from './components/host-card.vue'

export default {
  name: 'App',
  components: {
    HostCard,
    HostForm,
    Setting
  },
  data() {
    return {
      socket: null,
      loading: true,
      hostListStatus: [],
      updateHostData: null,
      hostFormVisible: false,
      settingVisible: false,
      hiddenIp: Number(localStorage.getItem('hiddenIp') || 0)
    }
  },
  mounted() {
    this.getHostList()
  },
  beforeUnmount() {
    this.socket?.close && this.socket.close()
  },
  methods: {
    handleLogout() {
      this.$store.clearJwtToken()
      this.$message({ type: 'success', message: '已安全退出', center: true })
      this.$router.push('/login')
    },
    async getHostList() {
      try {
        this.loading = true
        await this.$store.getHostList()
        this.connectIo()
      } catch(err) {
        this.loading = false
      }
    },
    connectIo() {
      let socket = io(this.$serviceURI, {
        path: '/clients',
        forceNew: true, // 强制新的实例
        reconnectionDelay: 5000,
        reconnectionAttempts: 2 // 每5s后尝试重新连接次数
      })
      this.socket = socket
      socket.on('connect', () => {
        let flag = 5
        this.loading = false
        console.log('clients websocket 已连接: ', socket.id)
        let token = this.$store.token
        socket.emit('init_clients_data', { token })
        socket.on('clients_data', (data) => {
          if((flag++ % 5) === 0) this.$store.getHostPing()
          this.hostListStatus = this.$store.hostList.map(item => {
            const { host } = item
            if(data[host] === null) return { ...item }// 为null时表示该服务器断开连接
            return Object.assign({}, item, data[host])
          })
        })
        socket.on('token_verify_fail', (message) => {
          this.$notification({
            title: '鉴权失败',
            message,
            type: 'error'
          })
          this.$router.push('/login')
        })
      })
      socket.on('disconnect', () => {
        // this.$notification({
        //   title: 'server websocket error',
        //   message: '与服务器连接断开',
        //   type: 'error'
        // })
        console.error('clients websocket 连接断开')
      })
      socket.on('connect_error', (message) => {
        this.loading = false
        console.error('clients websocket 连接出错: ', message)
      })
    },
    handleUpdateList() {
      this.socket.close && this.socket.close()
      this.getHostList()
    },
    handleUpdateHost(defaultData) {
      this.hostFormVisible = true
      this.updateHostData = defaultData
    },
    handleHiddenIP() {
      this.hiddenIp = this.hiddenIp ? 0 : 1
      localStorage.setItem('hiddenIp', String(this.hiddenIp))
    }
  }
}
</script>

<style lang="scss" scoped>
$height:70px;
header {
  // position: sticky;
  // top: 0px;
  // z-index: 1;
  // background: rgba(255,255,255,0);
  padding: 0 30px;
  height: $height;
  display: flex;
  justify-content: space-between;
  align-items: center;
  .logo-wrap {
    display: flex;
    justify-content: center;
    align-items: center;
    img {
      height: 50px;
    }
    h1 {
      color: white;
      font-size: 20px;
    }
  }
}
section {
  opacity: 0.9;
  height: calc(100vh - $height - 25px);
  padding: 10px 0 250px;
  overflow: auto;
}
footer {
  height: 25px;
  display: flex;
  justify-content: center;
  align-items: center;
  span {
    color: #ffffff;
  }
  a {
    color: #48ff00;
    font-weight: 600;
  }
}
</style>
