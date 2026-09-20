import { nextTick, ref } from 'vue'

export const StickyBottomState = Object.freeze({
  PINNED: 'pinned',
  DETACHED: 'detached'
})

export function bottomDistance({ scrollHeight = 0, scrollTop = 0, clientHeight = 0 } = {}) {
  return Math.max(0, scrollHeight - scrollTop - clientHeight)
}

export function isNearBottom(metrics, threshold = 24) {
  return bottomDistance(metrics) <= threshold
}

export function isUpwardScrollKey(event = {}) {
  if (event.metaKey || event.ctrlKey || event.altKey) return false
  return ['ArrowUp', 'PageUp', 'Home',].includes(event.key)
    || (event.key === ' ' && Boolean(event.shiftKey))
}

export function isEditableTarget(target) {
  if (!target) return false
  const tagName = target.tagName?.toLowerCase()
  return tagName === 'input'
    || tagName === 'textarea'
    || tagName === 'select'
    || Boolean(target.isContentEditable)
    || Boolean(target.closest?.('[contenteditable="true"]'))
}

export function nextStickyBottomState(state, event) {
  if (event === 'user-up') return StickyBottomState.DETACHED
  if (event === 'reached-bottom' || event === 'force-bottom') return StickyBottomState.PINNED
  return state
}

export function stickyBottomStatus(
  state,
  metrics,
  { threshold = 24, reattachThreshold = 1 } = {}
) {
  const reachedBottom = isNearBottom(metrics, reattachThreshold)
  const nextState = reachedBottom
    ? nextStickyBottomState(state, 'reached-bottom')
    : state
  return {
    state: nextState,
    reachedBottom,
    isAtBottom: nextState === StickyBottomState.PINNED
      && isNearBottom(metrics, threshold)
  }
}

export function useStickyBottom({
  getScrollElement,
  getContentElement,
  getBottomElement,
  threshold = 24,
  reattachThreshold = 1
}) {
  const isAtBottom = ref(true)
  const isFollowing = ref(true)
  let frameId = null
  let resizeObserver = null
  let intersectionObserver = null
  let fallbackTimer = null
  let touchY = null
  let started = false

  function setState(event) {
    const nextState = nextStickyBottomState(
      isFollowing.value ? StickyBottomState.PINNED : StickyBottomState.DETACHED,
      event
    )
    isFollowing.value = nextState === StickyBottomState.PINNED
  }

  function updateBottomState() {
    const element = getScrollElement()
    if (!element) return false
    const status = stickyBottomStatus(
      isFollowing.value ? StickyBottomState.PINNED : StickyBottomState.DETACHED,
      element,
      { threshold, reattachThreshold }
    )
    isFollowing.value = status.state === StickyBottomState.PINNED
    isAtBottom.value = status.isAtBottom
    return status.reachedBottom
  }

  function cancelScheduledScroll() {
    if (frameId === null) return
    cancelAnimationFrame(frameId)
    frameId = null
  }

  function scheduleBottomScroll() {
    nextTick(() => {
      if (!started || !isFollowing.value || frameId !== null) return
      frameId = requestAnimationFrame(() => {
        frameId = null
        if (!started || !isFollowing.value) return
        const element = getScrollElement()
        if (!element) return
        element.scrollTop = element.scrollHeight
        updateBottomState()
      })
    })
  }

  function detach() {
    setState('user-up')
    isAtBottom.value = false
    cancelScheduledScroll()
  }

  function scrollToBottom() {
    setState('force-bottom')
    isAtBottom.value = true
    scheduleBottomScroll()
  }

  function handleScroll() {
    updateBottomState()
  }

  function handleWheel(event) {
    if (event.deltaY < 0) detach()
  }

  function handleTouchStart(event) {
    touchY = event.touches?.[0]?.clientY ?? null
  }

  function handleTouchMove(event) {
    const nextY = event.touches?.[0]?.clientY
    if (touchY !== null && nextY > touchY) detach()
    touchY = nextY ?? null
  }

  function handleTouchEnd() {
    touchY = null
  }

  function handleKeydown(event) {
    if (!isEditableTarget(event.target) && isUpwardScrollKey(event)) detach()
  }

  function handlePointerDown(event) {
    if (event.target?.closest?.('.el-scrollbar__thumb, .el-scrollbar__bar')) detach()
  }

  function start() {
    if (started) return
    started = true
    nextTick(() => {
      if (!started) return
      const scrollElement = getScrollElement()
      const contentElement = getContentElement()
      const bottomElement = getBottomElement()

      if (typeof ResizeObserver !== 'undefined') {
        resizeObserver = new ResizeObserver(() => {
          if (isFollowing.value) scheduleBottomScroll()
          else updateBottomState()
        })
        if (scrollElement) resizeObserver.observe(scrollElement)
        if (contentElement) resizeObserver.observe(contentElement)
      } else if (scrollElement) {
        let lastScrollHeight = scrollElement.scrollHeight
        let lastClientHeight = scrollElement.clientHeight
        fallbackTimer = window.setInterval(() => {
          if (!started) return
          const element = getScrollElement()
          if (!element) return
          const layoutChanged = element.scrollHeight !== lastScrollHeight
            || element.clientHeight !== lastClientHeight
          lastScrollHeight = element.scrollHeight
          lastClientHeight = element.clientHeight
          if (!layoutChanged) return
          if (isFollowing.value) scheduleBottomScroll()
          else updateBottomState()
        }, 120)
      }

      if (typeof IntersectionObserver !== 'undefined' && scrollElement && bottomElement) {
        intersectionObserver = new IntersectionObserver(() => {
          // Observer callbacks can arrive after user input. Always verify the
          // current metrics before changing the sticky state.
          updateBottomState()
        }, {
          root: scrollElement,
          threshold: 1
        })
        intersectionObserver.observe(bottomElement)
      }

      updateBottomState()
      if (isFollowing.value) scheduleBottomScroll()
    })
  }

  function stop() {
    started = false
    cancelScheduledScroll()
    resizeObserver?.disconnect()
    intersectionObserver?.disconnect()
    if (fallbackTimer !== null) window.clearInterval(fallbackTimer)
    resizeObserver = null
    intersectionObserver = null
    fallbackTimer = null
    touchY = null
  }

  return {
    isAtBottom,
    isFollowing,
    start,
    stop,
    scrollToBottom,
    handleScroll,
    handleWheel,
    handleTouchStart,
    handleTouchMove,
    handleTouchEnd,
    handleKeydown,
    handlePointerDown
  }
}
