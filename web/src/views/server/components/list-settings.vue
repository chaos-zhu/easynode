<template>
  <el-dialog
    v-model="visible"
    title="列表设置"
    width="500px"
    append-to-body
    @close="handleClose"
  >
    <el-tabs v-model="activeTab">
      <!-- 表头设置 Tab -->
      <el-tab-pane label="表头设置" name="columns">
        <div class="column_settings">
          <div v-for="(item, key) in columnConfig" :key="key" class="column_item">
            <el-checkbox
              v-model="localColumnSettings[key]"
              :disabled="item.disabled"
            >
              {{ item.label }}
            </el-checkbox>
          </div>
        </div>
        <div class="tab_footer" />
      </el-tab-pane>

      <!-- 展现形式 Tab -->
      <el-tab-pane label="展现形式" name="display">
        <div class="display_settings">
          <div class="display_mode_cards">
            <div
              class="display_mode_card"
              :class="{ active: localDisplayMode === 'group' }"
              @click="localDisplayMode = 'group'"
            >
              <div class="card_content">
                <div class="card_title">分组展示</div>
                <div class="card_description">按照分组折叠展示主机列表</div>
              </div>
              <div class="card_check">
                <el-icon v-if="localDisplayMode === 'group'" class="check_icon">
                  <CircleCheckFilled />
                </el-icon>
              </div>
            </div>

            <div
              class="display_mode_card"
              :class="{ active: localDisplayMode === 'list' }"
              @click="localDisplayMode = 'list'"
            >
              <div class="card_content">
                <div class="card_title">列表展示</div>
                <div class="card_description">在一个列表中展示所有主机</div>
              </div>
              <div class="card_check">
                <el-icon v-if="localDisplayMode === 'list'" class="check_icon">
                  <CircleCheckFilled />
                </el-icon>
              </div>
            </div>
          </div>
        </div>
      </el-tab-pane>
    </el-tabs>

    <template #footer>
      <div class="dialog_footer">
        <el-button @click="handleClose">取消</el-button>
        <el-button type="primary" @click="handleConfirm">确定</el-button>
      </div>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { CircleCheckFilled } from '@element-plus/icons-vue'

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  columnConfig: {
    type: Object,
    required: true
  },
  columnSettings: {
    type: Object,
    required: true
  },
  displayMode: {
    type: String,
    default: 'group'
  }
})

const emit = defineEmits(['update:show', 'confirm',])

const visible = computed({
  get: () => props.show,
  set: (val) => emit('update:show', val)
})

const activeTab = ref('columns')
const localColumnSettings = ref({ ...props.columnSettings })
const localDisplayMode = ref(props.displayMode)

// 监听props变化，更新本地状态
watch(() => props.columnSettings, (newVal) => {
  localColumnSettings.value = { ...newVal }
}, { deep: true })

watch(() => props.displayMode, (newVal) => {
  localDisplayMode.value = newVal
})

// 重置弹窗状态
watch(() => props.show, (newVal) => {
  if (newVal) {
    localColumnSettings.value = { ...props.columnSettings }
    localDisplayMode.value = props.displayMode
    activeTab.value = 'columns'
  }
})

// 关闭弹窗
const handleClose = () => {
  visible.value = false
}

// 确认设置
const handleConfirm = () => {
  emit('confirm', {
    columnSettings: localColumnSettings.value,
    displayMode: localDisplayMode.value
  })
  visible.value = false
}
</script>

<style lang="scss" scoped>
.column_settings {
  padding: 10px 0;
  max-height: 400px;
  overflow-y: auto;
  display: flex;
  flex-wrap: wrap;
  gap: 12px 20px;

  .column_item {
    flex: 0 0 auto;
    min-width: fit-content;
  }
}

.tab_footer {
  margin-top: 20px;
  padding-top: 20px;
  border-top: 1px solid var(--el-border-color-lighter);
}

.display_settings {
  padding: 20px 0;

  .display_mode_cards {
    display: flex;
    flex-direction: column;
    gap: 12px;

    .display_mode_card {
      display: flex;
      align-items: center;
      padding: 16px 20px;
      border: 2px solid var(--el-border-color);
      border-radius: 6px;
      background-color: var(--el-fill-color-blank);
      cursor: pointer;

      &:hover {
        border-color: var(--el-color-primary-light-5);
      }

      &.active {
        border-color: var(--el-color-primary);
        background-color: var(--el-color-primary-light-9);

        .card_icon {
          color: var(--el-color-primary);
        }

        .card_title {
          color: var(--el-color-primary);
        }
      }

      .card_icon {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-right: 16px;
        color: var(--el-text-color-secondary);
      }

      .card_content {
        flex: 1;

        .card_title {
          font-size: 15px;
          font-weight: 500;
          color: var(--el-text-color-primary);
          margin-bottom: 4px;
        }

        .card_description {
          font-size: 13px;
          color: var(--el-text-color-secondary);
        }
      }

      .card_check {
        flex-shrink: 0;
        margin-left: 12px;

        .check_icon {
          font-size: 22px;
          color: var(--el-color-primary);
        }
      }
    }
  }
}

.dialog_footer {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
}
</style>

