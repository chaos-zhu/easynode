import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '../router'
import useStore from '../store'
import i18n from '@/i18n'

axios.defaults.timeout = 30 * 1000
axios.defaults.withCredentials = true
axios.defaults.baseURL = process.env.serviceApiPrefix || '/api/v1'

const instance = axios.create()
const { t } = i18n.global

instance.interceptors.request.use((config) => {
  config.headers.token = useStore().token
  config.headers['Accept-Language'] = i18n.global.locale.value
  return config
}, (error) => {
  ElMessage.error({ message: t('topBar.requestTimeout') })
  return Promise.reject(error)
})

instance.interceptors.response.use((response) => {
  if (response.status === 200) return response.data
}, (error) => {
  let { response } = error
  if (error?.message?.includes('timeout')) {
    ElMessage({ message: t('topBar.requestTimeout'), type: 'error', center: true })
    return Promise.reject(error)
  }
  switch (response?.data?.status) {
    case 401: // token过期
      router.push('login')
      return Promise.reject(error)
    case 403:
      ElMessage({ message: `${ response?.data?.msg || t('login.loginFailed') }`, type: 'error', center: true })
      router.push('login')
      return Promise.reject(error)
  }
  switch (response?.status) {
    case 404:
      ElMessage({ message: t('common.notFound'), type: 'error', center: true })
      return Promise.reject(error)
  }
  ElMessage({ message: response?.data.msg || error?.message || t('common.networkError'), type: 'error', center: true })
  return Promise.reject(error)
})

export default instance
