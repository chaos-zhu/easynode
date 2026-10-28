<template>
  <span class="model_select">
    <span class="model_measure" aria-hidden="true">{{ modelValue || '选择模型' }}</span>
    <el-select
      :model-value="modelValue"
      :filterable="filterable"
      size="small"
      placeholder="选择模型"
      @update:model-value="emit('update:modelValue', $event)"
    >
      <el-option
        v-for="model in models"
        :key="model"
        :label="model"
        :value="model"
      />
    </el-select>
  </span>
</template>

<script setup>
defineProps({
  modelValue: { type: String, default: '' },
  models: { type: Array, default: () => [] },
  filterable: { type: Boolean, default: false }
})

const emit = defineEmits(['update:modelValue',])
</script>

<style lang="scss" scoped>
.model_select {
  position: relative;
  display: inline-block;
  flex: 0 1 auto;
  width: max-content;
  min-width: min(110px, 100%);
  max-width: min(220px, 100%);
  height: 24px;
  vertical-align: middle;

  .model_measure {
    display: block;
    visibility: hidden;
    white-space: nowrap;
    padding: 0 20px;
    font-size: 12px;
    line-height: 24px;
  }

  .el-select {
    position: absolute;
    inset: 0;
    width: 100%;
  }
}
</style>
