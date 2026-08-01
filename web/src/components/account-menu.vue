<template>
  <el-dropdown
    class="account_dropdown"
    trigger="click"
    :placement="placement"
    popper-class="account_menu_popper"
  >
    <el-badge is-dot :hidden="!isNew" class="account_badge">
      <div class="account_trigger" :class="{ 'is_collapsed': collapsed }">
        <el-tooltip v-if="collapsed" :content="user || '用户'" placement="right">
          <el-icon class="user_icon"><User /></el-icon>
        </el-tooltip>
        <span v-else class="username" :title="user">{{ user || '用户' }}</span>
        <span
          v-if="!collapsed"
          class="plus_entry"
          title="Plus 激活"
          @click.stop="gotoPlusPage"
        >
          <img
            class="plus_icon"
            src="@/assets/plus.png"
            alt="PLUS"
            :style="{ filter: isPlusActive ? 'grayscale(0%)' : 'grayscale(100%)' }"
          >
          <img
            v-if="!isPlusActive && discount"
            class="discount_badge"
            src="@/assets/discount.png"
            alt="Discount"
          >
        </span>
      </div>
    </el-badge>

    <template #dropdown>
      <el-dropdown-menu>
        <el-dropdown-item @click="emit('open-version')">
          <div class="account_menu_item">
            <span>版本更新</span>
            <el-badge is-dot :hidden="!isNew" class="version_badge">
              <el-icon><Refresh /></el-icon>
            </el-badge>
          </div>
        </el-dropdown-item>
        <el-dropdown-item @click="toggleTheme">
          <div class="account_menu_item">
            <span>主题切换</span>
            <el-icon><Sunny v-if="isDark" /><Moon v-else /></el-icon>
          </div>
        </el-dropdown-item>
        <el-dropdown-item :disabled="savingAIPreferences || !$store.aiConfigLoaded" @click="toggleAIEntry">
          <div class="account_menu_item">
            <span>{{ aiEntryEnabled ? '隐藏 AI 助手' : '显示 AI 助手' }}</span>
            <el-icon>
              <Loading v-if="savingAIPreferences" class="is-loading" />
              <Hide v-else-if="aiEntryEnabled" />
              <View v-else />
            </el-icon>
          </div>
        </el-dropdown-item>
        <el-dropdown-item v-if="showCollapse" @click="$store.setMenuCollapse()">
          <div class="account_menu_item">
            <span>{{ collapsed ? '展开侧栏' : '收起侧栏' }}</span>
            <el-icon><Expand v-if="collapsed" /><Fold v-else /></el-icon>
          </div>
        </el-dropdown-item>
        <el-dropdown-item divided @click="handleLogout">
          <div class="account_menu_item danger_item">
            <span>退出登录</span>
            <el-icon><SwitchButton /></el-icon>
          </div>
        </el-dropdown-item>
      </el-dropdown-menu>
    </template>
  </el-dropdown>
</template>

<script setup>
import { computed, getCurrentInstance, ref } from 'vue'
import { Expand, Fold, Hide, Loading, Moon, Refresh, Sunny, SwitchButton, User, View } from '@element-plus/icons-vue'

defineProps({
  collapsed: { type: Boolean, default: false },
  discount: { type: [Boolean, Number, String,], default: false },
  isNew: { type: Boolean, default: false },
  placement: { type: String, default: 'right-end' },
  showCollapse: { type: Boolean, default: true }
})

const emit = defineEmits(['open-version',])
const { proxy: { $router, $store, $message } } = getCurrentInstance()

const user = computed(() => $store.user)
const isDark = computed(() => $store.isDark)
const isPlusActive = computed(() => $store.isPlusActive)
const aiEntryEnabled = computed(() => $store.aiConfig.ui?.petEnabled !== false)
const savingAIPreferences = ref(false)

function toggleTheme() {
  $store.setTheme(!isDark.value)
}

function gotoPlusPage() {
  $router.push('/setting?tabKey=plus')
}

async function toggleAIEntry() {
  if (savingAIPreferences.value) return
  savingAIPreferences.value = true
  try {
    await $store.setAIPreferences({ petEnabled: !aiEntryEnabled.value })
  } catch (error) {
    $message.error(error.message || '保存 AI 助手显示设置失败')
  } finally {
    savingAIPreferences.value = false
  }
}

async function handleLogout() {
  try {
    await $store.removeLoginInfo(true)
  } finally {
    $message({ type: 'success', message: '已安全退出', center: true })
    $router.push('/login')
  }
}
</script>

<style lang="scss" scoped>
.account_dropdown {
  width: 100%;
  display: block;
}

.account_badge {
  display: block;
  width: 100%;
}

.account_trigger {
  min-height: 44px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  border-radius: 8px;
  cursor: pointer;
  color: var(--el-text-color-primary);

  &:hover {
    background-color: var(--el-fill-color-light);
  }

  &.is_collapsed {
    width: 44px;
    justify-content: center;
    padding: 8px;
  }

  .username {
    min-width: 0;
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 14px;
  }

  .user_icon {
    font-size: 18px;
  }

  .plus_entry {
    position: relative;
    display: flex;
    align-items: center;
    flex-shrink: 0;
  }

  .plus_icon {
    width: 34px;
  }

  .discount_badge {
    position: absolute;
    width: 19px;
    right: -10px;
    top: -9px;
    transform: rotate(18deg);
  }
}
</style>

<style lang="scss">
.account_menu_popper {
  min-width: 190px;

  .account_menu_item {
    width: 150px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .version_badge {
    height: 16px;
  }

  .danger_item {
    color: var(--el-color-danger);
  }
}
</style>
