/**
 * AI 接口配置
 *
 * 旧的 AI Chat 已下线，会话历史由 agent 的 AgentSessionDB 承担
 * （见 controller/agent-session.js），这里只保留接口配置相关能力。
 */

import { AIConfigDB } from '../utils/db-class.js'
import { deriveBaseURL } from '../ai/provider.js'

const aiConfigDB = new AIConfigDB().getInstance()
const MODEL_DISCOVERY_TIMEOUT_MS = 15 * 1000

async function getAIConfig({ res }) {
  try {
    const config = await aiConfigDB.findOneAsync({})
    if (!config) return res.success({ data: {} })
    res.success({ data: config })
  } catch {
    res.fail({ msg: '获取配置失败' })
  }
}

async function getAIModels({ res, request }) {
  const { apiUrl, apiKey } = request.body
  if (!apiUrl || !apiKey) return res.fail({ msg: 'param error' })

  const baseURL = deriveBaseURL(apiUrl)
  if (!baseURL) return res.fail({ msg: 'invalid Base URL' })

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), MODEL_DISCOVERY_TIMEOUT_MS)
  try {
    const response = await fetch(`${ baseURL }/models`, {
      method: 'GET',
      headers: { authorization: `Bearer ${ apiKey }` },
      signal: controller.signal
    })
    const body = await response.json().catch(() => null)
    if (!response.ok) {
      const message = body?.error?.message || body?.message || `HTTP ${ response.status }`
      return res.fail({ msg: 'get AI models failed', data: { message } })
    }
    if (!Array.isArray(body?.data)) {
      return res.fail({ msg: 'get AI models failed', data: { message: 'invalid models response' } })
    }
    res.success({ data: body.data })
  } catch (error) {
    const message = error?.name === 'AbortError' ? 'request timeout' : error.message
    res.fail({ msg: 'get AI models failed', data: { message } })
  } finally {
    clearTimeout(timeout)
  }
}

async function saveAIConfig({ res, request }) {
  const { body } = request
  if (!body.apiUrl || !body.apiKey || !Array.isArray(body.models) || !body.models.length) {
    return res.fail({ msg: 'param error' })
  }
  try {
    const existConfig = await aiConfigDB.findOneAsync({})
    if (existConfig) {
      await aiConfigDB.updateAsync({ _id: existConfig._id }, body)
    } else {
      await aiConfigDB.insertAsync(body)
    }
    res.success({ msg: 'save success', data: { success: true } })
  } catch {
    res.fail({ msg: 'save AI config failed', data: { success: false } })
  }
}

export {
  getAIConfig,
  saveAIConfig,
  getAIModels
}
