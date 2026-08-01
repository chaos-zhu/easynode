<template>
  <div class="ai_entry_host">
    <div
      v-show="enabled"
      ref="entryRef"
      class="entry_button"
      :class="{
        'is_dragging': dragging,
        'is_resizing': resizing,
        'is_running': agentStatus.running,
        'has_error': agentStatus.connectError
      }"
      :style="entryStyle"
      role="button"
      tabindex="0"
      :aria-label="visible ? '关闭 AI 助手' : '打开 AI 助手'"
      @pointerdown="handlePointerDown"
      @pointermove="handlePointerMove"
      @pointerup="handlePointerUp"
      @pointercancel="handlePointerCancel"
      @pointerenter="handlePointerEnter"
      @pointerleave="handlePointerLeave"
      @keydown.enter.prevent="visible = !visible"
      @keydown.space.prevent="visible = !visible"
    >
      <AiPet class="pet_sprite" :state="petState" :hovered="hovering" />
      <button
        ref="resizeHandleRef"
        class="pet_resize_handle"
        type="button"
        aria-label="调整宠物大小"
        title="调整宠物大小"
        @pointerdown.stop.prevent="startResize"
        @pointermove.stop.prevent="handleResizeMove"
        @pointerup.stop.prevent="finishResize"
        @pointercancel.stop.prevent="finishResize"
        @click.stop.prevent
        @keydown.left.stop.prevent="resizeBy(8)"
        @keydown.up.stop.prevent="resizeBy(-8)"
        @keydown.right.stop.prevent="resizeBy(-8)"
        @keydown.down.stop.prevent="resizeBy(8)"
      >
        <svg viewBox="0 0 14 14" aria-hidden="true">
          <path d="M3 11L11 3M7 3H11V7M7 11H3V7" />
        </svg>
      </button>
    </div>

    <AiAgent v-model:show="visible" @status-change="handleStatusChange" />
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import AiAgent from '@/components/ai-agent/index.vue'
import AiPet from '@/components/ai-pet.vue'

const props = defineProps({
  enabled: { type: Boolean, default: true }
})

const POSITION_KEY = 'aiEntryPosition'
const SIZE_KEY = 'aiEntrySize'
const EDGE_GAP = 12
const DEFAULT_GAP = 24
const DESKTOP_DEFAULT_BOTTOM_GAP = 88
const MOBILE_BREAKPOINT = 968
const DRAG_THRESHOLD = 5
const DEFAULT_SIZE = 56
const MIN_SIZE = 48
const MAX_SIZE = 160
const IDLE_MIN_DELAY = 6000
const IDLE_MAX_DELAY = 12000
const IDLE_EXPRESSION_DURATION = 800
const HAPPY_DURATION = 2000

const visible = ref(false)
const entryRef = ref(null)
const resizeHandleRef = ref(null)
const dragging = ref(false)
const resizing = ref(false)
const hovering = ref(false)
const idleExpression = ref(false)
const happyExpression = ref(false)
const dragPetState = ref('')
const size = ref(DEFAULT_SIZE)
const position = reactive({ x: 0, y: 0 })
const agentStatus = reactive({ running: false, connectError: '', completionId: 0 })
let pointerState = null
let resizeState = null
let idleTimer = null
let idleExpressionTimer = null
let happyTimer = null

const entryStyle = computed(() => ({
  left: `${ position.x }px`,
  top: `${ position.y }px`,
  width: `${ size.value }px`,
  height: `${ size.value }px`
}))

const petState = computed(() => {
  if (dragging.value && dragPetState.value) return dragPetState.value
  if (happyExpression.value) return 'happy'
  if (agentStatus.running) return 'working'
  if (idleExpression.value) return 'idle'
  return 'normal'
})

function clearIdleTimers() {
  window.clearTimeout(idleTimer)
  window.clearTimeout(idleExpressionTimer)
  idleTimer = null
  idleExpressionTimer = null
}

function canShowIdleExpression() {
  return props.enabled && !document.hidden && !agentStatus.running && !happyExpression.value && !dragging.value && !resizing.value && !hovering.value
}

function scheduleIdleExpression() {
  clearIdleTimers()
  idleExpression.value = false
  if (!canShowIdleExpression()) return
  const delay = IDLE_MIN_DELAY + Math.random() * (IDLE_MAX_DELAY - IDLE_MIN_DELAY)
  idleTimer = window.setTimeout(() => {
    if (!canShowIdleExpression()) {
      scheduleIdleExpression()
      return
    }
    idleExpression.value = true
    idleExpressionTimer = window.setTimeout(() => {
      idleExpression.value = false
      scheduleIdleExpression()
    }, IDLE_EXPRESSION_DURATION)
  }, delay)
}

function showHappyExpression() {
  window.clearTimeout(happyTimer)
  clearIdleTimers()
  idleExpression.value = false
  if (!props.enabled) return
  happyExpression.value = true
  happyTimer = window.setTimeout(() => {
    happyExpression.value = false
    scheduleIdleExpression()
  }, HAPPY_DURATION)
}

function entrySize() {
  return {
    width: entryRef.value?.offsetWidth || size.value,
    height: entryRef.value?.offsetHeight || size.value
  }
}

function clampSize(value) {
  const viewportMax = Math.min(MAX_SIZE, window.innerWidth - EDGE_GAP * 2, window.innerHeight - EDGE_GAP * 2)
  return Math.round(Math.min(Math.max(MIN_SIZE, value), Math.max(MIN_SIZE, viewportMax)))
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

function saveSize() {
  localStorage.setItem(SIZE_KEY, String(size.value))
}

function restoreSize() {
  const savedSize = Number(localStorage.getItem(SIZE_KEY))
  size.value = clampSize(Number.isFinite(savedSize) && savedSize > 0 ? savedSize : DEFAULT_SIZE)
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
  const { height } = entrySize()
  const bottomGap = window.innerWidth > MOBILE_BREAKPOINT ? DESKTOP_DEFAULT_BOTTOM_GAP : DEFAULT_GAP
  setPosition(DEFAULT_GAP, window.innerHeight - height - bottomGap)
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
  if (!dragging.value && Math.hypot(deltaX, deltaY) >= DRAG_THRESHOLD) {
    dragPetState.value = petState.value
    dragging.value = true
  }
  if (dragging.value) setPosition(pointerState.originX + deltaX, pointerState.originY + deltaY)
}

function finishPointer(event, cancelled = false) {
  if (!pointerState || pointerState.pointerId !== event.pointerId) return
  if (entryRef.value?.hasPointerCapture(event.pointerId)) entryRef.value.releasePointerCapture(event.pointerId)
  if (dragging.value) savePosition()
  else if (!cancelled) visible.value = !visible.value
  dragging.value = false
  dragPetState.value = ''
  pointerState = null
}

function handlePointerUp(event) {
  finishPointer(event)
}

function handlePointerCancel(event) {
  finishPointer(event, true)
}

function startResize(event) {
  if (event.button !== 0) return
  resizeHandleRef.value?.setPointerCapture(event.pointerId)
  clearIdleTimers()
  resizing.value = true
  resizeState = {
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    startSize: size.value,
    originX: position.x,
    originY: position.y
  }
}

function handleResizeMove(event) {
  if (!resizeState || resizeState.pointerId !== event.pointerId) return
  const delta = ((resizeState.startX - event.clientX) + (event.clientY - resizeState.startY)) / 2
  const nextSize = clampSize(resizeState.startSize + delta)
  const nextX = resizeState.originX + resizeState.startSize - nextSize
  size.value = nextSize
  setPosition(nextX, resizeState.originY)
}

function finishResize(event) {
  if (!resizeState || resizeState.pointerId !== event.pointerId) return
  if (resizeHandleRef.value?.hasPointerCapture(event.pointerId)) resizeHandleRef.value.releasePointerCapture(event.pointerId)
  resizing.value = false
  resizeState = null
  saveSize()
  savePosition()
  scheduleIdleExpression()
}

function resizeBy(delta) {
  const previousSize = size.value
  size.value = clampSize(previousSize + delta)
  setPosition(position.x + previousSize - size.value, position.y)
  saveSize()
  savePosition()
}

function handlePointerEnter() {
  hovering.value = true
  clearIdleTimers()
  idleExpression.value = false
}

function handlePointerLeave() {
  hovering.value = false
  scheduleIdleExpression()
}

function handleViewportResize() {
  size.value = clampSize(size.value)
  setPosition(position.x, position.y)
  saveSize()
  savePosition()
}

function handleStatusChange(status = {}) {
  const completionId = Number(status.completionId) || 0
  const completed = completionId > agentStatus.completionId
  agentStatus.running = Boolean(status.running)
  agentStatus.connectError = status.connectError || ''
  agentStatus.completionId = completionId
  if (agentStatus.running) {
    window.clearTimeout(happyTimer)
    happyExpression.value = false
    clearIdleTimers()
    idleExpression.value = false
  } else if (completed) {
    showHappyExpression()
  } else {
    scheduleIdleExpression()
  }
}

function handleVisibilityChange() {
  if (document.hidden) {
    clearIdleTimers()
    window.clearTimeout(happyTimer)
    idleExpression.value = false
    happyExpression.value = false
  } else {
    scheduleIdleExpression()
  }
}

watch(() => props.enabled, (enabled) => {
  if (!enabled) {
    visible.value = false
    clearIdleTimers()
    window.clearTimeout(happyTimer)
    idleExpression.value = false
    happyExpression.value = false
  } else {
    scheduleIdleExpression()
  }
})

watch(dragging, (isDragging) => {
  if (isDragging) {
    clearIdleTimers()
  } else {
    scheduleIdleExpression()
  }
})

watch(visible, (show) => {
  if (show && !props.enabled) visible.value = false
})

onMounted(() => {
  nextTick(() => {
    restoreSize()
    restorePosition()
    scheduleIdleExpression()
  })
  window.addEventListener('resize', handleViewportResize)
  document.addEventListener('visibilitychange', handleVisibilityChange)
})

onBeforeUnmount(() => {
  clearIdleTimers()
  window.clearTimeout(happyTimer)
  window.removeEventListener('resize', handleViewportResize)
  document.removeEventListener('visibilitychange', handleVisibilityChange)
})
</script>

<style scoped lang="scss">
.entry_button {
  position: fixed;
  z-index: 1800;
  width: 56px;
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: 0;
  border-radius: 50%;
  background: transparent;
  cursor: default;
  touch-action: none;
  user-select: none;
  transition: filter 0.2s, transform 0.2s;

  &:hover,
  &:focus-visible {
    outline: none;
    filter: brightness(1.05);

    .pet_sprite {
      animation: ai_pet_hover 0.68s cubic-bezier(0.2, 0.75, 0.3, 1);
    }
  }

  &:focus-visible {
    outline: 2px solid var(--el-color-primary);
    outline-offset: 3px;
  }

  &.is_dragging {
    cursor: grabbing;
    transition: none;

    .pet_sprite {
      animation: none;
    }
  }

  &.is_resizing {
    .pet_sprite {
      animation: none;
    }

    .pet_resize_handle {
      opacity: 1;
      transform: scale(1);
    }
  }

  &.is_running::before {
    position: absolute;
    z-index: -1;
    inset: 4px;
    border-radius: 50%;
    background: rgba(117, 108, 245, 0.34);
    content: '';
    animation: ai_pet_pulse 1.4s ease-out infinite;
  }

  &.has_error::after {
    position: absolute;
    top: 2px;
    right: 2px;
    width: 10px;
    height: 10px;
    box-sizing: border-box;
    border: 2px solid var(--el-bg-color);
    border-radius: 50%;
    background: var(--el-color-danger);
    content: '';
  }

  .pet_sprite {
    width: 100%;
    height: 100%;
    filter: drop-shadow(0 7px 8px rgba(31, 40, 111, 0.25));
    pointer-events: none;
    animation: ai_pet_idle 3.8s ease-in-out infinite;
  }

  &:hover .pet_resize_handle,
  .pet_resize_handle:focus-visible {
    opacity: 1;
    transform: scale(1);
  }
}

.pet_resize_handle {
  position: absolute;
  left: -3px;
  bottom: -3px;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: 1px solid rgba(255, 255, 255, 0.24);
  border-radius: 7px;
  background: rgba(30, 32, 40, 0.88);
  box-shadow: 0 3px 9px rgba(0, 0, 0, 0.28);
  color: #fff;
  cursor: nesw-resize;
  opacity: 0;
  outline: none;
  transform: scale(0.82);
  transition: opacity 0.16s ease, transform 0.16s ease;
  touch-action: none;

  svg {
    width: 13px;
    height: 13px;
    fill: none;
    stroke: currentColor;
    stroke-linecap: square;
    stroke-linejoin: miter;
    stroke-width: 1.6;
  }
}

@keyframes ai_pet_idle {
  0%, 100% { transform: translateY(0) scale(1); }
  50% { transform: translateY(-2px) scale(1.015); }
}

@keyframes ai_pet_hover {
  0% { transform: translateY(0) rotate(0) scale(1); }
  28% { transform: translateY(-8px) rotate(-4deg) scale(1.04); }
  58% { transform: translateY(-6px) rotate(3deg) scale(1.025); }
  82% { transform: translateY(1px) rotate(-1deg) scaleX(1.035) scaleY(0.965); }
  100% { transform: translateY(0) rotate(0) scale(1); }
}

@keyframes ai_pet_pulse {
  0% { opacity: 0.65; transform: scale(0.85); }
  100% { opacity: 0; transform: scale(1.35); }
}

@media (prefers-reduced-motion: reduce) {
  .entry_button,
  .entry_button .pet_sprite,
  .entry_button::before {
    animation: none !important;
    transition: none !important;
  }
}
</style>
