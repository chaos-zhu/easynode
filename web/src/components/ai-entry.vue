<template>
  <div class="ai_entry">
    <div class="entry_button" @click="visible = true">
      <img src="@/assets/image/coding32.png" alt="AI">
      AI 助手
    </div>

    <AiAgent v-model:show="visible" />
  </div>
</template>

<script setup>
import { ref } from 'vue'
import AiAgent from '@/components/ai-agent/index.vue'

const visible = ref(false)
</script>

<style scoped lang="scss">
.ai_entry {
  .entry_button {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    min-width: 100px;
    height: 32px;
    padding: 0 10px;
    border-radius: 10px;
    background: #887dfd;
    color: #fff;
    font-size: 14px;
    cursor: pointer;
    transition: filter 0.3s;

    &:hover {
      filter: brightness(1.2);
    }

    img {
      width: 16px;
      height: 16px;
      border-radius: 10%;
    }
  }
}
</style>
