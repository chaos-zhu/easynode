import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '../router'
import useStore from '../store'

axios.defaults.timeout = 30 * 1000
axios.defaults.withCredentials = true
axios.defaults.baseURL = process.env.serviceApiPrefix || '/api/v1'

const instance = axios.create()
let authGeneration = 0

function handleAuthFailure(error, skipErrorMessage) {
  const store = useStore()
  const requestToken = error.config?.headers?.token || null

  // 重新登录后仍可能收到旧请求的失败响应，不能让旧响应清除新的登录态。
  if (store.token && requestToken !== store.token) return

  // 首个失败响应推进版本号，同一批并发请求及更早的响应会自动失效。
  if (error.config?.authGeneration !== authGeneration) return
  authGeneration += 1

  store.clearLoginInfo()
  if (router.currentRoute.value.path === '/login') return

  if (!skipErrorMessage) {
    ElMessage.closeAll()
    ElMessage({
      message: error.response?.data?.msg || '登录状态已失效，请重新登录',
      type: 'error',
      center: true
    })
  }
  router.replace('/login')
}

instance.interceptors.request.use((config) => {
  config.authGeneration = authGeneration
  config.headers.token = useStore().token
  return config
}, (error) => {
  ElMessage.error({ message: '请求超时！' })
  return Promise.reject(error)
})

instance.interceptors.response.use((response) => {
  return response.data
}, (error) => {
  const { response } = error
  const skipErrorMessage = error.config?.skipErrorMessage
  if (error?.message?.includes('timeout')) {
    if (!skipErrorMessage) ElMessage({ message: '请求超时', type: 'error', center: true })
    return Promise.reject(error)
  }

  if (response?.data?.data?.code === 'IP_ACCESS_DENIED') {
    window.location.reload()
    return Promise.reject(error)
  }

  if ([401, 403,].includes(response?.data?.status)) {
    handleAuthFailure(error, skipErrorMessage)
    return Promise.reject(error)
  }

  switch (response?.status) {
    case 404:
      if (!skipErrorMessage) ElMessage({ message: '404 Not Found', type: 'error', center: true })
      return Promise.reject(error)
  }
  if (!skipErrorMessage) ElMessage({ message: response?.data.msg || error?.message || '网络错误', type: 'error', center: true })
  return Promise.reject(error)
})

export default instance
