<template>
  <div v-if="merged.totalTokens" class="usage_bar">
    <span class="usage_item">Token {{ format(merged.totalTokens) }}</span>
    <span class="usage_item">输入 {{ format(merged.inputTokens) }}</span>
    <span class="usage_item">输出 {{ format(merged.outputTokens) }}</span>
    <span v-if="merged.cachedInputTokens" class="usage_item">缓存 {{ format(merged.cachedInputTokens) }}</span>
    <span v-if="merged.reasoningTokens" class="usage_item">推理 {{ format(merged.reasoningTokens) }}</span>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  // 会话累计量，以库里为准
  usage: {
    type: Object,
    default: () => ({})
  },
  // 本轮实时增量，turn 结束落盘后归零并并入 usage
  turnUsage: {
    type: Object,
    default: () => ({})
  }
})

const FIELDS = ['totalTokens', 'inputTokens', 'outputTokens', 'cachedInputTokens', 'reasoningTokens',]

const merged = computed(() => {
  const result = {}
  for (const field of FIELDS) {
    result[field] = (props.usage[field] || 0) + (props.turnUsage[field] || 0)
  }
  return result
})

const format = (value) => (value || 0).toLocaleString('en-US')
</script>

<style lang="scss" scoped>
.usage_bar {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  padding: 4px 0;
  color: #909399;
  font-size: 12px;

  .usage_item {
    white-space: nowrap;
  }
}
</style>
