import { defineStore, acceptHMRUpdate } from 'pinia'
import $api from '@/api'
import ping from '@/utils/ping'

const useStore = defineStore({
  id: 'global',
  state: () => ({
    hostList: [],
    token: sessionStorage.getItem('token') || localStorage.getItem('token') || null
  }),
  actions: {
    async setJwtToken(token, isSession = true) {
      if(isSession) sessionStorage.setItem('token', token)
      else localStorage.setItem('token', token)
      this.$patch({ token })
    },
    async clearJwtToken() {
      localStorage.clear('token')
      sessionStorage.clear('token')
      this.$patch({ token: null })
    },
    async getHostList() {
      const { data: hostList } = await $api.getHostList()
      this.$patch({ hostList })
      // console.log('pinia: ', this.hostList)
      // this.getHostPing()
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
