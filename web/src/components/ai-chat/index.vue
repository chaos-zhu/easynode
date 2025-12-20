<template>
  <el-drawer
    v-model="visible"
    size="100%"
    :modal="false"
    :with-header="true"
    :lock-scroll="false"
    :close-on-press-escape="false"
    modal-class="ai_chat_drawer"
    class="ai_chat_drawer"
  >
    <template #header>
      <div class="ai_header_wrap">
        <el-dropdown v-if="hasMoreModels" trigger="click" class="model_dropdown">
          <span class="model_dropdown_link">
            {{ activeModel }}
            <el-icon>
              <ArrowDown />
            </el-icon>
          </span>
          <template #dropdown>
            <el-dropdown-menu class="model_dropdown_menu">
              <el-dropdown-item
                v-for="model in models"
                :key="model"
                :class="{ 'active': activeModel === model }"
                @click="handleModelChange(model)"
              >
                {{ model }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <div class="right_wrap">
          <el-icon
            class="right_wrap_icon"
            title="新建对话"
            @click="handleNewChat"
          >
            <Plus />
          </el-icon>
          <el-dropdown
            :disabled="!hasChatHistory"
            trigger="click"
            class="chat_list_dropdown"
          >
            <el-icon
              class="right_wrap_icon"
              title="历史记录"
            >
              <ChatDotRound />
            </el-icon>
            <template #dropdown>
              <el-dropdown-menu class="chat_list_dropdown_menu">
                <el-dropdown-item
                  v-for="chatItem in chatHistory"
                  :key="chatItem.id"
                  :class="{ 'active': chatId === chatItem.id }"
                  @click="handleChangeChat(chatItem.id)"
                >
                  <div class="chat_item">
                    <div class="chat_item_info">
                      <span class="descript">{{ chatItem.describe }}</span>
                      <span class="created">{{ new Date(chatItem.createdAt).toLocaleString() }}</span>
                    </div>
                    <el-icon class="chat_item_icon" @click.stop="handleDeleteChat(chatItem.id)">
                      <Delete />
                    </el-icon>
                  </div>
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <el-icon
            :size="18"
            class="right_wrap_icon"
            title="设置"
            @click="handleSetting"
          >
            <Setting />
          </el-icon>
        </div>
      </div>
    </template>
    <div class="chat_box">
      <div
        ref="chatListBox"
        class="chat_list_box"
        @scroll="handleScroll"
      >
        <div v-for="(item, index) in chatList" :key="item.id" class="chat_list_item">
          <div
            class="message_bubble"
            :class="[item.role === 'assistant' ? 'bubble_start' : 'bubble_end']"
          >
            <!-- 头像 -->
            <div class="bubble_avatar">
              <svg-icon v-if="item.role === 'assistant'" name="icon-AI-money" class="ai_avatar" />
              <el-icon v-else :size="20" class="user_avatar"><Avatar /></el-icon>
            </div>

            <!-- 消息内容区域 -->
            <div class="bubble_content_wrap">
              <!-- 推理过程（仅AI消息且有reasoning） -->
              <div v-if="item.role === 'assistant' && item.reasoning" class="reasoning_box">
                <el-collapse
                  :key="`collapse-${item.id}-${item.isStreaming}`"
                  :model-value="(isReasoning && item.isStreaming) ? [item.id] : []"
                >
                  <el-collapse-item :name="item.id">
                    <template #title>
                      <div class="reasoning_title">
                        <span class="reasoning_text">
                          {{ (isReasoning && item.isStreaming) ? '思考中' : '已深度思考' }}
                          {{ item.reasoningTime ? `(用时:${(item.reasoningTime / 1000).toFixed(1)}s)` : '' }}
                        </span>
                        <el-icon class="reasoning_icon">
                          <CircleCheck v-if="!item.isStreaming" />
                          <Loading v-else />
                        </el-icon>
                      </div>
                    </template>
                    <div class="reasoning_content">
                      <MarkdownRender
                        :content="item.reasoning"
                        :is-dark="isDark"
                        :typewriter="true"
                        custom-id="reasoning"
                      />
                    </div>
                  </el-collapse-item>
                </el-collapse>
              </div>

              <!-- 消息内容 -->
              <div class="bubble_content">
                <!-- 编辑模式 -->
                <template v-if="item.isEditing">
                  <div class="message_edit_container">
                    <el-input
                      v-model="item.editingContent"
                      type="textarea"
                      :autosize="{ minRows: 3, maxRows: 10 }"
                      placeholder="编辑消息内容"
                      class="edit_textarea"
                    />
                    <div class="edit_actions">
                      <el-button
                        type="primary"
                        size="small"
                        :loading="loading"
                        @click="handleConfirmEdit(item.id, item.editingContent)"
                      >
                        确认
                      </el-button>
                      <el-button
                        size="small"
                        @click="handleCancelEdit(item.id)"
                      >
                        取消
                      </el-button>
                    </div>
                  </div>
                </template>

                <!-- 正常显示模式 -->
                <template v-else>
                  <!-- 加载中状态 -->
                  <div v-if="isConnecting && index === chatList.length - 1 && !item.content" class="loading_dots">
                    <span />
                    <span />
                    <span />
                  </div>

                  <!-- Markdown 内容渲染 -->
                  <MarkdownRender
                    v-else
                    :content="item.content"
                    :is-dark="isDark"
                    :typewriter="true"
                    :code-block-stream="item.isStreaming"
                    custom-id="chat"
                    @copy="handleCopy"
                  />
                </template>
              </div>

              <!-- 操作按钮 -->
              <div v-if="index !== 0 && !item.isEditing" class="action_btn">
                <el-button
                  size="small"
                  :icon="Refresh"
                  circle
                  title="重新生成"
                  @click="regenerateMessage(item.id, activeModel)"
                />
                <el-button
                  size="small"
                  :icon="CopyDocument"
                  circle
                  title="复制"
                  @click="copyContent(item.content)"
                />
                <el-button
                  size="small"
                  :icon="Delete"
                  circle
                  title="删除"
                  @click="deleteMessage(item.id)"
                />
                <el-button
                  v-if="item.role === 'user'"
                  size="small"
                  :icon="EditPen"
                  circle
                  title="编辑"
                  @click="handleStartEdit(item.id)"
                />
              </div>
            </div>
          </div>
        </div>
        <el-divider v-show="chatList.length > 1" content-position="center" class="clear_history_divider">
          <svg-icon name="icon-saoba" style="width: 16px; height: 16px;" />
          <el-popconfirm title="确定清空？" @confirm="clearChat">
            <template #reference>
              <span class="clear_history">清空历史记录</span>
            </template>
          </el-popconfirm>
        </el-divider>
      </div>
      <!-- 置顶和置底按钮 -->
      <div v-show="showScrollButtons" class="scroll_buttons">
        <el-icon
          class="scroll_btn"
          :class="{ 'is_disabled': isAtTop }"
          title="滚动到顶部"
          @click="scrollToTop"
        >
          <Top />
        </el-icon>
        <el-icon
          class="scroll_btn"
          :class="{ 'is_disabled': isAtBottom }"
          title="滚动到底部"
          @click="scrollToBottomManual"
        >
          <Bottom />
        </el-icon>
      </div>
      <div class="sender_box">
        <Sender
          v-model:value="question"
          :loading="loading"
          @submit="submit"
          @cancel="stopGeneration"
        />
      </div>
    </div>
    <AiApiConfig v-model:show="aiApiConfigVisible" :ai-config="aiConfig" />
  </el-drawer>
</template>

<script setup>
import { ref, computed, nextTick, watch, getCurrentInstance, onMounted } from 'vue'
import MarkdownRender, { setCustomComponents } from 'markstream-vue'
import 'markstream-vue/index.css'
import 'highlight.js/styles/github-dark.css'
import { Sender } from 'ant-design-x-vue'
import { Avatar, Refresh, CopyDocument, Delete, EditPen, CircleCheck, Loading, Setting, ArrowDown, ChatDotRound, Plus, Top, Bottom } from '@element-plus/icons-vue'
import { useAIChat } from '@/composables/useAIChat'
import AiApiConfig from './ai-api-config.vue'
import { EventBus } from '@/utils'
import CustomCodeBlock from './custom-code-block.vue'

const { proxy: { $message, $store } } = getCurrentInstance()

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:visible',])

const {
  chatId,
  chatList,
  loading,
  isConnecting,
  isReasoning,
  sendMessage,
  clearChat,
  stopGeneration,
  deleteMessage,
  regenerateMessage,
  changeChat,
  removeChat,
  addChat,
  startEditMessage,
  cancelEditMessage,
  confirmEditMessage
} = useAIChat()

const aiApiConfigVisible = ref(false)
const activeModel = ref(localStorage.getItem('activeModel') || '')
const question = ref('')
const isDark = computed(() => $store.isDark)
const isPlusActive = computed(() => $store.isPlusActive)
const aiConfig = computed(() => $store.aiConfig)
const models = computed(() => aiConfig.value?.models || [])
const chatHistory = computed(() => $store.chatHistory)
const hasMoreModels = computed(() => Array.isArray(models.value) && models.value.length > 1)
const hasChatHistory = computed(() => chatHistory.value.length > 0)
const visible = computed({
  get() {
    return props.visible
  },
  set(value) {
    emit('update:visible', value)
  }
})

// 注册自定义代码块组件
onMounted(() => {
  setCustomComponents('chat', {
    code_block: CustomCodeBlock
  })
  setCustomComponents('reasoning', {
    code_block: CustomCodeBlock
  })
})

watch(() => models.value, (newValue) => {
  if (!newValue?.length) return
  if (!activeModel.value || !newValue.includes(activeModel.value)) {
    activeModel.value = newValue[0]
  }
}, { immediate: true })

watch(() => chatList.value, () => {
  scrollToBottom()
}, { deep: true })

watch(() => visible.value, (newValue) => {
  if (!newValue) return
  nextTick(() => {
    inputFocus()
    if (chatListBox.value) {
      chatListBox.value.scrollTo({
        top: chatListBox.value?.scrollHeight,
        behavior: 'smooth'
      })
    }
  })
})

const inputFocus = () => {
  let input = document.querySelector('.ant-sender-input')
  setTimeout(() => {
    input?.focus()
  }, 300)
}

const handleModelChange = (model) => {
  activeModel.value = model
  localStorage.setItem('activeModel', model)
  inputFocus()
}

const chatListBox = ref(null)
const shouldAutoScroll = ref(true)
const showScrollButtons = ref(false)
const isAtTop = ref(true)
const isAtBottom = ref(true)

const handleScroll = () => {
  if (!chatListBox.value) return
  const element = chatListBox.value
  const hasScrollbar = element.scrollHeight > element.clientHeight
  const atBottom = Math.abs(element.scrollHeight - element.scrollTop - element.clientHeight) < 10
  const atTop = element.scrollTop < 10
  shouldAutoScroll.value = atBottom
  isAtTop.value = atTop
  isAtBottom.value = atBottom
  // 只有当存在滚动条时才显示按钮
  showScrollButtons.value = hasScrollbar
}

const scrollToBottom = () => {
  if (!shouldAutoScroll.value || !chatListBox.value) return
  nextTick(() => {
    chatListBox.value.scrollTop = chatListBox.value.scrollHeight
  })
}

const scrollToTop = () => {
  if (!chatListBox.value) return
  chatListBox.value.scrollTo({
    top: 0,
    behavior: 'smooth'
  })
}

const scrollToBottomManual = () => {
  if (!chatListBox.value) return
  shouldAutoScroll.value = true
  chatListBox.value.scrollTo({
    top: chatListBox.value.scrollHeight,
    behavior: 'smooth'
  })
}

const handleStartEdit = (messageId) => {
  if (loading.value) {
    $message.warning('请等待当前对话响应完成')
    return
  }
  startEditMessage(messageId)
}

const handleCancelEdit = (messageId) => {
  cancelEditMessage(messageId)
}

const handleConfirmEdit = async (messageId, newContent) => {
  if (!newContent || !newContent.trim()) {
    $message.warning('内容不能为空')
    return
  }
  await confirmEditMessage(messageId, newContent.trim(), activeModel.value)
}

EventBus.$on('sendToAIInput', (text) => {
  question.value = text
  visible.value = true
  inputFocus()
})

const submit = async function (questionStr) {
  if (!questionStr || loading.value) return
  question.value = ''
  shouldAutoScroll.value = true
  await sendMessage(questionStr, activeModel.value)
}

const copyContent = async (content) => {
  try {
    await navigator.clipboard.writeText(content)
    $message.success('复制成功')
  } catch (err) {
    $message.error('复制失败')
  }
}

const handleCopy = (text) => {
  copyContent(text)
}

const handleSetting = () => {
  if (!isPlusActive.value) {
    $message.warning('请先激活Plus')
    return
  }
  aiApiConfigVisible.value = true
}

const isLoadingTips = () => {
  if (loading.value) {
    $message.warning('请等待当前对话响应完成')
    return true
  }
  return false
}

const handleNewChat = () => {
  if (isLoadingTips()) return
  addChat()
  inputFocus()
}

const handleDeleteChat = async (id) => {
  if (isLoadingTips()) return
  await removeChat(id)
  inputFocus()
}

const handleChangeChat = (id) => {
  if (isLoadingTips()) return
  changeChat(id)
  inputFocus()
}
</script>

<style scoped lang="scss">
.ai_header_wrap {
  display: flex;
  align-items: center;
  justify-content: space-between;
  .right_wrap {
    display: flex;
    align-items: center;
    gap: 10px;
    .right_wrap_icon {
      cursor: pointer;
      font-size: 18px;
      color: var(--el-text-color-regular);
      &:hover {
        color: var(--el-color-primary);
      }
    }
  }
  .chat_list_dropdown,
  .model_dropdown {
    cursor: pointer;
  }
  .model_dropdown_link {
    display: flex;
    align-items: center;
    justify-content: center;
  }
}

.message_edit_container {
  width: 380px;

  .edit_textarea {
    margin-bottom: 10px;
    width: 100%;

    :deep(.el-textarea__inner) {
      width: 100% !important;
      border-color: v-bind('isDark ? "#454242" : "#d9d9d9"');
      background-color: v-bind('isDark ? "#1a1a1a" : "#fff"');
      color: v-bind('isDark ? "#bbb" : "#000"');

      &:focus {
        border-color: #1677ff;
      }
    }
  }

  .edit_actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
  }
}

.loading_dots {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 8px 0;

  span {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background-color: var(--el-color-primary);
    animation: loading-bounce 1.4s infinite ease-in-out both;

    &:nth-child(1) {
      animation-delay: -0.32s;
    }
    &:nth-child(2) {
      animation-delay: -0.16s;
    }
  }
}

@keyframes loading-bounce {
  0%, 80%, 100% {
    transform: scale(0);
  }
  40% {
    transform: scale(1);
  }
}
</style>

<style lang="scss">
.ai_chat_drawer {
  inset: unset !important;
  right: 0 !important;
  top: 0 !important;
  bottom: 0 !important;
  width: 30%;
  min-width: 350px;
  background-color: v-bind('isDark ? "#0d1117" : "#fff"');

  .el-drawer__header {
    margin-bottom: 0;
    padding-bottom: 10px;
    border-bottom: 1px solid v-bind('isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.06)"');
  }

  .el-drawer__body {
    padding: 10px;

    .chat_box {
      height: 100%;
      min-height: 300px;
      overflow-y: auto;
      display: flex;
      flex-direction: column;

      .ant-sender {
        border-color: v-bind('isDark ? "#454242" : "#d9d9d9"');
        &:focus-within {
          border-color: #1677ff;
        }
        .ant-sender-input {
          color: v-bind('isDark ? "#bbb" : "#000"');
        }
        .ant-sender-content {
          padding: 6px 12px;
        }
      }

      .chat_list_box {
        flex: 1;
        overflow-y: auto;
        padding-bottom: 10px;
        display: flex;
        flex-direction: column;

        .chat_list_item {
          position: relative;
          padding-bottom: 15px;

          .message_bubble {
            display: flex;
            gap: 10px;

            &.bubble_start {
              flex-direction: row;

              .bubble_content_wrap {
                align-items: flex-start;
              }

              .action_btn {
                left: 45px;
              }
            }

            &.bubble_end {
              flex-direction: row-reverse;

              .bubble_content_wrap {
                align-items: flex-end;
              }

              .action_btn {
                right: 45px;
              }
            }

            .bubble_avatar {
              flex-shrink: 0;
              width: 32px;
              height: 32px;
              display: flex;
              align-items: center;
              justify-content: center;

              .ai_avatar {
                width: 25px;
                height: 25px;
                color: var(--el-menu-active-color);
              }

              .user_avatar {
                color: #887dfd;
              }
            }

            .bubble_content_wrap {
              flex: 1;
              display: flex;
              flex-direction: column;
              min-width: 0;

              .reasoning_box {
                width: 100%;
                border: 1px solid v-bind('isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.06)"');
                background-color: v-bind('isDark ? "inherit" : "#f0f2f5"');
                border-radius: 4px;
                margin-bottom: 10px;

                .el-collapse {
                  padding: 0 10px;
                  .el-collapse-item__header {
                    border: none;
                  }
                }
                .el-collapse-item__header {
                  background-color: transparent;
                  height: 36px;
                }
                .el-collapse-item__wrap {
                  background-color: transparent;
                  .el-collapse-item__content {
                    padding-bottom: 10px;
                  }
                }

                .reasoning_title {
                  display: flex;
                  align-items: center;
                  justify-content: space-between;

                  .reasoning_text {
                    color: #887dfd;
                  }

                  .reasoning_icon {
                    color: #887dfd;
                    margin-left: 10px;
                  }
                }

                .reasoning_content {
                  font-size: 13px;
                  opacity: 0.85;
                }
              }

              .bubble_content {
                max-width: 100%;
                padding: 10px 14px;
                border-radius: 8px;
                border: 1px solid v-bind('isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.06)"');
                word-break: break-word;
                line-height: 1.3;

                .markstream-vue {
                  font-size: 14px;

                  // 段落样式
                  p {
                    line-height: 1.3;
                  }

                  .node-content > .paragraph-node {
                    margin: 0;
                  }

                  // 表格容器样式
                  .markstream-table-wrapper,
                  > div:has(table) {
                    width: 100%;
                    overflow-x: auto;
                    margin: 12px 0;
                  }

                  // 表格样式 - 只有水平分隔线
                  table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 14px;
                    table-layout: auto;

                    thead tr {
                      border-bottom: 2px solid v-bind('isDark ? "rgba(255, 255, 255, 0.15)" : "rgba(0, 0, 0, 0.1)"');
                    }

                    th, td {
                      padding: 10px 16px;
                      border: none;
                      border-bottom: 1px solid v-bind('isDark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.06)"');
                      white-space: nowrap;
                    }

                    th {
                      font-weight: 600;
                      color: v-bind('isDark ? "#58a6ff" : "#0969da"');
                      text-align: left;
                    }

                    td {
                      text-align: left;
                    }

                    // 支持对齐
                    th[align="center"], td[align="center"],
                    th[style*="text-align: center"], td[style*="text-align: center"] {
                      text-align: center;
                    }

                    th[align="right"], td[align="right"],
                    th[style*="text-align: right"], td[style*="text-align: right"] {
                      text-align: right;
                    }

                    tbody tr:last-child td {
                      border-bottom: none;
                    }
                  }
                }
              }
            }

            .action_btn {
              position: absolute;
              bottom: 1px;
              visibility: hidden;
              opacity: 0;
              transition: all 0.5s ease;
            }
          }

          &:hover .action_btn {
            visibility: visible;
            opacity: 1;
          }
        }

        .clear_history_divider {
          margin-top: 20px;
          flex-shrink: 0;
          .clear_history {
            margin-left: 5px;
            text-align: center;
            color: #887dfd;
            cursor: pointer;
            user-select: none;
          }
        }
      }

      .scroll_buttons {
        position: absolute;
        right: 20px;
        bottom: 80px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        z-index: 10;

        .scroll_btn {
          width: 28px;
          height: 28px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
          background-color: v-bind('isDark ? "rgba(255, 255, 255, 0.1)" : "rgba(0, 0, 0, 0.06)"');
          color: v-bind('isDark ? "#bbb" : "#666"');
          cursor: pointer;
          transition: all 0.3s ease;
          font-size: 14px;
          box-shadow: 0 2px 6px rgba(0, 0, 0, 0.12);

          &:hover:not(.is_disabled) {
            background-color: var(--el-color-primary);
            color: #fff;
            transform: scale(1.1);
          }

          &.is_disabled {
            opacity: 0.4;
            cursor: not-allowed;
          }
        }
      }

      .sender_box {
        margin-top: auto;
      }
    }
  }
}

.chat_list_dropdown_menu {
  max-height: 70vh;
  width: 310px;
  overflow: auto;
  .el-dropdown-menu__item {
    padding: 5px 8px;
  }
  .chat_item {
    height: 100%;
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: space-between;
    .chat_item_info {
      flex: 1;
      display: flex;
      align-content: center;
      justify-content: space-between;
      .descript {
        width: 160px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .created {
        flex: 1;
        padding: 0 10px;
        opacity: 0.6;
        font-size: 12px;
      }
    }
    &:hover .chat_item_icon {
      opacity: 1;
    }
    .chat_item_icon {
      opacity: 0;
      flex-shrink: 0;
      cursor: pointer;
      color: var(--el-text-color-regular);
      &:hover {
        color: var(--el-color-primary);
      }
    }
  }
  .active {
    background-color: var(--el-dropdown-menuItem-hover-fill);
    color: var(--el-dropdown-menuItem-hover-color);
  }
}

.model_dropdown_menu {
  max-height: 70vh;
  max-width: 375px;
  overflow: auto;
  .active {
    background-color: var(--el-dropdown-menuItem-hover-fill);
    color: var(--el-dropdown-menuItem-hover-color);
  }
}
</style>