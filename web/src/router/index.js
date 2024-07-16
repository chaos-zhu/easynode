import { createRouter, createWebHistory } from 'vue-router'

// import hostList from '@views/list/index.vue'
// import login from '@views/login/index.vue'
// import terminal from '@views/terminal/index.vue'
// import test from '@views/test/index.vue'

const hostList = () => import('@views/list/index.vue')
const login = () => import('@views/login/index.vue')
const terminal = () => import('@views/terminal/index.vue')

const routes = [
  { path: '/', component: hostList },
  { path: '/login', component: login },
  { path: '/terminal', component: terminal },
  // { path: '/test', component: test },
]

export default createRouter({
  history: createWebHistory(),
  routes
})
