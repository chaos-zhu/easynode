<template>
  <div class="ai_entry_host">
    <div
      ref="entryRef"
      class="entry_button"
      :class="{ 'is_dragging': dragging }"
      :style="entryStyle"
      role="button"
      tabindex="0"
      aria-label="打开 AI 助手"
      @pointerdown="handlePointerDown"
      @pointermove="handlePointerMove"
      @pointerup="handlePointerUp"
      @pointercancel="handlePointerCancel"
      @keydown.enter.prevent="visible = true"
      @keydown.space.prevent="visible = true"
    >
      <img src="@/assets/image/coding32.png" alt="">
      <span>AI 助手</span>
    </div>

    <AiAgent v-model:show="visible" />
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import AiAgent from '@/components/ai-agent/index.vue'

const POSITION_KEY = 'aiEntryPosition'
const EDGE_GAP = 12
const DEFAULT_GAP = 24
const DRAG_THRESHOLD = 5

const visible = ref(false)
const entryRef = ref(null)
const dragging = ref(false)
const position = reactive({ x: 0, y: 0 })
let pointerState = null

const entryStyle = computed(() => ({
  left: `${ position.x }px`,
  top: `${ position.y }px`
}))

function entrySize() {
  return {
    width: entryRef.value?.offsetWidth || 108,
    height: entryRef.value?.offsetHeight || 40
  }
}

function clampPosition(x, y) {
  const { width, height } = entrySize()
  return {
    x: Math.min(Math.max(EDGE_GAP, x), Math.max(EDGE_GAP, window.innerWidth - width - EDGE_GAP)),
    y: Math.min(Math.max(EDGE_GAP, y), Math.max(EDGE_GAP, window.innerHeight - height - EDGE_GAP))
  }
}

function setPosition(x, y) {
  const nextPosition = clampPosition(x, y)
  position.x = Math.round(nextPosition.x)
  position.y = Math.round(nextPosition.y)
}

function savePosition() {
  localStorage.setItem(POSITION_KEY, JSON.stringify({ x: position.x, y: position.y }))
}

function restorePosition() {
  try {
    const saved = JSON.parse(localStorage.getItem(POSITION_KEY) || 'null')
    if (Number.isFinite(saved?.x) && Number.isFinite(saved?.y)) {
      setPosition(saved.x, saved.y)
      return
    }
  } catch (error) {
    console.warn('读取 AI 助手悬浮位置失败:', error.message)
  }
  const { width, height } = entrySize()
  setPosition(window.innerWidth - width - DEFAULT_GAP, window.innerHeight - height - DEFAULT_GAP)
}

function handlePointerDown(event) {
  if (event.button !== 0) return
  entryRef.value?.setPointerCapture(event.pointerId)
  pointerState = {
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    originX: position.x,
    originY: position.y
  }
}

function handlePointerMove(event) {
  if (!pointerState || pointerState.pointerId !== event.pointerId) return
  const deltaX = event.clientX - pointerState.startX
  const deltaY = event.clientY - pointerState.startY
  if (!dragging.value && Math.hypot(deltaX, deltaY) >= DRAG_THRESHOLD) dragging.value = true
  if (dragging.value) setPosition(pointerState.originX + deltaX, pointerState.originY + deltaY)
}

function finishPointer(event, cancelled = false) {
  if (!pointerState || pointerState.pointerId !== event.pointerId) return
  if (entryRef.value?.hasPointerCapture(event.pointerId)) entryRef.value.releasePointerCapture(event.pointerId)
  if (dragging.value) savePosition()
  else if (!cancelled) visible.value = true
  dragging.value = false
  pointerState = null
}

function handlePointerUp(event) {
  finishPointer(event)
}

function handlePointerCancel(event) {
  finishPointer(event, true)
}

function handleViewportResize() {
  setPosition(position.x, position.y)
  savePosition()
}

onMounted(() => {
  nextTick(restorePosition)
  window.addEventListener('resize', handleViewportResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleViewportResize)
})
</script>

<style scoped lang="scss">
.entry_button {
  position: fixed;
  z-index: 1800;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 0 14px;
  border-radius: 20px;
  background: #887dfd;
  box-shadow: 0 6px 18px rgba(73, 62, 185, 0.3);
  color: #fff;
  font-size: 14px;
  cursor: grab;
  touch-action: none;
  user-select: none;
  transition: filter 0.2s, box-shadow 0.2s;

  &:hover,
  &:focus-visible {
    outline: none;
    filter: brightness(1.08);
    box-shadow: 0 8px 22px rgba(73, 62, 185, 0.4);
  }

  &.is_dragging {
    cursor: grabbing;
    transition: none;
  }

  img {
    width: 18px;
    height: 18px;
    border-radius: 10%;
    pointer-events: none;
  }
}
</style>
