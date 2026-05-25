const { HostListDB, CredentialsDB, FavoriteSftpDB } = require('../utils/db-class')

const favoriteSftpDB = new FavoriteSftpDB().getInstance()

async function getSftpFavorites({ params, request, res }) {
  try {
    const hostId = params?.hostId || request.query?.hostId
    if (!hostId) {
      return res.fail({ msg: 'missing hostId' })
    }
    const favorites = await favoriteSftpDB.findAsync(
      { hostId },
      { sort: { createTime: -1 } }
    )
    return res.success({ data: favorites, msg: 'success' })
  } catch (error) {
    logger.error('getSftpFavorites error:', error.message)
    return res.fail({ msg: error.message || 'mobile sftp favorites failed' })
  }
}

module.exports = {
  getSftpFavorites
}
