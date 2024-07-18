import { defineStore, acceptHMRUpdate } from 'pinia'
import $api from '@/api'
import ping from '@/utils/ping'

const useStore = defineStore({
  id: 'global',
  state: () => ({
    hostList: [],
    groupList: [],
    user: localStorage.getItem('user') || null,
    token: sessionStorage.getItem('token') || localStorage.getItem('token') || null,
    title: ''
  }),
  actions: {
    async setJwtToken(token, isSession = true) {
      if(isSession) sessionStorage.setItem('token', token)
      else localStorage.setItem('token', token)
      this.$patch({ token })
    },
    async setUser(username) {
      localStorage.setItem('user', username)
      this.$patch({ user: username })
    },
    async setTitle(title) {
      this.$patch({ title })
    },
    async clearJwtToken() {
      localStorage.clear('token')
      sessionStorage.clear('token')
      this.$patch({ token: null })
    },
    async getHostList() {
      const { data: groupList } = await $api.getGroupList()
      const { data: hostList } = await $api.getHostList()
      // console.log('hostList:', hostList)
      // console.log('groupList:', groupList)
      this.$patch({ hostList, groupList })
    },
    getHostPing() {
      setTimeout(() => {
        this.hostList.forEach((item) => {
          const { host } = item
          ping(`http://${ host }:${ this.$clientPort }`)
            .then((res) => {
              item.ping = res
            })
        })
        // console.clear()
        // console.warn('Please tick \'Preserve Log\'')
      }, 1500)
    },
    async sortHostList(list) {
      let hostList = list.map(({ host }) => {
        return this.hostList.find(item => item.host === host)
      })
      this.$patch({ hostList })
    }
  }
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useStore, import.meta.hot))
}

export default useStore
