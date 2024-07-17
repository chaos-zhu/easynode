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

<script setup>
import { ref, onMounted, onBeforeUnmount, getCurrentInstance } from 'vue'
import { io } from 'socket.io-client'
import HostForm from './components/host-form.vue'
import Setting from './components/setting.vue'
import HostCard from './components/host-card.vue'

const { proxy: { $store, $message, $notification, $router, $serviceURI } } = getCurrentInstance()

const socket = ref(null)
const loading = ref(true)
const hostListStatus = ref([])
const updateHostData = ref(null)
const hostFormVisible = ref(false)
const settingVisible = ref(false)
const hiddenIp = ref(Number(localStorage.getItem('hiddenIp') || 0))

const handleLogout = () => {
  $store.clearJwtToken()
  $message({ type: 'success', message: '已安全退出', center: true })
  $router.push('/login')
}

const getHostList = async () => {
  try {
    loading.value = true
    await $store.getHostList()
    connectIo()
  } catch (err) {
    loading.value = false
  }
}

const connectIo = () => {
  let socketInstance = io($serviceURI, {
    path: '/clients',
    forceNew: true,
    reconnectionDelay: 5000,
    reconnectionAttempts: 2
  })
  socket.value = socketInstance
  socketInstance.on('connect', () => {
    let flag = 5
    loading.value = false
    console.log('clients websocket 已连接: ', socketInstance.id)
    let token = $store.token
    socketInstance.emit('init_clients_data', { token })
    socketInstance.on('clients_data', (data) => {
      if ((flag++ % 5) === 0) $store.getHostPing()
      hostListStatus.value = $store.hostList.map(item => {
        const { host } = item
        if (data[host] === null) return { ...item }
        return Object.assign({}, item, data[host])
      })
    })
    socketInstance.on('token_verify_fail', (message) => {
      $notification({
        title: '鉴权失败',
        message,
        type: 'error'
      })
      $router.push('/login')
    })
  })
  socketInstance.on('disconnect', () => {
    console.error('clients websocket 连接断开')
  })
  socketInstance.on('connect_error', (message) => {
    loading.value = false
    console.error('clients websocket 连接出错: ', message)
  })
}

const handleUpdateList = () => {
  if (socket.value) socket.value.close()
  getHostList()
}

const handleUpdateHost = (defaultData) => {
  hostFormVisible.value = true
  updateHostData.value = defaultData
}

const handleHiddenIP = () => {
  hiddenIp.value = hiddenIp.value ? 0 : 1
  localStorage.setItem('hiddenIp', String(hiddenIp.value))
}

onMounted(() => {
  getHostList()
})

onBeforeUnmount(() => {
  if (socket.value) socket.value.close()
})
</script>

<style lang="scss" scoped>
$height:70px;
header {
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