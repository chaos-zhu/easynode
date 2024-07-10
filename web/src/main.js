import { createApp } from 'vue'
import { createPinia } from 'pinia'
import useStore from '@store/index'
import router from './router'
import tools from './plugins/tools'
import elementPlugins from './plugins/element'
import globalComponents from './plugins/components'
import api from './api'
import App from './App.vue'
import './assets/scss/reset.scss'
import './assets/scss/global.scss'
import './assets/scss/element-ui.scss'
import './assets/scss/animate.scss'

const app = createApp(App)
elementPlugins(app)
globalComponents(app)
app.use(createPinia())
app.use(router)

app.config.globalProperties.$api = api
app.config.globalProperties.$tools = tools
app.config.globalProperties.$store = useStore()

const serviceURI = import.meta.env.DEV ? process.env.serviceURI : location.origin
app.config.globalProperties.$serviceURI = serviceURI
app.config.globalProperties.$clientPort = process.env.clientPort || 22022
console.warn('ISDEV: ', import.meta.env.DEV)
console.warn('serviceURI: ', serviceURI)

app.mount('#app')
