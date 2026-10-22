import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const originalCwd = process.cwd()
const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'easynode-favorites-'))
await fs.mkdir(path.join(tempRoot, 'app', 'db'), { recursive: true })
process.chdir(tempRoot)
global.logger = { info() {}, warn() {}, error() {} }
try {
  const { HostListDB, FavoriteSftpDB } = await import('../app/utils/db-class.js')
  const { getSftpFavorites, addSftpFavorite, removeSftpFavorite } = await import('../app/controller/sftp.js')
  await new HostListDB().getInstance().insertAsync([{ _id: 'one' }, { _id: 'two' }])
  const favorites = new FavoriteSftpDB().getInstance()
  async function call(controller, { hostId = 'one', body = {}, query = {} } = {}) {
    let result
    await controller({ params: { hostId }, request: { body, query }, res: {
      success(value) { result = { ok: true, ...value } },
      fail(value) { result = { ok: false, ...value } }
    } })
    return result
  }
  const body = { path: '/srv/项目', name: '项目', type: 'folder' }
  assert.equal((await call(addSftpFavorite, { body })).ok, true)
  assert.equal((await call(addSftpFavorite, { body })).ok, true)
  assert.equal((await call(getSftpFavorites)).data.length, 1, 'duplicate path stays unique')
  const record = (await call(getSftpFavorites)).data[0]
  assert.equal(record.name, '项目')
  assert.equal(record.type, 'folder', 'same format as Web SFTP favorites')
  assert.equal(typeof record.createTime, 'number')
  await call(addSftpFavorite, { hostId: 'two', body })
  assert.equal((await call(removeSftpFavorite, { query: { path: body.path } })).ok, true)
  assert.equal((await call(getSftpFavorites)).data.length, 0)
  assert.equal((await call(getSftpFavorites, { hostId: 'two' })).data.length, 1, 'delete remains host scoped')
  assert.equal((await call(removeSftpFavorite, { query: { path: body.path } })).ok, true)
  for (const invalid of [{}, { ...body, path: {} }, { ...body, name: ' ' }, { ...body, type: 'unknown' }]) {
    assert.equal((await call(addSftpFavorite, { body: invalid })).ok, false)
  }
  assert.equal((await call(addSftpFavorite, { hostId: 'missing', body })).ok, false)
  assert.equal((await call(removeSftpFavorite, { query: { path: { $ne: '' } } })).ok, false)
  assert.equal((await favorites.findAsync({})).length, 1, 'invalid metadata does not mutate storage')
  console.log('SFTP favorite REST metadata tests passed')
} finally {
  process.chdir(originalCwd)
  await fs.rm(tempRoot, { recursive: true, force: true })
}
