<template>
  <el-dropdown trigger="click" placement="top-start" @command="emit('change', $event)">
    <span class="mode_trigger" :class="[`is_${modelValue}`, { 'is_dark': isDark }]">
      <el-icon><component :is="currentIcon" /></el-icon>
      <span>{{ currentPreset?.label || '审查' }}</span>
      <el-icon class="arrow"><ArrowDown /></el-icon>
    </span>

    <template #dropdown>
      <el-dropdown-menu>
        <el-dropdown-item
          v-for="preset in presets"
          :key="preset.key"
          :command="preset.key"
          :class="{ 'is_active': preset.key === modelValue }"
        >
          <div class="mode_option">
            <el-icon class="option_icon" :class="`is_${preset.key}`">
              <component :is="ICONS[preset.key] || Setting" />
            </el-icon>
            <div class="option_text">
              <div class="option_label">
                {{ preset.label }}
                <el-icon v-if="preset.key === modelValue" class="check"><Check /></el-icon>
              </div>
              <div class="option_desc">{{ preset.desc }}</div>
            </div>
          </div>
        </el-dropdown-item>
      </el-dropdown-menu>
    </template>
  </el-dropdown>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import { View, Lightning, Unlock, ArrowDown, Check, Setting } from '@element-plus/icons-vue'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  modelValue: {
    type: String,
    default: 'review'
  },
  presets: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['change',])

const isDark = computed(() => $store.isDark)

const ICONS = {
  review: View,
  assist: Lightning,
  authorized: Unlock
}

const currentPreset = computed(() => props.presets.find((item) => item.key === props.modelValue))
const currentIcon = computed(() => ICONS[props.modelValue] || Setting)
</script>

<style lang="scss" scoped>
.mode_trigger {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  border-radius: 6px;
  cursor: pointer;
  outline: none;
  font-size: 13px;
  white-space: nowrap;
  transition: background-color 0.2s;

  &:hover {
    background-color: rgba(0, 0, 0, 0.05);
  }

  &.is_dark:hover {
    background-color: rgba(255, 255, 255, 0.08);
  }

  &.is_review { color: #909399; }
  &.is_assist { color: #67c23a; }
  &.is_authorized { color: #e6a23c; }

  .arrow {
    font-size: 12px;
  }
}

.mode_option {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 2px 0;
  min-width: 200px;

  .option_icon {
    margin-top: 3px;

    &.is_review { color: #909399; }
    &.is_assist { color: #67c23a; }
    &.is_authorized { color: #e6a23c; }
  }

  .option_text {
    .option_label {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 13px;
      line-height: 1.5;

      .check {
        color: #409eff;
        font-size: 12px;
      }
    }

    .option_desc {
      color: #909399;
      font-size: 12px;
      line-height: 1.5;
    }
  }
}
</style>
