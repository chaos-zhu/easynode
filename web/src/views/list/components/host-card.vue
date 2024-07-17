<template>
  <el-card shadow="always" class="host-card">
    <div class="host-state">
      <span v-if="isError" class="offline">未连接</span>
      <span v-else class="online">已连接 {{ ping }}</span>
    </div>
    <div class="info">
      <div class="weizhi field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-fuwuqi" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>系统</h2>
            <h3><span>名称:</span> {{ osInfo.hostname }}</h3>
            <h3><span>类型:</span> {{ osInfo.type }}</h3>
            <h3><span>架构:</span> {{ osInfo.arch }}</h3>
            <h3><span>平台:</span> {{ osInfo.platform }}</h3>
            <h3><span>版本:</span> {{ osInfo.release }}</h3>
            <h3><span>开机时长:</span> {{ $tools.formatTime(osInfo.uptime) }}</h3>
            <h3><span>到期时间:</span> {{ expiredTime }}</h3>
            <h3><span>本地IP:</span> {{ osInfo.ip }}</h3>
            <h3><span>连接数:</span> {{ openedCount || 0 }}</h3>
          </div>
        </el-popover>
        <div class="fields">
          <span class="name" @click="handleUpdate">
            {{ name || '--' }}
            <svg-icon name="icon-xiugai" class="svg-icon" />
          </span>
          <span>{{ osInfo?.type || '--' }}</span>
          <!-- <span>{{ osInfo?.hostname || '--' }}</span> -->
        </div>
      </div>
      <div class="weizhi field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-position" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>位置信息</h2>
            <h3><span>详细:</span> {{ ipInfo.country || '--' }} {{ ipInfo.regionName }}</h3>
            <!-- <h3><span>详细:</span> {{ ipInfo.country || '--' }} {{ ipInfo.regionName }} {{ ipInfo.city }}</h3> -->
            <!-- <h3><span>IP:</span> {{ hostIp }}</h3> -->
            <h3><span>提供商:</span> {{ ipInfo.isp || '--' }}</h3>
            <h3><span>线路:</span> {{ ipInfo.as || '--' }}</h3>
          </div>
        </el-popover>
        <div class="fields">
          <span>{{ `${ipInfo?.country || '--'} ${ipInfo?.regionName || '--'}` }}</span>
          <!-- <span>{{ `${ipInfo?.country || '--' } ${ipInfo?.regionName || '--'} ${ipInfo?.city || '--'}` }}</span> -->
          <span>{{ hostIp }}</span>
        </div>
      </div>
      <div class="cpu field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-xingzhuang" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>CPU</h2>
            <h3><span>利用率:</span> {{ cpuInfo.cpuUsage }}%</h3>
            <h3><span>物理核心:</span> {{ cpuInfo.cpuCount }}</h3>
            <h3><span>型号:</span> {{ cpuInfo.cpuModel }}</h3>
          </div>
        </el-popover>
        <div class="fields">
          <span :style="{ color: setColor(cpuInfo.cpuUsage) }">{{ cpuInfo.cpuUsage || '0' || '--' }}%</span>
          <span>{{ cpuInfo.cpuCount || '--' }} 核心</span>
        </div>
      </div>
      <div class="ram field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-neicun1" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>内存</h2>
            <h3><span>总大小:</span> {{ $tools.toFixed(memInfo.totalMemMb / 1024) }} GB</h3>
            <h3><span>已使用:</span> {{ $tools.toFixed(memInfo.usedMemMb / 1024) }} GB</h3>
            <h3><span>占比:</span> {{ $tools.toFixed(memInfo.usedMemPercentage) }}%</h3>
            <h3><span>空闲:</span> {{ $tools.toFixed(memInfo.freeMemMb / 1024) }} GB</h3>
          </div>
        </el-popover>
        <div class="fields">
          <span :style="{ color: setColor(memInfo.usedMemPercentage) }">{{ $tools.toFixed(memInfo.usedMemPercentage)
          }}%</span>
          <span>{{ $tools.toFixed(memInfo.usedMemMb / 1024) }} | {{ $tools.toFixed(memInfo.totalMemMb / 1024) }} GB</span>
        </div>
      </div>
      <div class="yingpan field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-xingzhuang1" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>存储</h2>
            <h3><span>总空间:</span> {{ driveInfo.totalGb || '--' }} GB</h3>
            <h3><span>已使用:</span> {{ driveInfo.usedGb || '--' }} GB</h3>
            <h3><span>剩余:</span> {{ driveInfo.freeGb || '--' }} GB</h3>
            <h3><span>占比:</span> {{ driveInfo.usedPercentage || '--' }}%</h3>
          </div>
        </el-popover>
        <div class="fields">
          <span :style="{ color: setColor(driveInfo.usedPercentage) }">{{ driveInfo.usedPercentage || '--' }}%</span>
          <span>{{ driveInfo.usedGb || '--' }} | {{ driveInfo.totalGb || '--' }} GB</span>
        </div>
      </div>
      <div class="wangluo field">
        <el-popover placement="bottom-start" :width="200" trigger="hover">
          <template #reference>
            <svg-icon name="icon-wangluo1" class="svg-icon" />
          </template>
          <div class="field-detail">
            <h2>网卡</h2>
            <!-- <h3>
              <span>实时流量</span>
              <div>↑ {{ $tools.toFixed(netstatInfo.netTotal?.outputMb) || 0 }}MB / s</div>
              <div>↓ {{ $tools.toFixed(netstatInfo.netTotal?.inputMb) || 0 }}MB / s</div>
            </h3> -->
            <div v-for="(value, key) in netstatInfo.netCards" :key="key" style="display: flex; flex-direction: column;">
              <h3>
                <span>{{ key }}</span>
                <div>↑ {{ $tools.formatNetSpeed(value?.outputMb) || 0 }}</div>
                <div>↓ {{ $tools.formatNetSpeed(value?.inputMb) || 0 }}</div>
              </h3>
            </div>
          </div>
        </el-popover>
        <div class="fields">
          <span>↑ {{ $tools.formatNetSpeed(netstatInfo.netTotal?.outputMb) || 0 }}</span>
          <span>↓ {{ $tools.formatNetSpeed(netstatInfo.netTotal?.inputMb) || 0 }}</span>
        </div>
      </div>
      <div class="fields terminal">
        <el-dropdown class="web-ssh" type="primary" trigger="click">
          <!-- <el-button type="primary" @click="handleSSH">Web SSH</el-button> -->
          <el-button type="primary">功能</el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleSSH">连接终端</el-dropdown-item>
              <el-dropdown-item v-if="consoleUrl" @click="handleToConsole">控制台</el-dropdown-item>
              <el-dropdown-item @click="handleUpdate">修改服务器</el-dropdown-item>
              <el-dropdown-item @click="handleRemoveHost"><span style="color: #727272;">移除主机</span></el-dropdown-item>
              <el-dropdown-item @click="handleRemoveSSH"><span style="color: #727272;">移除凭证</span></el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </div>
    <SSHForm v-model:show="sshFormVisible" :temp-host="tempHost" :name="name" />
  </el-card>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import SSHForm from './ssh-form.vue'

const { proxy: { $api, $tools } } = getCurrentInstance()

const props = defineProps({
  hostInfo: {
    required: true,
    type: Object
  },
  hiddenIp: {
    required: true,
    type: [Number, Boolean,]
  }
})

const emit = defineEmits(['update-list', 'update-host',])

const sshFormVisible = ref(false)
const tempHost = ref('')

const hostIp = computed(() => {
  let ip = props.hostInfo?.ipInfo?.query || props.hostInfo?.host || '--'
  try {
    let formatIp = ip.replace(/\d/g, '*').split('.').map((item) => item.padStart(3, '*')).join('.')
    return props.hiddenIp ? formatIp : ip
  } catch (error) {
    return ip
  }
})

const host = computed(() => props.hostInfo?.host)
const name = computed(() => props.hostInfo?.name)
const ping = computed(() => props.hostInfo?.ping || '')
const expiredTime = computed(() => $tools.formatTimestamp(props.hostInfo?.expired, 'date'))
const consoleUrl = computed(() => props.hostInfo?.consoleUrl)
const ipInfo = computed(() => props.hostInfo?.ipInfo || {})
const isError = computed(() => !Boolean(props.hostInfo?.osInfo))
const cpuInfo = computed(() => props.hostInfo?.cpuInfo || {})
const memInfo = computed(() => props.hostInfo?.memInfo || {})
const osInfo = computed(() => props.hostInfo?.osInfo || {})
const driveInfo = computed(() => props.hostInfo?.driveInfo || {})
const netstatInfo = computed(() => {
  let { total: netTotal, ...netCards } = props.hostInfo?.netstatInfo || {}
  return { netTotal, netCards: netCards || {} }
})
const openedCount = computed(() => props.hostInfo?.openedCount || 0)

const setColor = (num) => {
  num = Number(num)
  return num ? (num < 80 ? '#595959' : (num >= 80 && num < 90 ? '#FF6600' : '#FF0000')) : '#595959'
}

const handleUpdate = () => {
  let { expired, expiredNotify, group, consoleUrl, remark } = props.hostInfo
  emit('update-host', { name: name.value, host: host.value, expired, expiredNotify, group, consoleUrl, remark })
}

const handleToConsole = () => {
  window.open(consoleUrl.value)
}

const handleSSH = async () => {
  let { data } = await $api.existSSH(host.value)
  if (data) return window.open(`/terminal?host=${ host.value }&name=${ name.value }`)
  if (!host.value) {
    return ElMessage({
      message: '请等待获取服务器ip或刷新页面重试',
      type: 'warning',
      center: true
    })
  }
  tempHost.value = host.value
  sshFormVisible.value = true
}

const handleRemoveSSH = async () => {
  ElMessageBox.confirm('确认删除SSH凭证', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeSSH(host.value)
    ElMessage({
      message: data,
      type: 'success',
      center: true
    })
  })
}

const handleRemoveHost = async () => {
  ElMessageBox.confirm('确认删除主机', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ host: host.value })
    ElMessage({
      message: data,
      type: 'success',
      center: true
    })
    emit('update-list')
  })
}
</script>

<style lang="scss" scoped>
.host-card {
  margin: 0px 30px 20px;
  transition: all 0.5s;
  position: relative;

  &:hover {
    box-shadow: 0px 0px 15px rgba(6, 30, 37, 0.5);
  }

  .host-state {
    position: absolute;
    top: 0px;
    left: 0px;

    span {
      font-size: 8px;
      // transform: rotate(-45deg);
      transform: scale(0.9);
      display: inline-block;
      padding: 3px 5px;
    }

    .online {
      color: #009933;
      background-color: #e8fff3;
    }

    .offline {
      color: #FF0033;
      background-color: #fff5f8;
    }
  }

  .info {
    display: flex;
    align-items: center;
    height: 50px;

    &>div {
      flex: 1
    }

    .field {
      height: 100%;
      display: flex;
      align-items: center;

      .svg-icon {
        width: 25px;
        height: 25px;
        color: #1989fa;
        cursor: pointer;
      }

      .fields {
        display: flex;
        flex-direction: column;

        // justify-content: center;
        span {
          padding: 3px 0;
          margin-left: 5px;
          font-weight: 600;
          font-size: 13px;
          color: #595959;
        }

        .name {
          display: inline-block;
          height: 19px;
          cursor: pointer;

          &:hover {
            text-decoration-line: underline;
            text-decoration-color: #1989fa;

            .svg-icon {
              display: inline-block;
            }
          }

          .svg-icon {
            display: none;
            width: 13px;
            height: 13px;
          }
        }
      }
    }

    .web-ssh {

      // ::v-deep has been deprecated. Use :deep(<inner-selector>) instead.
      :deep(.el-dropdown__caret-button) {
        margin-left: -5px;
      }
    }
  }
}
</style>

<style lang="scss">
.field-detail {
  display: flex;
  flex-direction: column;

  h2 {
    font-weight: 600;
    font-size: 16px;
    margin: 0px 0 8px 0;
  }

  h3 {
    span {
      font-weight: 600;
      color: #797979;
    }
  }

  span {
    display: inline-block;
    margin: 4px 0;
  }
}
</style>
