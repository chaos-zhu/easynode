<template>
  <el-select
    :model-value="modelValue"
    multiple
    filterable
    collapse-tags
    collapse-tags-tooltip
    :max-collapse-tags="1"
    :placeholder="modelValue.length ? '选择目标主机' : '聊天模式'"
    class="host_selector"
    size="small"
    @update:model-value="emit('update:modelValue', $event)"
  >
    <el-option-group v-for="group in grouped" :key="group.name" :label="group.name">
      <el-option
        v-for="host in group.hosts"
        :key="host._id"
        :label="host.name"
        :value="host._id"
        :disabled="host.aiDisabled"
      >
        <div class="host_option">
          <span class="host_name">{{ host.name }}</span>
          <span class="host_addr">{{ host.host }}</span>
          <span v-if="host.aiDisabled" class="host_tag">已禁用 AI</span>
        </div>
      </el-option>
    </el-option-group>
  </el-select>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'

const { proxy: { $store } } = getCurrentInstance()

defineProps({
  modelValue: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['update:modelValue',])

const groupName = computed(() => {
  const map = new Map(($store.groupList || []).map((group) => [group._id, group.name,]))
  return (id) => map.get(id) || '默认分组'
})

const grouped = computed(() => {
  const buckets = new Map()
  for (const host of $store.hostList || []) {
    const name = groupName.value(host.group)
    if (!buckets.has(name)) buckets.set(name, [])
    buckets.get(name).push({
      ...host,
      aiDisabled: host.aiPolicy?.enabled === false
    })
  }
  return [...buckets.entries(),].map(([name, hosts,]) => ({ name, hosts }))
})
</script>

<style lang="scss" scoped>
.host_selector {
  width: 150px;
}

.host_option {
  display: flex;
  align-items: center;
  gap: 8px;

  .host_name {
    flex: 1;
  }

  .host_addr {
    color: #909399;
    font-size: 12px;
  }

  .host_tag {
    padding: 0 4px;
    border-radius: 3px;
    background-color: rgba(245, 108, 108, 0.15);
    color: #f56c6c;
    font-size: 11px;
  }
}
</style>
