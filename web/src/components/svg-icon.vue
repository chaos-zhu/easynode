<template>
  <svg class="icon" aria-hidden="true">
    <title v-if="title">{{ title }}</title>
    <use :xlink:href="href" />
  </svg>
</template>
<script>
export default {
  name: 'IconSvg',
  props: {
    name: {
      required: true,
      type: String,
      default: ''
    },
    title: {
      required: false,
      type: String,
      default: ''
    }
  },
  computed: {
    href() {
      return `#${ this.name }`
    }
  }
}
</script>
<style lang="scss" scoped>
.icon {
  // width: 16px;
  // height: 16px;
  width: 1em;
  height: 1em;
  vertical-align: -0.15em;
  fill: currentColor;
  overflow: hidden;
}
</style>
