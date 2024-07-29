<template>
  <div class="server_group_container">
    <div class="server_group_header">
      <el-button type="primary" @click="hostFormVisible = true">添加实例</el-button>
      <el-button type="primary" @click="handleHiddenIP">
        {{ hiddenIp ? '显示IP' : '隐藏IP' }}
      </el-button>
    </div>
    <div class="server_group_collapse">
      <div v-if="isNoHost">
        <el-empty description="暂无实例">
          <el-button type="primary" @click="hostFormVisible = true">添加第一台实例配置</el-button>
        </el-empty>
      </div>
      <el-collapse v-else v-model="activeGroup">
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
              @update-host="handleUpdateHost"
              @update-list="handleUpdateList"
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
import { ref, getCurrentInstance, computed, watch } from 'vue'
import HostCard from './components/host-card.vue'
import HostForm from './components/host-form.vue'

const { proxy: { $store, $message } } = getCurrentInstance()

const updateHostData = ref(null)
const hostFormVisible = ref(false)
const hiddenIp = ref(Number(localStorage.getItem('hiddenIp') || 0))
const activeGroup = ref([])

const handleUpdateList = async () => {
  try {
    await $store.getHostList()
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
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

let isNoHost = computed(() => Object.keys(groupHostList.value).length === 0)

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
