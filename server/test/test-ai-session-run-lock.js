import {
  claimSessionRun,
  releaseSessionRun,
  clearSessionRunLocks
} from '../app/ai/session-run-lock.js'

let passed = 0
const expect = (label, actual, expected) => {
  if (actual !== expected) throw new Error(`${ label }: expected ${ expected }, got ${ actual }`)
  passed += 1
}

clearSessionRunLocks()
expect('first owner claims session', claimSessionRun('session-1', 'socket-a'), true)
expect('same owner cannot start a second run', claimSessionRun('session-1', 'socket-a'), false)
expect('other owner is rejected', claimSessionRun('session-1', 'socket-b'), false)
expect('other owner cannot release lock', releaseSessionRun('session-1', 'socket-b'), false)
expect('owner releases lock', releaseSessionRun('session-1', 'socket-a'), true)
expect('other owner can claim after release', claimSessionRun('session-1', 'socket-b'), true)
clearSessionRunLocks()

console.log(`\n✅ AI session run lock tests passed (${ passed })`)
