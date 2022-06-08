let getOsData = require('../utils/os-data')

module.exports = async ({ res }) => {
  let data = await getOsData()
  res.success({ data })
}
