import {
  StickyBottomState,
  bottomDistance,
  isEditableTarget,
  isNearBottom,
  isUpwardScrollKey,
  nextStickyBottomState,
  stickyBottomStatus
} from '../src/composables/useStickyBottom.js'

let passed = 0
let failed = 0
const failures = []

function expect(label, actual, wanted) {
  if (JSON.stringify(actual) === JSON.stringify(wanted)) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`  ${ label }\n    期望: ${ JSON.stringify(wanted) }\n    实际: ${ JSON.stringify(actual) }`)
}

const atBottom = { scrollHeight: 1000, scrollTop: 600, clientHeight: 400 }
const nearBottom = { scrollHeight: 1000, scrollTop: 580, clientHeight: 400 }
const detached = { scrollHeight: 1000, scrollTop: 400, clientHeight: 400 }

expect('底部距离不小于零', bottomDistance({ ...atBottom, scrollTop: 700 }), 0)
expect('阈值内视为到达底部', isNearBottom(nearBottom, 24), true)
expect('接近底部不等于真正到达底部', isNearBottom(nearBottom, 1), false)
expect('阈值外不在底部', isNearBottom(detached, 24), false)
expect('用户向上滚动后退出跟随', nextStickyBottomState(StickyBottomState.PINNED, 'user-up'), StickyBottomState.DETACHED)
expect('内容增长不会擅自恢复跟随', nextStickyBottomState(StickyBottomState.DETACHED, 'layout-change'), StickyBottomState.DETACHED)
expect('接近底部不会覆盖用户上翻意图', nextStickyBottomState(StickyBottomState.DETACHED, 'near-bottom'), StickyBottomState.DETACHED)
expect(
  'detached 状态在视觉阈值内仍不恢复跟随',
  stickyBottomStatus(StickyBottomState.DETACHED, nearBottom),
  { state: StickyBottomState.DETACHED, reachedBottom: false, isAtBottom: false }
)
expect(
  '只有真正到达底部才恢复跟随',
  stickyBottomStatus(StickyBottomState.DETACHED, atBottom),
  { state: StickyBottomState.PINNED, reachedBottom: true, isAtBottom: true }
)
expect('程序化滚动事件不会退出跟随', nextStickyBottomState(StickyBottomState.PINNED, 'programmatic-scroll'), StickyBottomState.PINNED)
expect('回到底部后恢复跟随', nextStickyBottomState(StickyBottomState.DETACHED, 'reached-bottom'), StickyBottomState.PINNED)
expect('点击查看最新强制恢复跟随', nextStickyBottomState(StickyBottomState.DETACHED, 'force-bottom'), StickyBottomState.PINNED)
expect('PageUp 是向上阅读意图', isUpwardScrollKey({ key: 'PageUp' }), true)
expect('Shift+Space 是向上阅读意图', isUpwardScrollKey({ key: ' ', shiftKey: true }), true)
expect('普通 Space 不是向上阅读意图', isUpwardScrollKey({ key: ' ' }), false)
expect('组合键不改变跟随状态', isUpwardScrollKey({ key: 'ArrowUp', metaKey: true }), false)
expect('输入框内按键不应控制滚动', isEditableTarget({ tagName: 'INPUT' }), true)
expect('普通容器可以控制滚动', isEditableTarget({ tagName: 'DIV' }), false)

if (failed) {
  console.error(`\nSticky bottom 测试失败：${ failed } 项`)
  console.error(failures.join('\n'))
  process.exit(1)
}

console.log(`Sticky bottom 测试通过：${ passed } 项`)
