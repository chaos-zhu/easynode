<template>
  <div class="terminal_container">
    <div v-if="showLinkTips" class="terminal_link_tips">
      <h2 class="quick_link_text">快速连接</h2>
      <el-table
        :data="tabelData"
        :show-header="false"
      >
        <el-table-column prop="name" label="name" />
        <el-table-column>
          <template #default="{ row }">
            <span>{{ row.username ? `ssh ${row.username}@` : '' }}{{ row.host }}{{ row.port ? ` -p ${row.port}` : '' }}</span>
          </template>
        </el-table-column>
        <el-table-column v-show="!isAllConfssh">
          <template #default="{ row }">
            <div class="actios_btns">
              <el-button
                v-if="row.username && row.port"
                type="primary"
                link
                @click="linkTerminal(row)"
              >
                连接
              </el-button>
              <el-button
                v-else
                type="success"
                link
                @click="confSSH(row)"
              >
                配置ssh
              </el-button>
            </div>
          </template>
        </el-table-column>
      </el-table>
    </div>
    <div v-else>
      <Terminal />
    </div>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import Terminal from './components/terminal.vue'

const { proxy: { $store } } = getCurrentInstance()

let showLinkTips = ref(true)
let ternimalTabs = ref([])

let hostList = computed(() => $store.hostList)
let sshList = computed(() => $store.sshList)
let tabelData = computed(() => {
  return hostList.value.map(hostConf => {
    // console.log(sshList.value)
    let target = sshList.value?.find(sshConf => sshConf.host === hostConf.host)
    if (target !== -1) {
      return { ...hostConf, ...target }
    }
    return hostConf
  })
})
let isAllConfssh = computed(() => {
  return tabelData.value?.every(item => item.username && item.port)
})

function linkTerminal(row) {
  // console.log(row)
  ternimalTabs.value.push(row)
  showLinkTips.value = false
}

function confSSH(row) {

}

</script>

<style lang="scss" scoped>
.terminal_container {
  .terminal_link_tips {
    width: 50%;
    // margin: 0 auto;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    padding: 20px;
    .quick_link_text {
      align-self: self-start;
      margin: 0 10px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
      margin-bottom: 15px;
    }
    .actios_btns {
      display: flex;
      justify-content: flex-end;
    }
  }
}
</style>
