<template>
  <el-tooltip
    effect="dark"
    :show-after="showAfter"
    :hide-after="0"
    :content="content"
    placement="bottom"
  >
    <slot />
  </el-tooltip>
</template>

<script>
export default {
  name: 'Tooltip',
  props: {
    showAfter: {
      required: false,
      type: Number,
      default: 1000
    },
    content: {
      required: true,
      type: String
    }
  },
  data() {
    return {
    }
  }
}
</script>

<style lang="scss" scoped>

</style>
