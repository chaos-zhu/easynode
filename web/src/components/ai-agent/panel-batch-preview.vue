<template>
  <section class="panel_batch_preview">
    <p>面板数据变更 · {{ actionLabel }} · {{ preview.items.length }} 项</p>
    <details v-for="item in preview.items" :key="item.id">
      <summary>{{ item.name }} <small>{{ item.id }}</small></summary>
      <div v-for="change in item.changes" :key="change.field" class="change">
        <strong>{{ labels[change.field] || change.field }}</strong>
        <pre v-if="change.diff">{{ change.diff }}</pre>
        <template v-else>
          <div>修改前：{{ format(change.before) }}</div>
          <div>修改后：{{ format(change.after) }}</div>
        </template>
      </div>
      <p v-if="item.group">目标分组：{{ item.group.name }}</p>
      <p v-if="item.members?.length">移至默认分组：{{ item.members.map(member => member.name).join('、') }}</p>
      <div v-if="item.affectedTasks?.length" class="task_impact">
        <strong>{{ preview.action === 'delete' ? '以下定时任务将被禁用' : '引用此脚本的任务下次将使用最新内容' }}</strong>
        <p v-for="task in item.affectedTasks" :key="task.taskId">{{ task.name }} · {{ task.taskId }}</p>
      </div>
      <p v-if="!item.changed">没有字段变化</p>
    </details>
  </section>
</template>

<script setup>
import { computed } from 'vue'
const props = defineProps({ preview: { type: Object, required: true } })
const actionLabel = computed(() => ({ create: '新增', update: '修改', delete: '删除' }[props.preview.action]))
const labels = { name: '名称', description: '说明', command: '脚本内容', groupId: '分组 ID', tag: '标签', expired: '到期时间', expiredNotify: '到期提醒', consoleUrl: '控制台 URL', useBase64: 'Base64 执行' }
function format(value) { return value === null ? '空' : typeof value === 'object' ? JSON.stringify(value) : String(value) }
</script>

<style scoped>
.panel_batch_preview { overflow-wrap: anywhere; }
details { margin: 8px 0; padding: 8px; border: 1px solid var(--el-border-color); border-radius: 6px; }
summary { cursor: pointer; font-weight: 600; }
small { font-weight: normal; opacity: .7; }
.change { margin-top: 8px; }
pre { max-height: 240px; overflow: auto; white-space: pre-wrap; font-size: 12px; }
.task_impact { margin-top: 8px; color: var(--el-color-warning); }
</style>
