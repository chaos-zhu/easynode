import assert from 'node:assert/strict'
import { parseFreeOutput } from '../app/utils/parse-free-output.js'

const openWrt = parseFreeOutput(`
              total        used        free      shared  buff/cache   available
Mem:         238128       71380      113900        1584       52848      115504
Swap:         78844           0       78844
`)
assert.equal(openWrt.memInfo.totalMemMb, 233)
assert.equal(openWrt.memInfo.usedMemMb, 70)
assert.equal(openWrt.memInfo.usedMemPercentage, 29.98)
assert.equal(openWrt.swapInfo.swapTotal, 77)

const linux = parseFreeOutput(`
              total        used        free      shared  buff/cache   available
Mem:        8178688     2043904     1024000       11264     5110784     5734400
Swap:       2096128      524288     1571840
`)
assert.equal(linux.memInfo.totalMemMb, 7987)
assert.equal(linux.memInfo.usedMemMb, 1996)
assert.equal(linux.swapInfo.swapTotal, 2047)
assert.equal(linux.swapInfo.swapUsed, 512)

console.log('free output parser tests passed')
