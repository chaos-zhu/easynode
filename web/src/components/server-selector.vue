<template>
  <div class="server-selector">
    <el-select
      v-model="selectedServer"
      :disabled="!isPlusActive"
      placeholder="选择服务器"
      filterable
      clearable
      class="server-select"
      @change="handleServerChange"
    >
      <el-option
        v-for="server in serverList"
        :key="server._id"
        :label="`${server.name} (${server.host})`"
        :value="server._id"
      >
        <div class="server-option">
          <span class="server-name">{{ server.name }}</span>
          <span class="server-host">{{ server.host }}</span>
        </div>
      </el-option>
    </el-select>
  </div>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'

const props = defineProps({
  modelValue: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['update:modelValue', 'change',])

const { proxy: { $store } } = getCurrentInstance()

const serverList = computed(() => $store.hostList?.filter(item => item.connectType !== 'rdp' && item.isConfig))
const isPlusActive = computed(() => $store.isPlusActive)

const selectedServer = computed({
  get: () => props.modelValue,
  set: (value) => emit('update:modelValue', value)
})

const handleServerChange = (serverId) => {
  const server = serverList.value.find(s => s._id === serverId)
  emit('change', server)
}
</script>

<style lang="scss" scoped>
.server-selector {
  .server-select {
    width: 100%;
  }

  .server-option {
    display: flex;
    justify-content: space-between;
    align-items: center;

    .server-name {
      font-weight: 500;
      color: var(--el-text-color-primary);
    }

    .server-host {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }
}
</style>