const { LogDB } = require('../utils/db-class')
const logDB = new LogDB().getInstance()

let whiteList = process.env.ALLOWED_IPS ? process.env.ALLOWED_IPS.split(',') : []

async function getLog({ res }) {
  let list = await logDB.findAsync({})
  list = list.map(item => {
    return { ...item, id: item._id }
  })
  list?.sort((a, b) => Number(b.date) - Number(a.date))
  res.success({ data: { list, whiteList } })
}

module.exports = {
  getLog
}
