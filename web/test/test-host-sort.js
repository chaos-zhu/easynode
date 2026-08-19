import assert from 'node:assert/strict'
import { compareHostNames } from '../src/utils/host-sort.js'

const sortHosts = (hosts) => [...hosts,].sort(compareHostNames)
const sortedNames = (hosts) => sortHosts(hosts).map(({ name }) => name)

assert.deepEqual(
  sortedNames([
    { id: '3', name: 't10' },
    { id: '1', name: 't1' },
    { id: '2', name: 't2' },
  ]),
  ['t1', 't2', 't10',]
)

assert.deepEqual(
  sortedNames([
    { id: '4', name: '闲置10' },
    { id: '2', name: '闲云' },
    { id: '3', name: '闲置2' },
    { id: '1', name: '闲鱼' },
  ]),
  ['闲鱼', '闲云', '闲置2', '闲置10',]
)

assert.deepEqual(
  sortHosts([
    { id: 'b', name: 'T1', index: 100 },
    { id: 'a', name: 't1', index: 1 },
  ]).map(({ id }) => id),
  ['a', 'b',]
)

assert.deepEqual(
  sortHosts([
    { id: 'b', name: null },
    { id: 'a' },
    { id: 'c', name: 'server' },
  ]).map(({ id }) => id),
  ['a', 'b', 'c',]
)

assert.deepEqual(
  sortHosts([
    { id: 'later', name: 't10', index: 100 },
    { id: 'earlier', name: 't2', index: 1 },
  ]).map(({ id }) => id),
  ['earlier', 'later',]
)

console.log('✅ 实例名称排序测试全部通过')
