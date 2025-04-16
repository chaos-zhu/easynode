export class AIChatService {
  constructor(baseUrl, apiKey) {
    this.baseUrl = baseUrl
    this.apiKey = apiKey
    this.controller = null
    this.reasoningStartTime = null // 添加推理开始时间记录
    this.isThinking = false
  }

  async startChat(messages, model, options = {}, callbacks) {
    this.closeConnection()

    this.controller = new AbortController()

    // 默认参数
    const defaultOptions = {
      stream: true,
      temperature: 0.5,
      top_p: 1,
      max_tokens: 4000,
      presence_penalty: 0,
      frequency_penalty: 0
    }

    // 合并参数，确保必传参数存在
    const requestBody = {
      ...defaultOptions,
      ...options,
      messages,
      model,
      stream: true // 强制使用流式传输
    }

    try {
      const response = await fetch(this.baseUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${ this.apiKey }`
        },
        body: JSON.stringify(requestBody),
        signal: this.controller.signal
      })

      if (!response.ok) {
        // 获取详细的错误信息
        let errorMessage = `HTTP error! status: ${ response.status }`
        try {
          const errorData = await response.json()
          errorMessage = errorData.error?.message || errorMessage
        } catch (e) {
          // 如果无法解析错误响应，使用默认错误信息
        }

        if (callbacks.onError) {
          callbacks.onError(errorMessage)
        }
        return // 提前返回，不继续处理
      }

      if (callbacks.onOpen) {
        callbacks.onOpen()
      }

      const reader = response.body.getReader()
      const decoder = new TextDecoder()

      while (true) {
        const { done, value } = await reader.read()

        if (done) {
          break
        }

        const chunk = decoder.decode(value)
        const lines = chunk.split('\n').filter(line => line.trim() !== '')

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const jsonStr = line.slice(6) // 移除 "data: " 前缀
            if (jsonStr === '[DONE]') {
              if (callbacks.onComplete) {
                callbacks.onComplete()
              }
              continue
            }

            try {
              const data = JSON.parse(jsonStr)
              if (callbacks.onMessage && data.choices?.[0]?.delta?.content) {
                const { content } = data.choices[0].delta
                if (content.includes('</think>')) {
                  // 推理结束
                  this.isThinking = false
                  callbacks.onReasoning(content.replace('</think>', ''))
                  if (this.reasoningStartTime) {
                    const reasoningTime = Date.now() - this.reasoningStartTime
                    if (callbacks.onReasoningComplete) {
                      callbacks.onReasoningComplete(reasoningTime)
                    }
                    this.reasoningStartTime = null // 重置开始时间
                  }
                } else if (content.includes('<think>') || this.isThinking) {
                  // 记录推理开始时间
                  this.isThinking = true
                  if (!this.reasoningStartTime) {
                    this.reasoningStartTime = Date.now()
                  }
                  callbacks.onReasoning(content.replace('<think>', ''))
                } else {
                  // 非推理模型对话
                  callbacks.onMessage(content)
                }
              }
              // ====== deepseek r1 推理返回的字段为 reasoning_content
              if (callbacks.onReasoning && data.choices?.[0]?.delta?.reasoning_content) {
                // 记录推理开始时间
                if (!this.reasoningStartTime) {
                  this.reasoningStartTime = Date.now()
                }
                callbacks.onReasoning(data.choices[0].delta.reasoning_content)
              }
              // 在推理结束时计算耗时[判断reasoning_content是否为null]
              if (this.reasoningStartTime && data.choices?.[0]?.delta?.reasoning_content === null) {
                const reasoningTime = Date.now() - this.reasoningStartTime
                if (callbacks.onReasoningComplete) {
                  callbacks.onReasoningComplete(reasoningTime)
                }
                this.reasoningStartTime = null // 重置开始时间
              }
              // ======
            } catch (error) {
              console.error('解析消息失败:', error)
              if (callbacks.onError) {
                callbacks.onError(error)
              }
            }
          }
        }
      }
    } catch (error) {
      console.error('连接错误:', error.message)
      if (error.message === 'BodyStreamBuffer was aborted') {
        callbacks.onMessage('用户取消请求')
        this.closeConnection()
        return
      }
      if (callbacks.onError) {
        callbacks.onError(error)
      }
    }
  }

  async generateTitle(messages, model, options = {}) {
    if (!messages || messages.length === 0) {
      return '闲聊'
    }

    const titleMessages = JSON.parse(JSON.stringify(messages)).splice(1) // 移除打招呼的内容
    titleMessages.push({
      role: 'user',
      content: '使用四到五个字直接返回这句话的简要主题，不要解释、不要标点、不要语气词、不要多余文本，不要加粗，如果没有主题，请直接返回"闲聊"'
    })

    const defaultOptions = {
      stream: false,
      temperature: 0.5,
      top_p: 1,
      max_tokens: 4000,
      presence_penalty: 0,
      frequency_penalty: 0
    }

    // 合并参数
    const requestBody = {
      ...defaultOptions,
      ...options,
      messages: titleMessages,
      model
    }

    try {
      const response = await fetch(this.baseUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${ this.apiKey }`
        },
        body: JSON.stringify(requestBody)
      })

      if (!response.ok) {
        let errorMessage = `HTTP error! status: ${ response.status }`
        try {
          const errorData = await response.json()
          errorMessage = errorData.error?.message || errorMessage
        } catch (e) {
          // 如果无法解析错误响应，使用默认错误信息
        }
        console.error('生成标题失败:', errorMessage)
        return '闲聊'
      }

      const data = await response.json()
      if (data.choices && data.choices[0] && data.choices[0].message) {
        return data.choices[0].message.content.trim() || '闲聊'
      }
      return '闲聊'
    } catch (error) {
      console.error('生成标题错误:', error)
      return '闲聊'
    }
  }

  closeConnection() {
    if (this.controller) {
      this.controller.abort()
      this.controller = null
    }
  }
}