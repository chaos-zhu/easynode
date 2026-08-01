<template>
  <div class="reasoning_block" :class="{ 'is_dark': isDark }">
    <div class="reasoning_head" @click="expanded = !expanded">
      <el-icon class="toggle_icon" :class="{ 'is_expanded': expanded }"><ArrowRight /></el-icon>
      <span class="head_text">{{ headText }}</span>
    </div>
    <div v-if="expanded" class="reasoning_content">{{ part.text }}</div>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { ArrowRight } from '@element-plus/icons-vue'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  part: {
    type: Object,
    required: true
  }
})

// 思考过程默认折叠：它对排查有价值，但绝大多数时候用户只想看结论
const expanded = ref(false)
const isDark = computed(() => $store.isDark)

const headText = computed(() => (props.part.done ? '思考过程' : '思考中…'))
</script>

<style lang="scss" scoped>
.reasoning_block {
  margin: 6px 0;
  font-size: 13px;

  .reasoning_head {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    user-select: none;
    color: #909399;

    &:hover {
      color: #606266;
    }

    .toggle_icon {
      font-size: 12px;
      transition: transform 0.2s;

      &.is_expanded {
        transform: rotate(90deg);
      }
    }
  }

  .reasoning_content {
    margin-top: 6px;
    padding: 8px 10px;
    max-height: 260px;
    overflow: auto;
    border-left: 2px solid #dcdfe6;
    color: #909399;
    line-height: 1.7;
    white-space: pre-wrap;
    word-break: break-word;
  }

  &.is_dark {
    .reasoning_head:hover { color: #c0c4cc; }
    .reasoning_content { border-left-color: #4a4a4a; }
  }
}
</style>
