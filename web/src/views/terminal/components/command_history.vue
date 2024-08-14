<template>
  <div class="command_history_container">
    <ul>
      <li
        v-for="item in list"
        :key="item"
      >
        {{ item }}
      </li>
    </ul>
  </div>
</template>
<script setup>

import { ref } from 'vue'

defineProps({
  list: {
    required: true,
    type: Array
  }
})

</script>

<style lang="scss" scoped>
.command_history_container {

}
</style>