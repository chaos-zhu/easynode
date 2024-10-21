<template>
  <div class="mobile_float_menu_container">
    <div
      class="draggable_ball"
      :style="styleObject"
      @touchstart="startDrag"
      @click.stop="handleClick"
    >
      <el-icon><Calendar /></el-icon>
    </div>
    <el-drawer
      v-model="showMenu"
      direction="ttb"
      :with-header="false"
      :close-on-click-modal="false"
      :close-on-press-escape="false"
      :modal="false"
      modal-class="keyboard_drawer"
    >
      <ul class="keyboard">
        <li
          v-for="item in keys"
          :key="item.key"
          :class="['key', { long_press: item.type === LONG_PRESS }]"
          @click="handleClickKey(item)"
        >
          <div :class="{ active: (item.key === 'Ctrl' && longPressCtrl) || (item.key === 'Alt' && longPressAlt) }">
            {{ item.key }}
          </div>
        </li>
        <li class="key placeholder" />
        <li class="key placeholder" />
      </ul>
    </el-drawer>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { Calendar } from '@element-plus/icons-vue'
import { virtualKeyType } from '@/utils/enum'

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  longPressCtrl: {
    type: Boolean,
    default: false
  },
  longPressAlt: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:show', 'click-key',])

let showMenu = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal) })

const { LONG_PRESS, SINGLE_PRESS } = virtualKeyType
const keys = ref([
  { key: 'Ctrl+C', ascii: null, type: SINGLE_PRESS, ansi: '\x03' },
  { key: 'Ctrl+A', ascii: null, type: SINGLE_PRESS, ansi: '\x01' },
  { key: 'Ctrl+E', ascii: null, type: SINGLE_PRESS, ansi: '\x05' },
  { key: 'Ctrl+L', ascii: null, type: SINGLE_PRESS, ansi: '\x0C' },
  { key: 'Ctrl+R', ascii: null, type: SINGLE_PRESS, ansi: '\x12' },
  { key: ':wq', ascii: null, type: SINGLE_PRESS, ansi: ':wq\r' },
  { key: ':q!', ascii: null, type: SINGLE_PRESS, ansi: ':q!\r' },
  { key: 'dd', ascii: null, type: SINGLE_PRESS, ansi: 'dd\r' },
  { key: 'Esc', ascii: 27, type: SINGLE_PRESS, ansi: '\x1B' },
  { key: 'Tab', ascii: 9, type: SINGLE_PRESS, ansi: '\x09' },
  { key: 'Ctrl', ascii: null, type: LONG_PRESS, ansi: '' },
  { key: 'Alt', ascii: null, type: LONG_PRESS, ansi: '' },
  { key: 'F1', ascii: 112, type: SINGLE_PRESS, ansi: '\x1BOP' },
  { key: 'F2', ascii: 113, type: SINGLE_PRESS, ansi: '\x1BOQ' },
  { key: 'F3', ascii: 114, type: SINGLE_PRESS, ansi: '\x1BOR' },
  { key: 'F4', ascii: 115, type: SINGLE_PRESS, ansi: '\x1BOS' },
  { key: 'F5', ascii: 116, type: SINGLE_PRESS, ansi: '\x1B[15~' },
  { key: 'F6', ascii: 117, type: SINGLE_PRESS, ansi: '\x1B[17~' },
  { key: 'F7', ascii: 118, type: SINGLE_PRESS, ansi: '\x1B[18~' },
  { key: 'F8', ascii: 119, type: SINGLE_PRESS, ansi: '\x1B[19~' },
  { key: 'F9', ascii: 120, type: SINGLE_PRESS, ansi: '\x1B[20~' },
  { key: 'F10', ascii: 121, type: SINGLE_PRESS, ansi: '\x1B[21~' },
  { key: 'F11', ascii: 122, type: SINGLE_PRESS, ansi: '\x1B[23~' },
  { key: 'F12', ascii: 123, type: SINGLE_PRESS, ansi: '\x1B[24~' },
  { key: 'Backspace', ascii: 8, type: SINGLE_PRESS, ansi: '\x7F' },
  { key: 'Delete', ascii: 46, type: SINGLE_PRESS, ansi: '\x1B[3~' },
  { key: '↑', ascii: 38, type: SINGLE_PRESS, ansi: '\x1B[A' },
  { key: '→', ascii: 39, type: SINGLE_PRESS, ansi: '\x1B[C' },
  { key: 'Home', ascii: 36, type: SINGLE_PRESS, ansi: '\x1B[H' },
  { key: 'End', ascii: 35, type: SINGLE_PRESS, ansi: '\x1B[F' },
  { key: '↓', ascii: 40, type: SINGLE_PRESS, ansi: '\x1B[B' },
  { key: '←', ascii: 37, type: SINGLE_PRESS, ansi: '\x1B[D' },
  { key: 'PageUp', ascii: 33, type: SINGLE_PRESS, ansi: '\x1B[5~' },
  { key: 'PageDown', ascii: 34, type: SINGLE_PRESS, ansi: '\x1B[6~' },
])

const handleClickKey = (key) => {
  emit('click-key', key)
}

const handleClick = () => {
  showMenu.value = !showMenu.value
  // if (!dragging || (Math.abs(initialX - x.value) < 10 && Math.abs(initialY - y.value) < 10)) {
  // }
}

const radius = 20 // 悬浮球的半径
const x = ref(window.innerWidth - radius * 2) // 初始化位置在屏幕右下角
const y = ref(window.innerHeight - radius * 2)

const styleObject = ref({
  position: 'fixed',
  top: `${ y.value }px`,
  left: `${ x.value }px`,
  cursor: 'grab',
  userSelect: 'none',
  width: `${ radius * 2 }px`, // 悬浮球的直径
  height: `${ radius * 2 }px`,
  borderRadius: '50%',
  backgroundColor: '#42b983',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  color: 'white',
  fontSize: '14px',
  zIndex: '1000'
})

let startX = 0
let startY = 0
let dragging = false
let initialX = 0 // 初始化点击位置X
let initialY = 0 // 初始化点击位置Y

const startDrag = (event) => {
  const touchEvent = event.type.includes('touch') ? event.touches[0] : event
  dragging = true
  initialX = touchEvent.clientX
  initialY = touchEvent.clientY
  startX = touchEvent.clientX - x.value
  startY = touchEvent.clientY - y.value
  if (event.type.includes('touch')) {
    document.addEventListener('touchmove', onDragging)
    document.addEventListener('touchend', stopDrag)
  } else {
    document.addEventListener('mousemove', onDragging)
    document.addEventListener('mouseup', stopDrag)
  }
  // event.preventDefault()
}

const onDragging = (event) => {
  if (dragging) {
    const moveEvent = event.type.includes('touch') ? event.touches[0] : event
    let newX = moveEvent.clientX - startX
    let newY = moveEvent.clientY - startY

    // 边界检查以保持悬浮球至少露出一半
    newX = Math.max(newX, -radius) // 允许悬浮球露出一半
    newX = Math.min(newX, window.innerWidth - radius) // 确保右侧至少露出一半
    newY = Math.max(newY, -radius) // 允许悬浮球露出一半
    newY = Math.min(newY, window.innerHeight - radius) // 确保底部至少露出一半

    x.value = newX
    y.value = newY
    styleObject.value.top = `${ y.value }px`
    styleObject.value.left = `${ x.value }px`
  }
}

const stopDrag = (event) => {
  dragging = false
  if (event.type.includes('touch')) {
    document.removeEventListener('touchmove', onDragging)
    document.removeEventListener('touchend', stopDrag)
  } else {
    document.removeEventListener('mousemove', onDragging)
    document.removeEventListener('mouseup', stopDrag)
  }
}

// 确保组件在初始加载时位于右下角
onMounted(() => {
  x.value = window.innerWidth - radius * 2
  y.value = window.innerHeight - radius * 2
  styleObject.value.top = `${ y.value }px`
  styleObject.value.left = `${ x.value }px`

  window.addEventListener('resize', () => {
    x.value = window.innerWidth - radius * 2
    y.value = window.innerHeight - radius * 2
    styleObject.value.top = `${ y.value }px`
    styleObject.value.left = `${ x.value }px`
  })
})
</script>

<style lang="scss">
.mobile_float_menu_container {
  .draggable_ball {
    transition: background-color 0.3s;
    &:active,
    &:touch-active {
      background-color: #333;
      cursor: grabbing;
    }
  }

  .keyboard_drawer {
    height: 150px;
    .el-drawer {
      height: 100%!important;
      .el-drawer__header {
        margin-bottom: 10px;
      }
      .el-drawer__body {
        padding: 10px 15px;
      }
    }
    .keyboard {
      list-style: none;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-around;
      padding: 0;
      .key.placeholder {
        opacity: 0;
      }
      .key {
        width: 76px;
        min-height: 15px;
        font-size: 12px;
        box-sizing: border-box;
        padding: 8px;
        text-align: center;
        margin-right: 8px;
        margin-bottom: 6px;
        border: 1px solid #ccc;
      }
      .long_press {
        .active {
          // color: red;
          font-weight: bolder;
          text-decoration: underline;
        }
      }
    }
  }
}

</style>
