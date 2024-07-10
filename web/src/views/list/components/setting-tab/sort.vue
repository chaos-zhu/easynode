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
  <div style="display: flex; justify-content: center;margin-top: 25px">
    <el-button type="primary" @click="handleUpdateSort">
      保存
    </el-button>
  </div>
</template>

<script>
export default {
  name: 'HostSort',
  emits: ['update-list',],
  data() {
    return {
      targetIndex: 0,
      list: []
    }
  },
  created() {
    this.list = this.$store.hostList.map(({ name, host }) => ({ name, host }))
  },
  methods: {
    dragstart(index) {
      // console.log('拖动目标：', index)
      this.targetIndex = index
    },
    dragenter(e, curIndex) {
      e.preventDefault()
      if (this.targetIndex !== curIndex) {
        // console.log('拖动进入：', curIndex)
        let target = this.list.splice(this.targetIndex, 1)[0]
        this.list.splice(curIndex, 0, target)
        this.targetIndex = curIndex // 每次拖动排序后重置目标元素下标
      }
    },
    dragover(e) {
      e.preventDefault()
    },
    handleUpdateSort() {
      let { list } = this
      this.$api.updateHostSort({ list })
        .then(({ msg }) => {
          this.$message({ type: 'success', center: true, message: msg })
          this.$store.sortHostList(this.list)
        })
    }
  }
}
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
  // width: 300px;
  padding: 0 20px;
  margin: 0 auto;
  // background: #c8c8c8;
  border-radius: 4px;
  color: #000;
  margin-bottom: 6px;
  height: 35px;
  line-height: 35px;
  &:hover {
    box-shadow: var(--el-box-shadow
);
  }
}
.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
