const offlineInspect = require('./offline-inspect')
const expiredNotify = require('./expired-notify')

module.exports = () => {
  offlineInspect()
  expiredNotify()
}
