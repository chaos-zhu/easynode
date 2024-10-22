<template>
  <div class="mobile_float_menu_container">
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
      <li class="key placeholder" />
    </ul>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { virtualKeyType } from '@/utils/enum'

defineProps({
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

const { LONG_PRESS, SINGLE_PRESS } = virtualKeyType
const keys = ref([
  { key: 'Ctrl', ascii: null, type: LONG_PRESS, ansi: '' },
  { key: 'Esc', ascii: 27, type: SINGLE_PRESS, ansi: '\x1B' },
  { key: 'Tab', ascii: 9, type: SINGLE_PRESS, ansi: '\x09' },
  { key: 'Backspace', ascii: 8, type: SINGLE_PRESS, ansi: '\x7F' },
  // { key: 'Delete', ascii: 46, type: SINGLE_PRESS, ansi: '\x1B[3~' },
  { key: '←', ascii: 37, type: SINGLE_PRESS, ansi: '\x1B[D' },
  { key: '↑', ascii: 38, type: SINGLE_PRESS, ansi: '\x1B[A' },
  { key: '↓', ascii: 40, type: SINGLE_PRESS, ansi: '\x1B[B' },
  { key: '→', ascii: 39, type: SINGLE_PRESS, ansi: '\x1B[C' },
  { key: 'Home', ascii: 36, type: SINGLE_PRESS, ansi: '\x1B[H' },
  { key: 'End', ascii: 35, type: SINGLE_PRESS, ansi: '\x1B[F' },
  { key: 'PageUp', ascii: 33, type: SINGLE_PRESS, ansi: '\x1B[5~' },
  { key: 'PageDown', ascii: 34, type: SINGLE_PRESS, ansi: '\x1B[6~' },
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
])

const handleClickKey = (key) => {
  emit('click-key', key)
}

</script>

<style scoped lang="scss">
.mobile_float_menu_container {
  height: 55px;
  padding-top: 5px;
  overflow-y: auto;
  &::-webkit-scrollbar {
    width: 0px;
    height: 0px;
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
      width: 25%;
      height: 25px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      box-sizing: border-box;
      padding: 0 8px;
      // margin-bottom: 6px;
      // border: 1px solid #cccccc5b;
      // border-radius: 2px;
    }
    .long_press {
      .active {
        // color: red;
        font-weight: bolder;
        text-decoration: underline;
      }
    }
  }
}</style>
