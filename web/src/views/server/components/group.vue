<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :top="isMobile() ? '45px' : '15vh'"
    :append-to-body="false"
    title="实例分组管理"
    :close-on-click-modal="false"
  >
    <Group />
  </el-dialog>
</template>

<script setup>
import { computed } from 'vue'
import Group from '@/views/group/index.vue'
import { isMobile } from '@/utils'

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show',])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

</script>

