import { ref, onUnmounted, computed, watch } from 'vue'
import { AIChatService } from '@/utils/aiChatService'
import { ElMessage } from 'element-plus'
import useStore from '@/store'
import $api from '@/api'
import { randomStr } from '@/utils'

// const titlePrompt = '使用四到五个字直接返回这句话的简要主题，不要解释、不要标点、不要语气词、不要多余文本，不要加粗，如果没有主题，请直接返回“闲聊”'

const defaultChatList = () => {
  return [{
    id: 1,
    content: '您好，我是小助手，有什么可以帮您的吗？',
    role: 'assistant',
    timestamp: new Date(),
    isStreaming: false,
    error: false
  },]
}

const defaultCurChat = () => {
  return {
    id: '',
    describe: '新对话',
    chatList: defaultChatList()
  }
}

export function useAIChat() {
  const $store = useStore()
  const aiService = ref(null)
  const curChat = ref(defaultCurChat())

  const chatId = computed(() => curChat.value.id)
  const chatList = computed(() => curChat.value.chatList)
  const aiConfig = computed(() => $store.aiConfig)
  const titleGenMedel = computed(() => aiConfig.value.titleGenMedel)
  const chatHistory = computed(() => $store.chatHistory)

  watch(() => aiConfig.value, (newConfig) => {
    if (newConfig && typeof newConfig === 'object') {
      const { apiUrl, apiKey } = newConfig
      if (apiUrl && apiKey) {
        aiService.value = new AIChatService(apiUrl, apiKey)
        console.log('aiService created:', apiUrl)
      }
    }
  }, { immediate: true, deep: true })

  const isConnecting = ref(false)
  const loading = ref(false)
  const error = ref(null)
  const isReasoning = ref(false)

  const sendMessage = async (messageContent, model, options = {}) => {
    if (!aiService.value) {
      error.value = '请先配置API参数'
      ElMessage.error(error.value)
      return
    }

    error.value = null
    loading.value = true
    isConnecting.value = true
    isReasoning.value = false

    const userMessage = {
      id: Date.now(),
      content: messageContent,
      role: 'user',
      timestamp: new Date()
    }
    chatList.value.push(userMessage)

    const aiMessageId = Date.now() + 1 // 确保AI消息ID与用户消息ID不会重复
    const aiMessage = {
      id: aiMessageId,
      content: '',
      reasoning: '',
      reasoningTime: 0,
      role: 'assistant',
      timestamp: new Date(),
      isStreaming: true
    }
    chatList.value.push(aiMessage)

    const apiMessages = chatList.value
      .slice(1) // 排除第一条消息
      .slice(0, -1) // 排除最后一条空的AI消息
      .filter(msg => msg.role === 'user' || msg.role === 'assistant')
      .map(msg => ({
        role: msg.role,
        content: msg.content
      }))

    try {
      await aiService.value.startChat(
        apiMessages,
        model,
        options,
        {
          onOpen: () => {
            isConnecting.value = false
          },
          onMessage: (content) => {
            const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
            if (aiMessage) {
              aiMessage.content += content
            }
          },
          onReasoning: (reasoning) => {
            isReasoning.value = true
            const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
            if (aiMessage) {
              aiMessage.reasoning += reasoning
            }
          },
          onReasoningComplete: (reasoningTime) => {
            isReasoning.value = false
            const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
            if (aiMessage) {
              aiMessage.reasoningTime = reasoningTime
            }
          },
          onError: (err) => {
            error.value = err?.message || err || '连接到 AI 服务时出错'
            loading.value = false
            const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
            if (aiMessage) {
              aiMessage.error = true
              aiMessage.isStreaming = false
              aiMessage.content = error.value // 将错误信息设置为消息内容
            }
          }
        }
      )

      loading.value = false
      isConnecting.value = false
      isReasoning.value = false
      const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
      if (aiMessage) {
        aiMessage.isStreaming = false
      }
      saveChat() // 保存对话

    } catch (err) {
      error.value = err?.message || err || '发送消息时出错'
      loading.value = false
      isConnecting.value = false
      isReasoning.value = false
      const aiMessage = chatList.value.find(msg => msg.id === aiMessageId)
      if (aiMessage) {
        aiMessage.error = true
        aiMessage.isStreaming = false
        aiMessage.content = error.value // 将错误信息设置为消息内容
      }
    }
  }

  const clearChat = async () => {
    if (loading.value) return
    chatList.value.length = 1
    error.value = null
    await saveChat() // 保存清空后的状态
    ElMessage.success('清除成功')
  }

  const stopGeneration = () => {
    aiService.value?.closeConnection()
    loading.value = false

    const streamingMessage = chatList.value.find(msg => msg.isStreaming)
    if (streamingMessage) {
      streamingMessage.isStreaming = false
    }
  }

  const deleteMessage = (messageId) => {
    if (loading.value) return
    const index = chatList.value.findIndex(msg => msg.id === messageId)
    if (index !== -1) {
      chatList.value.splice(index, Infinity)
      saveChat() // 保存删除后的状态
    }
  }

  const regenerateMessage = async (messageId, model) => {
    if (loading.value) return
    const index = chatList.value.findIndex(msg => msg.id === messageId)
    if (index === -1) return
    chatList.value.splice(index + 1, Infinity) // 删除当前消息的后续消息
    const lastMessage = chatList.value[index]
    const { content, role } = lastMessage
    if (role === 'user') {
      chatList.value.pop()
      await sendMessage(content, model)
    } else if (role === 'assistant') {
      chatList.value.pop()
      const lastUserMessage = chatList.value.pop()
      await sendMessage(lastUserMessage.content, model)
    }
  }

  const addChat = async () => {
    curChat.value = defaultCurChat()
  }

  const removeChat = async (id) => {
    await $api.removeChatHistory(id)
    ElMessage.success('删除成功')
    await $store.getChatHistory()
    if (chatHistory.value.length > 0) {
      changeChat(chatHistory.value[0].id)
    } else {
      addChat()
    }
  }

  const changeChat = (id) => {
    const chatItem = chatHistory.value.find(item => item.id === id)
    if (!chatItem) return ElMessage.error('对话id不存在')
    curChat.value = chatItem
  }

  const saveChat = async () => {
    if (curChat.value.chatList.length === 3) {
      const title = await aiService.value.generateTitle(curChat.value.chatList, titleGenMedel.value)
      curChat.value.describe = title
    }
    const { data } = await $api.saveChatHistory(curChat.value)
    if (!data.updateChat) ElMessage.error('对话保存失败')
    else {
      curChat.value.id = data.updateChat.id
      curChat.value.createdAt = data.updateChat.createdAt
      curChat.value.updatedAt = data.updateChat.updatedAt
      // curChat.value = {
      //   id: data.updateChat._id,
      //   ...data.updateChat
      // }
    }
    $store.getChatHistory()
  }

  onUnmounted(() => {
    aiService.value?.closeConnection()
  })

  return {
    chatId,
    chatList,
    isConnecting,
    isReasoning,
    loading,
    error,
    sendMessage,
    clearChat,
    stopGeneration,
    deleteMessage,
    regenerateMessage,
    changeChat,
    removeChat,
    addChat
  }
}
