<template>
  <transition-group
    name="list"
    mode="out-in"
    tag="ul"
    class="host-list"
  >
    <li
      v-for="(item, index) in list"
      :key="item.host"
      :draggable="true"
      class="host-item"
      @dragenter="dragenter($event, index)"
      @dragover="dragover($event)"
      @dragstart="dragstart(index)"
    >
      <span>{{ item.host }}</span>
      ---
      <span>{{ item.name }}</span>
    </li>
  </transition-group>
  <div style="display: flex; justify-content: center; margin-top: 25px">
    <el-button type="primary" @click="handleUpdateSort">
      保存
    </el-button>
  </div>
</template>

<script setup>
import { ref, onMounted, getCurrentInstance } from 'vue'

const emit = defineEmits(['update-list'])
const { proxy: { $api, $message, $store } } = getCurrentInstance()

const targetIndex = ref(0)
const list = ref([])

const dragstart = (index) => {
  targetIndex.value = index
}

const dragenter = (e, curIndex) => {
  e.preventDefault()
  if (targetIndex.value !== curIndex) {
    let target = list.value.splice(targetIndex.value, 1)[0]
    list.value.splice(curIndex, 0, target)
    targetIndex.value = curIndex
  }
}

const dragover = (e) => {
  e.preventDefault()
}

const handleUpdateSort = () => {
  $api.updateHostSort({ list: list.value })
    .then(({ msg }) => {
      $message({ type: 'success', center: true, message: msg })
      $store.sortHostList(list.value)
      emit('update-list', list.value) // 触发自定义事件
    })
}

onMounted(() => {
  list.value = $store.hostList.map(({ name, host }) => ({ name, host }))
})
</script>

<style lang="scss" scoped>
.drag-move {
  transition: transform .3s;
}
.host-list {
  padding-top: 10px;
  padding-right: 50px;
}
.host-item {
  transition: all .3s;
  box-shadow: var(--el-box-shadow-lighter);
  cursor: move;
  font-size: 12px;
  color: #595959;
  padding: 0 20px;
  margin: 0 auto;
  border-radius: 4px;
  color: #000;
  margin-bottom: 6px;
  height: 35px;
  line-height: 35px;
  &:hover {
    box-shadow: var(--el-box-shadow);
  }
}
.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
