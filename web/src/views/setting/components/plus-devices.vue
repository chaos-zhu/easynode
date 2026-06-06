<template>
  <div class="plus_devices">
    <div class="devices_header">
      <div class="header_left">
        <span class="title">设备授权</span>
        <el-tag
          class="quota_tag"
          :type="isFull ? 'danger' : 'success'"
          effect="light"
          round
        >
          已用 {{ usedCount }} / {{ deviceLimit }} 台
        </el-tag>
      </div>
      <el-button
        class="refresh_btn"
        type="primary"
        text
        :icon="Refresh"
        :loading="loading"
        @click="fetchDevices"
      >
        刷新
      </el-button>
    </div>

    <el-table
      v-loading="loading"
      :data="devices"
      class="devices_table"
      empty-text="暂无在线设备"
      :header-cell-style="{ background: '#f5f7fa', color: '#606266', fontWeight: 600 }"
    >
      <el-table-column label="#" type="index" width="50" align="center" />
      <el-table-column label="实例" min-width="170">
        <template #default="{ row }">
          <div class="instance_cell">
            <span class="instance_id">实例 {{ shortId(row.instanceId) }}</span>
            <el-tag v-if="row.isCurrent" type="success" size="small" effect="plain">本机</el-tag>
          </div>
        </template>
      </el-table-column>
      <el-table-column label="出口 IP" prop="ip" min-width="150">
        <template #default="{ row }">
          <span class="ip_text">{{ row.ip || '-' }}</span>
        </template>
      </el-table-column>
      <el-table-column label="版本" min-width="100" align="center">
        <template #default="{ row }">
          <span class="version_text">{{ row.version ? `v${ row.version }` : '-' }}</span>
        </template>
      </el-table-column>
      <el-table-column label="最后活跃" min-width="120">
        <template #default="{ row }">
          <span class="active_dot" />
          <span class="active_text">{{ formatRelative(row.lastSeen) }}</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="100" align="center">
        <template #default="{ row }">
          <span v-if="row.isCurrent" class="current_hint">—</span>
          <el-button
            v-else
            type="danger"
            size="small"
            plain
            @click="handleRelease(row)"
          >
            释放
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <div class="devices_tip">
      <el-icon class="tip_icon"><InfoFilled /></el-icon>
      <span>
        当新实例启动且额度已满时，将自动移除最久未活跃的实例。如需主动腾出额度，可点击对应实例的「释放」按钮。
      </span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, getCurrentInstance } from 'vue'
import { ElMessageBox } from 'element-plus'
import { Refresh, InfoFilled } from '@element-plus/icons-vue'

const { proxy: { $api, $message } } = getCurrentInstance()

const loading = ref(false)
const deviceLimit = ref(0)
const devices = ref([])

const usedCount = computed(() => devices.value.length)
const isFull = computed(() => deviceLimit.value > 0 && usedCount.value >= deviceLimit.value)

const shortId = (id) => (id ? `${ String(id).slice(0, 4) }…` : '')

const formatRelative = (ts) => {
  const diff = Date.now() - Number(ts || 0)
  if (!ts || diff < 0) return '-'
  const sec = Math.floor(diff / 1000)
  if (sec < 10) return '刚刚'
  if (sec < 60) return `${ sec }秒前`
  const min = Math.floor(sec / 60)
  if (min < 60) return `${ min }分钟前`
  const hour = Math.floor(min / 60)
  if (hour < 24) return `${ hour }小时前`
  const day = Math.floor(hour / 24)
  return `${ day }天前`
}

const fetchDevices = async () => {
  try {
    loading.value = true
    const { data } = await $api.getPlusDevices()
    deviceLimit.value = data?.deviceLimit || 0
    devices.value = Array.isArray(data?.devices) ? data.devices : []
  } catch (error) {
    $message({ type: 'warning', center: true, message: error?.message || '获取设备列表失败' })
  } finally {
    loading.value = false
  }
}

const handleRelease = (row) => {
  ElMessageBox.confirm(
    '释放该实例的 Plus 额度占用，提供给新实例使用。被释放的实例需重启后才能重新占用额度。',
    '释放确认',
    {
      confirmButtonText: '确认释放',
      cancelButtonText: '取消',
      type: 'warning'
    }
  )
    .then(async () => {
      await $api.releasePlusDevice({ targetInstanceId: row.instanceId })
      $message({ type: 'success', center: true, message: '释放成功' })
      fetchDevices()
    })
    .catch(() => {})
}

onMounted(() => {
  fetchDevices()
})
</script>

<style lang="scss" scoped>
.plus_devices {
  margin-bottom: 15px;
  padding: 16px;
  border: 1px solid #ebeef5;
  border-radius: 8px;
  background: #fff;

  .devices_header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 14px;

    .header_left {
      display: flex;
      align-items: center;
      gap: 12px;

      .title {
        font-size: 16px;
        font-weight: 600;
        color: #303133;
      }

      .quota_tag {
        font-size: 13px;
        font-weight: 500;
      }
    }

    .refresh_btn {
      font-size: 14px;
    }
  }

  .devices_table {
    font-size: 14px;

    .instance_cell {
      display: flex;
      align-items: center;
      gap: 8px;

      .instance_id {
        font-family: 'Menlo', 'Consolas', monospace;
        font-size: 14px;
        color: #303133;
      }
    }

    .ip_text {
      font-family: 'Menlo', 'Consolas', monospace;
      font-size: 14px;
      color: #606266;
    }

    .version_text {
      font-size: 13px;
      color: #909399;
    }

    .active_dot {
      display: inline-block;
      width: 7px;
      height: 7px;
      margin-right: 6px;
      border-radius: 50%;
      background: #67c23a;
      vertical-align: middle;
    }

    .active_text {
      font-size: 13px;
      color: #606266;
      vertical-align: middle;
    }

    .current_hint {
      color: #c0c4cc;
    }
  }

  .devices_tip {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin-top: 14px;
    padding: 10px 12px;
    border-radius: 6px;
    background: #ecf5ff;
    border: 1px solid #d9ecff;
    font-size: 13px;
    line-height: 1.6;
    color: #606266;

    .tip_icon {
      flex-shrink: 0;
      margin-top: 2px;
      color: #409eff;
      font-size: 15px;
    }
  }
}
</style>
