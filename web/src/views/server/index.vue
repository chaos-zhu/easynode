<template>
  <div class="server_group_container">
    <div class="server_group_header">
      <el-button type="primary" @click="hostFormVisible = true">添加服务器</el-button>
      <el-button type="primary" @click="handleHiddenIP">
        {{ hiddenIp ? '显示IP' : '隐藏IP' }}
      </el-button>
    </div>
    <div class="server_group_collapse">
      <el-collapse v-model="activeGroup">
        <el-collapse-item v-for="(servers, groupName) in groupHostList" :key="groupName" :name="groupName">
          <template #title>
            <div class="group_title">
              {{ groupName }}
            </div>
          </template>
          <div class="host_card_container">
            <HostCard
              v-for="(item, index) in servers"
              :key="index"
              :host-info="item"
              :hidden-ip="hiddenIp"
              @update-list="handleUpdateList"
              @update-host="handleUpdateHost"
            />
          </div>
        </el-collapse-item>
      </el-collapse>
    </div>
    <HostForm
      v-model:show="hostFormVisible"
      :default-data="updateHostData"
      @update-list="handleUpdateList"
      @closed="updateHostData = null"
    />
  </div>
</template>

<script setup>
import { ref, onBeforeUnmount, getCurrentInstance, computed, watch, onMounted } from 'vue'
import { io } from 'socket.io-client'
import HostForm from './components/host-form.vue'
import HostCard from './components/host-card.vue'

const { proxy: { $store, $notification, $router, $serviceURI, $message } } = getCurrentInstance()

const socket = ref(null)
const updateHostData = ref(null)
const hostFormVisible = ref(false)
const hiddenIp = ref(Number(localStorage.getItem('hiddenIp') || 0))
const activeGroup = ref([])

const connectIo = () => {
  if (socket.value) socket.value.close()
  let socketInstance = io($serviceURI, {
    path: '/clients',
    forceNew: true,
    reconnectionDelay: 5000,
    reconnectionAttempts: 2
  })
  socket.value = socketInstance
  socketInstance.on('connect', () => {
    let flag = 5
    console.log('clients websocket 已连接: ', socketInstance.id)
    let token = $store.token
    socketInstance.emit('init_clients_data', { token })
    socketInstance.on('clients_data', (data) => {
      if ((flag++ % 5) === 0) $store.getHostPing()
      $store.hostList.forEach(item => {
        const { host } = item
        if (data[host] === null) return { ...item }
        return Object.assign(item, data[host])
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
    console.error('clients websocket 连接出错: ', message)
  })
}

const handleUpdateList = async () => {
  try {
    await $store.getHostList()
    // connectIo()
  } catch (err) {
    $message.error('获取主机列表失败')
    console.error('获取主机列表失败: ', err)
  }
}

const handleUpdateHost = (defaultData) => {
  hostFormVisible.value = true
  updateHostData.value = defaultData
}

const handleHiddenIP = () => {
  hiddenIp.value = hiddenIp.value ? 0 : 1
  localStorage.setItem('hiddenIp', String(hiddenIp.value))
}

let groupHostList = computed(() => {
  let res = {}
  let hostList = $store.hostList
  let groupList = $store.groupList
  groupList.forEach(group => {
    res[group.name] = []
  })
  hostList.forEach(item => {
    const group = groupList.find(group => group.id === item.group)
    if (group) {
      res[group.name].push(item)
    } else {
      res['默认分组'].push(item)
    }
  })
  Object.keys(res).map(groupName => {
    if (res[groupName].length === 0) delete res[groupName]
  })
  return res
})

watch(groupHostList, () => {
  activeGroup.value = [...Object.keys(groupHostList.value),]
}, {
  immediate: true,
  deep: false
})

onMounted(() => {
  connectIo()
})

onBeforeUnmount(() => {
  if (socket.value) socket.value.close()
})

</script>

<style lang="scss" scoped>
.server_group_container {
  .server_group_header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
  }
  .server_group_collapse {
    .group_title {
      margin: 0 15px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
    }
    .host_card_container {
      padding-top: 25px;
    }
  }
}
</style>
