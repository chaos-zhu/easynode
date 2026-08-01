/**
 * 模型 provider 适配
 *
 * 复用现有 AIConfigDB 里的配置（apiUrl / apiKey / models），不改动既有
 * 保存逻辑，只新增一个可选的 providerType 字段：
 *   缺省 openai-compatible —— 覆盖 DeepSeek / 通义 / 硅基流动 / OpenRouter
 *   等绝大多数第三方端点，也兼容 OpenAI 本身
 *
 * ⚠️ 并非所有模型都支持 tool calling。用户自填的小模型如果不支持，
 * agent 会静默退化成普通对话 —— 所以 probeToolSupport 要在开会话前跑一次。
 */

import { createOpenAICompatible } from '@ai-sdk/openai-compatible'
import { createAnthropic } from '@ai-sdk/anthropic'
import { createGoogleGenerativeAI } from '@ai-sdk/google'
import { AIConfigDB } from '../utils/db-class.js'

const aiConfigDB = new AIConfigDB().getInstance()

// 控制单次 agent turn 的最大模型/工具循环次数。该值只能由面板设置保存，
// 不能信任 WebSocket 请求中的任意数字。
export const DEFAULT_MAX_STEPS = 25
export const MAX_MAX_STEPS = 50

export function normalizeMaxSteps(value) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 1) return DEFAULT_MAX_STEPS
  return Math.min(parsed, MAX_MAX_STEPS)
}

export const ProviderType = {
  OPENAI_COMPATIBLE: 'openai-compatible',
  ANTHROPIC: 'anthropic',
  GOOGLE: 'google'
}

/**
 * 配置项保存的是 Provider 的 Base URL（API 前缀），AI SDK 会自行追加
 * 各 Provider 的请求路径。为兼容旧配置，也接受过去填写的完整端点。
 */
export function deriveBaseURL(apiUrl, providerType = ProviderType.OPENAI_COMPATIBLE) {
  if (!apiUrl || typeof apiUrl !== 'string') return ''
  let url = apiUrl.trim().replace(/\/+$/, '')

  if (providerType === ProviderType.ANTHROPIC) {
    return url.replace(/\/messages$/i, '')
  }

  if (providerType === ProviderType.GOOGLE) {
    return url.replace(/\/models\/[^/]+:generateContent$/i, '')
  }

  url = url.replace(/\/chat\/completions$/i, '')
  url = url.replace(/\/completions$/i, '')
  return url
}

export async function loadAIConfig() {
  const config = await aiConfigDB.findOneAsync({})
  if (!config) throw new Error('尚未配置 AI 接口，请先在 AI 设置中填写 Base URL 与 API Key')
  if (!config.apiUrl || !config.apiKey) throw new Error('AI 配置不完整：缺少 Base URL 或 API Key')
  return config
}

/**
 * 构造模型实例
 * @param {object} [options]
 * @param {string} [options.modelId] 指定模型，缺省用配置里的第一个
 * @returns {Promise<{ model: object, modelId: string, providerType: string, maxSteps: number }>}
 */
export async function resolveModel(options = {}) {
  const config = await loadAIConfig()
  const providerType = config.providerType || ProviderType.OPENAI_COMPATIBLE
  const models = Array.isArray(config.models) ? config.models : []
  const modelId = options.modelId || models[0]

  if (!modelId) throw new Error('未指定模型，且 AI 配置中没有可用的模型列表')
  if (models.length && !models.includes(modelId)) {
    throw new Error(`模型 ${ modelId } 不在已配置的模型列表中`)
  }

  const baseURL = deriveBaseURL(config.apiUrl, providerType)
  // 第三方模型的上下文窗口无从探测，允许用户在配置里指定；缺省交给
  // compaction.js 的保守默认值
  const contextLimit = Number(config.contextLimit) > 0 ? Number(config.contextLimit) : undefined
  const maxSteps = normalizeMaxSteps(config.maxSteps)

  switch (providerType) {
    case ProviderType.ANTHROPIC: {
      const anthropic = createAnthropic({ apiKey: config.apiKey, baseURL: baseURL || undefined })
      return { model: anthropic(modelId), modelId, providerType, contextLimit, maxSteps }
    }
    case ProviderType.GOOGLE: {
      const google = createGoogleGenerativeAI({ apiKey: config.apiKey, baseURL: baseURL || undefined })
      return { model: google(modelId), modelId, providerType, contextLimit, maxSteps }
    }
    default: {
      const openai = createOpenAICompatible({
        name: 'easynode-ai',
        apiKey: config.apiKey,
        baseURL: baseURL || 'https://api.openai.com/v1'
      })
      return { model: openai(modelId), modelId, providerType, contextLimit, maxSteps }
    }
  }
}

/** 可用模型列表，供前端选择 */
export async function listConfiguredModels() {
  const config = await aiConfigDB.findOneAsync({})
  const models = Array.isArray(config?.models) ? config.models : []
  return { models, defaultModel: models[0] || '', providerType: config?.providerType || ProviderType.OPENAI_COMPATIBLE }
}
