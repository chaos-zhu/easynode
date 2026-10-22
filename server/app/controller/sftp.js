import { HostListDB, FavoriteSftpDB } from '../utils/db-class.js'

const favoriteSftpDB = new FavoriteSftpDB().getInstance()
const hostsDB = new HostListDB().getInstance()

async function getSftpFavorites({ params, request, res }) {
  try {
    const hostId = params?.hostId || request.query?.hostId
    if (!hostId) return res.fail({ msg: 'missing hostId' })
    const favorites = await favoriteSftpDB.findAsync(
      { hostId }, { sort: { createTime: -1 } }
    )
    return res.success({ data: favorites, msg: 'success' })
  } catch (error) {
    logger.error('getSftpFavorites error:', error.message)
    return res.fail({ msg: error.message || 'sftp favorites failed' })
  }
}

// Metadata only. Native SSH/SFTP connections stay on the user's device.
async function addSftpFavorite({ params, request, res }) {
  try {
    const hostId = params?.hostId
    const { path, name, type } = request.body || {}
    if (typeof hostId !== 'string' || !hostId ||
        typeof path !== 'string' || !path.trim() ||
        typeof name !== 'string' || !name.trim() || !['folder', 'file'].includes(type)) {
      return res.fail({ msg: 'invalid favorite' })
    }
    if (!await hostsDB.findOneAsync({ _id: hostId })) return res.fail({ msg: 'host not found' })
    const existing = await favoriteSftpDB.findOneAsync({ hostId, path })
    if (!existing) {
      await favoriteSftpDB.insertAsync({ hostId, path, name: name.trim(), type, createTime: Date.now() })
    }
    return res.success({ msg: 'success' })
  } catch (error) {
    logger.error('addSftpFavorite error:', error.message)
    return res.fail({ msg: error.message || 'sftp favorites failed' })
  }
}

async function removeSftpFavorite({ params, request, res }) {
  try {
    const hostId = params?.hostId
    const path = request.query?.path
    if (typeof hostId !== 'string' || !hostId || typeof path !== 'string' || !path) {
      return res.fail({ msg: 'invalid favorite' })
    }
    await favoriteSftpDB.removeAsync({ hostId, path }, { multi: true })
    return res.success({ msg: 'success' })
  } catch (error) {
    logger.error('removeSftpFavorite error:', error.message)
    return res.fail({ msg: error.message || 'sftp favorites failed' })
  }
}

export { getSftpFavorites, addSftpFavorite, removeSftpFavorite }
