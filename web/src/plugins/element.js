import { ElMessage, ElMessageBox, ElNotification } from 'element-plus'

export default (app) => {
  app.config.globalProperties.$ELEMENT = { size: 'default' }
  app.config.globalProperties.$message = ElMessage
  app.config.globalProperties.$messageBox = ElMessageBox
  app.config.globalProperties.$notification = ElNotification
}
