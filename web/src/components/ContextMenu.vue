<template>
  <teleport to="body">
    <!-- 遮罩层，用于点击外部关闭菜单 -->
    <div
      v-if="visible"
      class="context_menu_overlay"
      @click="closeMenu"
      @contextmenu.prevent="closeMenu"
    />

    <!-- 主菜单 -->
    <div
      v-if="visible"
      ref="contextMenuRef"
      class="custom_context_menu"
      :style="menuStyle"
      @contextmenu.prevent
    >
      <div class="context_menu_content">
        <template v-for="(item, index) in menuItems" :key="index">
          <!-- 有子菜单的项 -->
          <div
            v-if="item.children && item.children.length > 0"
            :ref="el => setMenuItemRef(el, index)"
            class="context_menu_item has_children"
            :class="{ disabled: item.disabled }"
            @mouseenter="handleSubMenuHover(index, $event)"
            @mouseleave="handleSubMenuLeave"
            @click="!item.disabled && handleItemClick(item)"
          >
            <span class="menu_label">{{ item.label }}</span>
            <el-icon class="sub_menu_arrow">
              <ArrowRight />
            </el-icon>
          </div>

          <!-- 普通菜单项 -->
          <div
            v-else
            class="context_menu_item"
            :class="{ disabled: item.disabled }"
            @click="!item.disabled && handleItemClick(item)"
          >
            <span class="menu_label">{{ item.label }}</span>
          </div>
        </template>
      </div>
    </div>

    <!-- 子菜单 -->
    <div
      v-if="visible && activeSubMenuIndex >= 0"
      ref="subMenuRef"
      class="custom_context_menu context_submenu"
      :style="subMenuStyle"
      @contextmenu.prevent
      @mouseenter="keepSubMenuOpen = true"
      @mouseleave="handleSubMenuLeave"
    >
      <div class="context_menu_content">
        <div
          v-for="(child, childIndex) in currentSubMenuItems"
          :key="childIndex"
          class="context_menu_item"
          :class="{ disabled: child.disabled }"
          @click="!child.disabled && handleItemClick(child)"
        >
          <span class="menu_label">{{ child.label }}</span>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount } from 'vue'
import { ArrowRight } from '@element-plus/icons-vue'

const visible = ref(false)
const menuItems = ref([])
const position = ref({ x: 0, y: 0 })
const contextMenuRef = ref(null)
const subMenuRef = ref(null)
const activeSubMenuIndex = ref(-1)
const subMenuPosition = ref({ x: 0, y: 0 })
const keepSubMenuOpen = ref(false)
const menuItemRefs = ref({})
let subMenuTimer = null

const menuStyle = computed(() => ({
  position: 'fixed',
  left: `${ position.value.x }px`,
  top: `${ position.value.y }px`,
  zIndex: 9999
}))

const subMenuStyle = computed(() => ({
  position: 'fixed',
  left: `${ subMenuPosition.value.x }px`,
  top: `${ subMenuPosition.value.y }px`,
  zIndex: 10000
}))

const currentSubMenuItems = computed(() => {
  if (activeSubMenuIndex.value >= 0 && menuItems.value[activeSubMenuIndex.value]) {
    return menuItems.value[activeSubMenuIndex.value].children || []
  }
  return []
})

const setMenuItemRef = (el, index) => {
  if (el) {
    menuItemRefs.value[index] = el
  } else {
    delete menuItemRefs.value[index]
  }
}

const showMenu = async (event, items) => {
  if (!items || items.length === 0) return

  menuItems.value = items
  position.value = { x: event.x, y: event.y }
  visible.value = true
  activeSubMenuIndex.value = -1
  keepSubMenuOpen.value = false

  await nextTick()
  adjustPosition()
}

const closeMenu = () => {
  visible.value = false
  menuItems.value = []
  activeSubMenuIndex.value = -1
  keepSubMenuOpen.value = false
  menuItemRefs.value = {}
  clearTimeout(subMenuTimer)
}

const handleItemClick = (item) => {
  if (item.onClick && typeof item.onClick === 'function') {
    item.onClick()
  }
  closeMenu()
}

const handleSubMenuHover = async (index, event) => {
  if (activeSubMenuIndex.value === index) return

  clearTimeout(subMenuTimer)
  keepSubMenuOpen.value = true
  activeSubMenuIndex.value = index

  await nextTick()

  // 计算子菜单位置
  calculateSubMenuPosition(index)
}

const calculateSubMenuPosition = (index) => {
  const parentMenu = contextMenuRef.value
  const menuItem = menuItemRefs.value[index]

  if (!parentMenu || !menuItem) {
    console.warn('无法获取菜单元素引用')
    return
  }

  const parentRect = parentMenu.getBoundingClientRect()
  const itemRect = menuItem.getBoundingClientRect()
  const viewportWidth = window.innerWidth
  const viewportHeight = window.innerHeight

  // 默认在右侧显示
  let x = parentRect.right + 2
  let y = itemRect.top

  // 等待子菜单渲染后再进行边界检测
  nextTick(() => {
    if (subMenuRef.value) {
      const subMenuRect = subMenuRef.value.getBoundingClientRect()

      // 水平边界检测
      if (x + subMenuRect.width > viewportWidth) {
        // 如果右侧空间不够，在左侧显示
        x = parentRect.left - subMenuRect.width - 2
      }

      // 确保不会超出左边界
      if (x < 0) {
        x = 10
      }

      // 垂直边界检测
      if (y + subMenuRect.height > viewportHeight) {
        y = viewportHeight - subMenuRect.height - 10
      }
      if (y < 0) {
        y = 10
      }

      subMenuPosition.value = { x, y }
    }
  })

  // 先设置初始位置
  subMenuPosition.value = { x, y }
}

const handleSubMenuLeave = () => {
  keepSubMenuOpen.value = false
  subMenuTimer = setTimeout(() => {
    if (!keepSubMenuOpen.value) {
      activeSubMenuIndex.value = -1
    }
  }, 150)
}

// 调整主菜单位置，防止超出屏幕边界
const adjustPosition = () => {
  if (!contextMenuRef.value) return

  const menu = contextMenuRef.value
  const menuRect = menu.getBoundingClientRect()
  const viewportWidth = window.innerWidth
  const viewportHeight = window.innerHeight

  let { x, y } = position.value

  // 防止水平超出
  if (x + menuRect.width > viewportWidth) {
    x = viewportWidth - menuRect.width - 10
  }
  if (x < 0) x = 10

  // 防止垂直超出
  if (y + menuRect.height > viewportHeight) {
    y = viewportHeight - menuRect.height - 10
  }
  if (y < 0) y = 10

  position.value = { x, y }
}

// 监听键盘事件
const handleKeydown = (event) => {
  if (event.key === 'Escape' && visible.value) {
    closeMenu()
  }
}

onMounted(() => {
  document.addEventListener('keydown', handleKeydown)
})

onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleKeydown)
  clearTimeout(subMenuTimer)
})

defineExpose({
  showMenu,
  closeMenu
})
</script>

<style lang="scss" scoped>
.custom_context_menu {
  .context_menu_content {
    min-width: 160px;
    border: 1px solid var(--el-border-color);
    border-radius: 6px;
    box-shadow: var(--el-box-shadow-light);
    background: var(--el-bg-color);
    padding: 4px 0;
    user-select: none;

    .context_menu_item {
      position: relative;
      height: 32px;
      line-height: 32px;
      padding: 0 16px;
      font-size: 13px;
      color: var(--el-text-color-regular);
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: space-between;

      &:hover:not(.disabled) {
        background-color: var(--el-color-primary-light-9);
        color: var(--el-color-primary);
      }

      &.disabled {
        color: var(--el-text-color-disabled);
        cursor: not-allowed;
      }

      &.has_children {
        .sub_menu_arrow {
          font-size: 12px;
          transition: transform 0.2s;
        }
      }

      .menu_label {
        flex: 1;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    }
  }
}

.context_submenu {
  .context_menu_content {
    border: 1px solid var(--el-border-color);
    border-radius: 6px;
    box-shadow: var(--el-box-shadow-light);
    background: var(--el-bg-color);

    .context_menu_item {
      &:hover:not(.disabled) {
        background-color: var(--el-color-primary-light-9);
        color: var(--el-color-primary);
      }
    }
  }
}

.context_menu_overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 9998;
  background: transparent;
}
</style>