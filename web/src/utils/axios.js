import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '../router'
import useStore from '../store'

axios.defaults.timeout = 30 * 1000
axios.defaults.withCredentials = true
axios.defaults.baseURL = process.env.serviceApiPrefix || '/api/v1'

const instance = axios.create()

instance.interceptors.request.use((config) => {
  config.headers.token = useStore().token
  return config
}, (error) => {
  ElMessage.error({ message: '请求超时！' })
  return Promise.reject(error)
})

instance.interceptors.response.use((response) => {
  if (response.status === 200) return response.data
}, (error) => {
  let { response } = error
  if (error?.message?.includes('timeout')) {
    ElMessage({ message: '请求超时', type: 'error', center: true })
    return Promise.reject(error)
  }
  switch (response?.data?.status) {
    case 401: // token过期
      router.push('login')
      return Promise.reject(error)
    case 403:
      ElMessage({ message: `${ response?.data?.msg || '登录错误' }`, type: 'error', center: true })
      router.push('login')
      return Promise.reject(error)
  }
  switch (response?.status) {
    case 404:
      ElMessage({ message: '404 Not Found', type: 'error', center: true })
      return Promise.reject(error)
  }
  ElMessage({ message: response?.data.msg || error?.message || '网络错误', type: 'error', center: true })
  return Promise.reject(error)
})

export default instance
