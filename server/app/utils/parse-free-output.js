const toMb = value => Math.round(value / 1024)

export const parseFreeOutput = output => {
  const lines = output.split('\n')
  const memLine = lines.find(line => line.trim().startsWith('Mem:'))
  const swapLine = lines.find(line => line.trim().startsWith('Swap:'))
  let memInfo = { totalMemMb: 0, usedMemMb: 0, freeMemMb: 0, usedMemPercentage: 0, freeMemPercentage: 0 }
  let swapInfo = { swapTotal: 0, swapUsed: 0, swapFree: 0, swapPercentage: '0' }

  if (memLine) {
    const parts = memLine.trim().split(/\s+/)
    const totalKb = Number.parseInt(parts[1], 10)
    const usedKb = Number.parseInt(parts[2], 10)
    const freeKb = parts[3] ? Number.parseInt(parts[3], 10) : totalKb - usedKb
    if (Number.isFinite(totalKb) && Number.isFinite(usedKb)) {
      const totalMb = toMb(totalKb)
      const usedMb = toMb(usedKb)
      const freeMb = Number.isFinite(freeKb) ? toMb(freeKb) : 0
      memInfo = {
        totalMemMb: totalMb,
        usedMemMb: usedMb,
        freeMemMb: freeMb,
        usedMemPercentage: totalKb > 0 ? Number(((usedKb / totalKb) * 100).toFixed(2)) : 0,
        freeMemPercentage: totalKb > 0 && Number.isFinite(freeKb) ? Number(((freeKb / totalKb) * 100).toFixed(2)) : 0
      }
    }
  }

  if (swapLine) {
    const parts = swapLine.trim().split(/\s+/)
    const totalKb = Number.parseInt(parts[1], 10)
    const usedKb = Number.parseInt(parts[2], 10)
    const freeKb = parts[3] ? Number.parseInt(parts[3], 10) : totalKb - usedKb
    if (Number.isFinite(totalKb) && Number.isFinite(usedKb)) {
      swapInfo = {
        swapTotal: toMb(totalKb),
        swapUsed: toMb(usedKb),
        swapFree: Number.isFinite(freeKb) ? toMb(freeKb) : 0,
        swapPercentage: totalKb > 0 ? ((usedKb / totalKb) * 100).toFixed(1) : '0'
      }
    }
  }

  return { memInfo, swapInfo }
}
