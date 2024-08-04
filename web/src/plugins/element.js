import { ElMessage, ElMessageBox, ElNotification } from 'element-plus'
import 'element-plus/es/components/message/style/css'
import 'element-plus/es/components/message-box/style/css'
import 'element-plus/es/components/notification/style/css'

// 如果使用 unplugin-element-plus 并且只使用组件 API，需要手动导入样式
// https://element-plus.org/zh-CN/guide/quickstart.html#%E6%89%8B%E5%8A%A8%E5%AF%BC%E5%85%A5
export default (app) => {
  app.config.globalProperties.$ELEMENT = { size: 'small' }
  app.config.globalProperties.$message = ElMessage
  app.config.globalProperties.$messageBox = ElMessageBox
  app.config.globalProperties.$notification = ElNotification
}
