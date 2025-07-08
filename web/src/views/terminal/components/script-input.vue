<template>
  <div class="script_input_container">
    <PlusLimitTip />
    <div class="left_box">
      <div class="group_list">
        <div
          v-for="group in scriptGroupList"
          :key="group.id"
          :class="['group_item', { active: activeGroup === group.id }]"
          @click="handleSelectGroup(group)"
        >
          {{ group.name }}
        </div>
        <div
          class="group_item group_manage"
          @click="handleShowGroupManage"
        >
          <el-icon><Setting /></el-icon>
          分组管理
        </div>
      </div>
      <div class="script_list">
        <template v-if="filteredScripts.length">
          <div
            v-for="script in filteredScripts"
            :key="script.id"
            class="script_item"
          >
            <div class="script_info">
              <span class="script_name">{{ script.name }}:</span>
              <span class="script_command">{{ script.command }}</span>
            </div>
            <div class="hover_icons">
              <el-icon
                class="action_icon"
                title="执行"
                @click="handleExecScript(script)"
              >
                <VideoPlay />
              </el-icon>
              <el-icon
                v-if="activeGroup !== 'builtin'"
                class="action_icon"
                title="编辑脚本"
                @click="handleEditScript(script)"
              >
                <Edit />
              </el-icon>
              <el-icon
                class="action_icon"
                title="发送到脚本编辑器"
                @click="handleSendToEditor(script)"
              >
                <ArrowRightBold />
              </el-icon>
            </div>
          </div>
          <div
            v-if="activeGroup !== 'builtin'"
            class="script_item add_script_btn"
            @click="handleAddScript"
          >
            <el-icon><Plus /></el-icon>
            <span>新建脚本</span>
          </div>
        </template>
        <div v-else class="empty-list">
          <el-empty
            :image-size="38"
            description="暂无脚本"
          >
            <template #description>
              <p>当前分组暂无脚本</p>
            </template>
            <el-button
              size="small"
              type="primary"
              @click="handleAddScript"
            >
              添加脚本
            </el-button>
          </el-empty>
        </div>
      </div>
    </div>
    <div class="right_box">
      <div class="editor_title">脚本编辑器</div>
      <div class="editor_content">
        <el-input
          v-model="scriptContent"
          type="textarea"
          :rows="10"
          placeholder="请输入脚本内容..."
        />
        <div class="action_btn">
          <el-dropdown
            split-button
            trigger="click"
            type="primary"
            size="small"
            :disabled="!scriptContent"
            @click="handleSendToTerminal"
          >
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item>发送至当前窗口终端</el-dropdown-item>
                <el-dropdown-item>发送至所有窗口终端</el-dropdown-item>
                <el-dropdown-item @click="handleSaveAsScript">保存至脚本库</el-dropdown-item>
                <el-dropdown-item @click="handleSendClearContent">发送后清空内容: {{ isClearContent ? '是' : '否' }}</el-dropdown-item>
              </el-dropdown-menu>
            </template>
            发送至终端
          </el-dropdown>
        </div>
      </div>
    </div>
  </div>
  <ScriptEdit
    v-model:show="scriptEditVisible"
    :default-data="editScriptData"
    :default-script="scriptContent"
    :default-group="activeGroup"
    @success="handleScriptEditSuccess"
  />

  <ScriptGroup
    v-model:show="scriptGroupVisible"
    @group-deleted="handleGroupDeleted"
  />
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { useRouter } from 'vue-router'
import { VideoPlay, Edit, Setting, Plus, ArrowRightBold } from '@element-plus/icons-vue'
import ScriptEdit from '@/views/scripts/components/script-edit.vue'
import ScriptGroup from '@/views/scripts/components/script-group.vue'
import PlusLimitTip from '@/components/common/PlusLimitTip.vue'

defineProps({
  hostId: {
    required: true,
    type: String
  }
})

const emit = defineEmits(['exec-command',])

const { proxy: { $store, $message } } = getCurrentInstance()

const router = useRouter()
const scriptContent = ref('')
const activeGroup = ref('')
const scriptEditVisible = ref(false)
const editScriptData = ref(null)
const scriptGroupVisible = ref(false)
const isClearContent = ref(false)

const isPlusActive = computed(() => $store.isPlusActive)
const scriptGroupList = computed(() => $store.scriptGroupList || [])
const scriptList = computed(() => $store.scriptList || [])

const gotoPlusPage = () => {
  router.push('/setting?tabKey=plus')
}

const filteredScripts = computed(() => {
  return scriptList.value.filter(script => script.group === activeGroup.value)
})

const handleSelectGroup = (group) => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  activeGroup.value = group.id
}

const handleExecScript = (script) => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  emit('exec-command', script.command)
}

const handleEditScript = (script) => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  editScriptData.value = script
  scriptEditVisible.value = true
}

const handleSendToEditor = (script) => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  scriptContent.value = script.command
}

const handleSendToTerminal = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  emit('exec-command', scriptContent.value)
  if (isClearContent.value) {
    scriptContent.value = ''
  }
}

const handleSendClearContent = () => {
  isClearContent.value = !isClearContent.value
}

const handleAddScript = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  editScriptData.value = null
  scriptEditVisible.value = true
}

const handleScriptEditSuccess = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  editScriptData.value = null
}

const handleShowGroupManage = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  scriptGroupVisible.value = true
}

const handleGroupDeleted = (deletedGroupId) => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  if (deletedGroupId === activeGroup.value) {
    // 如果删除的是当前选中的分组，切换到第一个分组
    if (scriptGroupList.value.length) {
      activeGroup.value = scriptGroupList.value[0].id
    }
  }
}

const handleSaveAsScript = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  if (!scriptContent.value) {
    return $message.warning('请先输入脚本内容')
  }
  scriptEditVisible.value = true
}

if (scriptGroupList.value.length) {
  activeGroup.value = scriptGroupList.value[0].id
}
</script>

<style lang="scss" scoped>
.script_input_container {
  height: 100%;
  display: flex;
  gap: 10px;
  padding: 10px;
  min-width: 0;
  position: relative;
  .left_box {
    width: 50%;
    min-width: 50%;
    max-width: 50%;
    flex: 0 0 50%;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--el-border-color);
    border-radius: 4px;

    .group_list {
      padding: 6px 10px;
      height: 32px;
      box-sizing: border-box;
      border-bottom: 1px solid var(--el-border-color);
      display: flex;
      flex-wrap: nowrap;
      gap: 8px;
      overflow-x: auto;
      overflow-y: hidden;
      white-space: nowrap;

      &::-webkit-scrollbar {
        display: none;
      }

      .group_item {
        padding: 2px 12px;
        cursor: pointer;
        border-radius: 12px;
        margin-bottom: 0;
        font-size: 13px;
        border: 1px solid var(--el-border-color-light);
        flex-shrink: 0;
        transition: all 0.2s;

        &:hover {
          background-color: var(--el-fill-color-light);
          border-color: var(--el-border-color);
        }

        &.active {
          background-color: var(--el-color-primary-light-9);
          color: var(--el-color-primary);
          border-color: var(--el-color-primary-light-7);
        }

        &.group_manage {
          display: flex;
          align-items: center;
          gap: 4px;
          border-color: var(--el-color-info-light-5);
          color: var(--el-text-color-regular);

          .el-icon {
            font-size: 14px;
          }

        }
      }
    }

    .script_list {
      flex: 1;
      overflow-y: auto;
      padding: 10px;
      .empty-list {
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--el-text-color-secondary);

        :deep(.el-empty__description) {
          margin-bottom: 0px;
          p {
            margin: 0;
            line-height: 0.5;

            &.sub-text {
              font-size: 12px;
              color: var(--el-text-color-placeholder);
            }
          }
        }
      }

      .script_item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        height: 36px;
        padding: 0 12px;
        border-radius: 4px;
        cursor: pointer;
        border: 1px solid transparent;
        transition: all 0.2s ease;
        line-height: 36px;

        &:hover {
          background-color: var(--el-fill-color-light);
          border-color: var(--el-border-color);
          .hover_icons {
            opacity: 1;
            transform: translateX(0);
          }
        }

        .script_info {
          flex: 1;
          display: flex;
          align-items: center;
          min-width: 0;
          margin-right: 8px;
          height: 100%;
          padding: 2px 0;

          .script_name {
            flex-shrink: 0;
            font-size: 13px;
            color: var(--el-text-color-regular);
            margin-right: 4px;
            line-height: normal;

            &::before {
              content: '⌘';
              margin-right: 6px;
              color: var(--el-text-color-secondary);
              font-size: 12px;
            }
          }

          .script_command {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-size: 13px;
            color: var(--el-text-color-secondary);
            line-height: normal;
            padding: 2px 0;
          }
        }

        .hover_icons {
          display: flex;
          gap: 8px;
          opacity: 0;
          transform: translateX(10px);
          transition: all 0.2s ease;
          flex-shrink: 0;
          height: 100%;
          align-items: center;
          padding: 2px 0;

          .action_icon {
            font-size: 16px;
            color: var(--el-text-color-secondary);
            padding: 4px;
            border-radius: 4px;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            width: 24px;
            height: 24px;

            &:hover {
              color: var(--el-color-primary);
              background-color: var(--el-color-primary-light-9);
              transform: scale(1.1);
            }
          }
        }

        &.add_script_btn {
          justify-content: center;
          color: var(--el-text-color-secondary);
          border: 1px dashed var(--el-border-color);
          margin-top: 10px;
          background-color: var(--el-fill-color-blank);

          .el-icon {
            font-size: 14px;
            margin-right: 4px;
          }

          span {
            font-size: 13px;
          }

          &:hover {
            color: var(--el-color-primary);
            border-color: var(--el-color-primary);
            background-color: var(--el-color-primary-light-9);
          }
        }
      }
    }
  }

  .right_box {
    width: 50%;
    min-width: 50%;
    max-width: 50%;
    flex: 0 0 50%;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--el-border-color);
    border-radius: 4px;
    position: relative;

    .editor_title {
      padding: 6px 10px;
      height: 32px;
      box-sizing: border-box;
      font-size: 14px;
      font-weight: 500;
      color: var(--el-text-color-primary);
      border-bottom: 1px solid var(--el-border-color);
      display: flex;
      align-items: center;
    }

    .editor_content {
      flex: 1;
      display: flex;
      flex-direction: column;
      position: relative;
      padding: 10px;
      height: calc(100% - 32px);

      .el-textarea {
        height: 100%;
        :deep(.el-textarea__inner) {
          height: 100%;
          resize: none;
        }
      }

      .action_btn {
        position: absolute;
        right: 20px;
        bottom: 20px;
        z-index: 1;
        display: flex;
        gap: 10px;
      }
    }
  }
}
</style>