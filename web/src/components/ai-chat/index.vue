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
          <Bubble
            :loading="isConnecting && index === chatList.length - 1"
            :placement="item.role === 'assistant' ? 'start' : 'end'"
            :content="item.content"
            :message-render="renderMarkdown"
          >
            <template #avatar>
              <svg-icon v-if="item.role === 'assistant'" name="icon-AI-money" style="width: 25px; height: 25px;color: var(--el-menu-active-color);" />
              <el-icon v-else :size="20" style="color: #887dfd;"><Avatar /></el-icon>
            </template>
            <template #header>
              <div v-show="item.reasoning" class="reasoning_box">
                <el-collapse :model-value="(isReasoning && item.isStreaming) ? [item.id] : []">
                  <el-collapse-item :name="item.id">
                    <template #title>
                      <div style="display: flex; align-items: center; justify-content: space-between;">
                        <span style="color: #887dfd;">
                          {{ (isReasoning && item.isStreaming) ? '思考中' : '已深度思考' }}
                          {{ item.reasoningTime ? `(用时:${(item.reasoningTime / 1000).toFixed(1)}s)` : '' }}
                        </span>
                        <el-icon class="header-icon" style="color: #887dfd;margin-left: 10px;">
                          <CircleCheck v-if="!isReasoning" style="color: #887dfd;" />
                          <Loading v-else style="color: #887dfd;" />
                        </el-icon>
                      </div>
                    </template>
                    <div v-html="md.render(item.reasoning || '')" />
                  </el-collapse-item>
                </el-collapse>
              </div>
            </template>
            <template v-if="index !== 0" #footer>
              <div class="action_btn" :style="item.role === 'assistant' ? 'left: 45px;' : 'right: 45px;'">
                <el-button
                  size="small"
                  :icon="Refresh"
                  circle
                  @click="regenerateMessage(item.id, activeModel)"
                />
                <el-button
                  size="small"
                  :icon="CopyDocument"
                  circle
                  @click="copyContent(item.content)"
                />
                <el-button
                  size="small"
                  :icon="Delete"
                  circle
                  @click="deleteMessage(item.id)"
                />
                <el-button
                  v-show="item.role === 'user'"
                  size="small"
                  :icon="EditPen"
                  circle
                  @click="editMessage(item.content)"
                />
              </div>
            </template>
          </Bubble>
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
import MarkdownIt from 'markdown-it'
import hljs from 'highlight.js'
import 'highlight.js/styles/github-dark.css'
import { ref, computed, h, nextTick, watch, getCurrentInstance } from 'vue'
import { Bubble, Sender } from 'ant-design-x-vue'
import { Avatar, Refresh, CopyDocument, Delete, EditPen, CircleCheck, Loading, Setting, ArrowDown, ChatDotRound, Plus } from '@element-plus/icons-vue'
import { useAIChat } from '@/composables/useAIChat'
import { loadMarkdownCSS } from '@/utils/markdown'
import AiApiConfig from './ai-api-config.vue'
import { EventBus } from '@/utils'

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: true,
  highlight: function (str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(str, { language: lang }).value
      } catch (__) {console.warn(__)}
    }
    return ''
  }
})

md.renderer.rules.link_open = function (tokens, idx, options, env, self) {
  const token = tokens[idx]
  token.attrSet('target', '_blank')
  token.attrSet('rel', 'noopener noreferrer')
  return self.renderToken(tokens, idx, options)
}

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
  // error,
  sendMessage,
  clearChat,
  stopGeneration,
  deleteMessage,
  regenerateMessage,
  changeChat,
  removeChat,
  addChat
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

watch(() => models.value, (newValue) => {
  if (!newValue?.length) return
  if (!activeModel.value || !newValue.includes(activeModel.value)) {
    activeModel.value = newValue[0]
  }
}, { immediate: true })

watch(() => isDark.value, (newValue) => {
  loadMarkdownCSS(newValue)
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

const renderMarkdown = (content) => {
  const renderedContent = md.render(content)

  const processCodeBlocks = () => {
    nextTick(() => {
      const codeBlocks = document.querySelectorAll('.markdown-body pre')

      codeBlocks.forEach(pre => {
        if (pre.classList.contains('code-block-processed')) return
        pre.classList.add('code-block-processed')
        pre.style.position = 'relative'
        if (!pre.querySelector('.code_copy_btn')) {
          const copyBtn = document.createElement('div')
          copyBtn.classList.add('code_btn')
          copyBtn.classList.add('code_copy_btn')
          copyBtn.innerHTML = '复制'
          copyBtn.addEventListener('click', (e) => {
            e.stopPropagation()
            const codeElement = pre.querySelector('code')
            if (codeElement) {
              const codeText = codeElement.textContent || ''
              copyContent(codeText)
            }
          })
          pre.appendChild(copyBtn)
        }
        if (!pre.querySelector('.code_exec_btn')) {
          const execBtn = document.createElement('div')
          execBtn.classList.add('code_btn')
          execBtn.classList.add('code_exec_btn')
          execBtn.innerHTML = '执行'
          execBtn.addEventListener('click', (e) => {
            e.stopPropagation()
            const codeElement = pre.querySelector('code')
            if (codeElement) {
              const codeText = codeElement.textContent?.trim() || ''
              // console.log(codeText)
              EventBus.$emit('exec_external_command', codeText)
            }
          })
          pre.appendChild(execBtn)
        }

        pre.addEventListener('mouseenter', () => {
          const copyBtn = pre.querySelector('.code_copy_btn')
          if (copyBtn) {
            copyBtn.style.opacity = '1'
          }
          const execBtn = pre.querySelector('.code_exec_btn')
          if (execBtn) {
            execBtn.style.opacity = '1'
          }
        })

        pre.addEventListener('mouseleave', () => {
          const copyBtn = pre.querySelector('.code_copy_btn')
          if (copyBtn) {
            copyBtn.style.opacity = '0'
          }
          const execBtn = pre.querySelector('.code_exec_btn')
          if (execBtn) {
            execBtn.style.opacity = '0'
          }
        })
      })
    })
  }

  // 每次渲染后处理代码块
  processCodeBlocks()

  return h('div', {
    class: 'markdown-body',
    innerHTML: renderedContent,
    onMounted: processCodeBlocks
  })
}

const chatListBox = ref(null)
const shouldAutoScroll = ref(true)

const handleScroll = () => {
  if (!chatListBox.value) return
  const element = chatListBox.value
  const isAtBottom = Math.abs(element.scrollHeight - element.scrollTop - element.clientHeight) < 10
  shouldAutoScroll.value = isAtBottom
}

const scrollToBottom = () => {
  if (!shouldAutoScroll.value || !chatListBox.value) return
  nextTick(() => {
    chatListBox.value.scrollTop = chatListBox.value.scrollHeight
  })
}

const editMessage = (content) => {
  question.value = content
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
  .chat_list_dropdown {
    cursor: pointer;
  }
  .model_dropdown {
    cursor: pointer;
  }
  .model_dropdown_link {
    display: flex;
    align-items: center;
    justify-content: center;
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

      .ant-bubble-header {
        width: 100%;
      }
      .ant-bubble-content.ant-bubble-content-filled {
        background-color: transparent!important;
        border: 1px solid v-bind('isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.06)"');
      }
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
          .reasoning_box {
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
          }
          .action_btn {
            position: absolute;
            bottom: 1px;
            visibility: hidden;
            opacity: 0;
            transition: all 0.5s ease;
          }

          &:hover .action_btn {
            visibility: visible;
            opacity: 1;
          }
        }
        .clear_history_divider {
          margin-top: auto;
          .clear_history {
            margin-left: 5px;
            text-align: center;
            color: #887dfd;
            cursor: pointer;
            user-select: none;
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
  max-width: 375px;
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

.code_btn {
  position: absolute;
  top: 5px;
  opacity: 0;
  color: var(--el-color-primary);
  padding: 0 4px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
  font-size: 12px;
  transition: all 0.5s;
  &:hover {
    opacity: 1;
    color: var(--el-color-success);
  }
}

.code_copy_btn {
  right: 35px;
}

.code_exec_btn {
  right: 0px;
}

.markdown-body pre {
  position: relative;
}
</style>
