<template>
  <div class="session_list" :class="{ 'is_dark': isDark }">
    <div class="list_head">
      <span>历史会话</span>
      <div class="head_actions">
        <el-button
          v-if="sessions.length"
          link
          size="small"
          title="清空历史会话"
          @click="confirmClear"
        >
          <el-icon><Delete /></el-icon>
        </el-button>
        <el-button link size="small" @click="emit('create')">
          <el-icon><Plus /></el-icon>
          新会话
        </el-button>
      </div>
    </div>

    <el-scrollbar class="list_body">
      <p v-if="!sessions.length" class="empty">暂无历史会话</p>

      <div
        v-for="session in sessions"
        :key="session.id"
        class="session_row"
        :class="{ 'is_active': session.id === activeId }"
        @click="emit('select', session.id)"
      >
        <div class="row_main">
          <el-input
            v-if="editingId === session.id"
            ref="renameInputRef"
            v-model="editingTitle"
            size="small"
            @click.stop
            @keyup.enter="commitRename(session.id)"
            @blur="commitRename(session.id)"
          />
          <span v-else class="row_title" :title="session.title">{{ session.title }}</span>
          <span class="row_meta">
            {{ formatTime(session.updatedAt) }} · {{ session.messageCount }} 条
          </span>
        </div>

        <div class="row_actions" @click.stop>
          <el-button
            link
            size="small"
            title="重命名"
            @click="startRename(session)"
          >
            <el-icon><EditPen /></el-icon>
          </el-button>
          <el-button
            link
            size="small"
            title="删除"
            @click="confirmRemove(session)"
          >
            <el-icon><Delete /></el-icon>
          </el-button>
        </div>
      </div>
    </el-scrollbar>
  </div>
</template>

<script setup>
import { ref, computed, nextTick, getCurrentInstance } from 'vue'
import { ElMessageBox } from 'element-plus'
import { Plus, EditPen, Delete } from '@element-plus/icons-vue'
import dayjs from 'dayjs'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  sessions: {
    type: Array,
    default: () => []
  },
  activeId: {
    type: String,
    default: ''
  },
  clearScopeLabel: {
    type: String,
    default: '当前助手'
  }
})

const emit = defineEmits(['select', 'create', 'remove', 'rename', 'clear',])

const isDark = computed(() => $store.isDark)
const editingId = ref('')
const editingTitle = ref('')
const renameInputRef = ref(null)

function startRename(session) {
  editingId.value = session.id
  editingTitle.value = session.title
  // v-if 保证同时只有一个输入框存在，但它在 v-for 里，ref 仍会被收集成数组
  nextTick(() => {
    const input = Array.isArray(renameInputRef.value) ? renameInputRef.value[0] : renameInputRef.value
    input?.focus()
  })
}

function commitRename(id) {
  if (editingId.value !== id) return
  const title = editingTitle.value.trim()
  editingId.value = ''
  const original = props.sessions.find((item) => item.id === id)?.title
  if (title && title !== original) emit('rename', id, title)
}

async function confirmRemove(session) {
  try {
    await ElMessageBox.confirm(`确定删除会话「${ session.title }」？删除后无法恢复。`, '删除会话', {
      type: 'warning',
      confirmButtonText: '删除',
      cancelButtonText: '取消'
    })
    emit('remove', session.id)
  } catch {
    // 用户取消
  }
}

async function confirmClear() {
  if (!props.sessions.length) return
  try {
    await ElMessageBox.confirm(
      `将永久删除${ props.clearScopeLabel }的全部 ${ props.sessions.length } 条历史会话，此操作无法恢复。`,
      '清空历史会话',
      {
        type: 'warning',
        confirmButtonText: '全部删除',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger'
      }
    )
    emit('clear')
  } catch {
    // 用户取消
  }
}

function formatTime(timestamp) {
  if (!timestamp) return ''
  const time = dayjs(timestamp)
  return time.isSame(dayjs(), 'day') ? time.format('HH:mm') : time.format('MM-DD')
}
</script>

<style lang="scss" scoped>
.session_list {
  display: flex;
  flex-direction: column;
  height: 100%;
  border-right: 1px solid #e4e7ed;

  &.is_dark {
    border-right-color: #3a3a3a;
  }

  .list_head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 10px;
    font-size: 13px;
    font-weight: 500;

    .head_actions {
      display: flex;
      align-items: center;
      gap: 2px;
    }
  }

  .list_body {
    flex: 1;
    min-height: 0;

    .empty {
      padding: 16px 10px;
      color: #909399;
      font-size: 12px;
      text-align: center;
    }
  }

  .session_row {
    display: flex;
    align-items: center;
    gap: 4px;
    height: 52px;
    box-sizing: border-box;
    padding: 6px 10px;
    cursor: pointer;
    border-radius: 6px;
    margin: 0 4px 2px;

    &:hover {
      background-color: rgba(0, 0, 0, 0.04);

      .row_actions {
        visibility: visible;
      }
    }

    &.is_active {
      background-color: rgba(64, 158, 255, 0.12);
    }

    .row_main {
      flex: 1;
      min-width: 0;
      height: 40px;

      :deep(.el-input) {
        display: block;
        height: 22px;
        --el-input-height: 22px;
      }

      :deep(.el-input__wrapper) {
        min-height: 22px;
        box-sizing: border-box;
      }

      .row_title {
        display: block;
        height: 22px;
        line-height: 22px;
        font-size: 13px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .row_meta {
        display: block;
        height: 18px;
        line-height: 18px;
        color: #909399;
        font-size: 11px;
      }
    }

    .row_actions {
      visibility: hidden;
      flex-shrink: 0;
      display: flex;
    }
  }

  &.is_dark .session_row:hover {
    background-color: rgba(255, 255, 255, 0.06);
  }
}
</style>
