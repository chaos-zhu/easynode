const osu = require('node-os-utils')
const osSwap = require('../lib/swap')
const os = require('os')

let cpu = osu.cpu
let mem = osu.mem
let drive = osu.drive
let netstat = osu.netstat
let osuOs = osu.os
let users = osu.users

async function cpuInfo() {
  let cpuUsage = await cpu.usage(500)
  let cpuCount = cpu.count()
  let cpuModel = cpu.model()
  return {
    cpuUsage,
    cpuCount,
    cpuModel
  }
}

async function memInfo() {
  let memInfo = await mem.info()
  return {
    ...memInfo
  }
}

async function swapInfo() {
  let swapInfo = await osSwap()
  return {
    ...swapInfo
  }
}

async function driveInfo() {
  let driveInfo = {}
  try {
    driveInfo = await drive.info()
  } catch {
    // console.log(driveInfo)
  }
  return driveInfo
}

async function netstatInfo() {
  let netstatInfo = await netstat.inOut()
  return netstatInfo === 'not supported' ? {} : netstatInfo
}

async function osInfo() {
  let type = os.type()
  let platform = os.platform()
  let release = os.release()
  let uptime = osuOs.uptime()
  let ip = osuOs.ip()
  let hostname = osuOs.hostname()
  let arch = osuOs.arch()
  return {
    type,
    platform,
    release,
    ip,
    hostname,
    arch,
    uptime
  }
}

async function openedCount() {
  let openedCount = await users.openedCount()
  return openedCount === 'not supported' ? 0 : openedCount
}

module.exports = async () => {
  let data = {}
  try {
    data = {
      cpuInfo: await cpuInfo(),
      memInfo: await memInfo(),
      swapInfo: await swapInfo(),
      driveInfo: await driveInfo(),
      netstatInfo: await netstatInfo(),
      osInfo: await osInfo(),
      openedCount: await openedCount()
    }
    return data
  } catch(err){
    return err.toString()
  }
}
