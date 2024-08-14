let exec = require('child_process').exec
let os = require('os')

function getSwapMemory() {
  return new Promise((resolve, reject) => {
    if (os.platform() === 'win32') {
      // Windows-specific command
      const command = 'powershell -command "Get-CimInstance Win32_OperatingSystem | Select-Object TotalVirtualMemorySize, FreeVirtualMemory"'
      exec(command, { encoding: 'utf8' }, (error, stdout, stderr) => {
        if (error) {
          console.error('exec error:', error)
          return reject(error)
        }
        if (stderr) {
          console.error('stderr:', stderr)
          return reject(stderr)
        }

        const lines = stdout.trim().split('\n')
        const values = lines[lines.length - 1].trim().split(/\s+/)
        const totalVirtualMemory = parseInt(values[0], 10) / 1024
        const freeVirtualMemory = parseInt(values[1], 10) / 1024
        const usedVirtualMemory = totalVirtualMemory - freeVirtualMemory

        resolve({
          swapTotal: totalVirtualMemory,
          swapFree: freeVirtualMemory,
          swapUsed: usedVirtualMemory,
          swapPercentage: ((usedVirtualMemory / totalVirtualMemory) * 100).toFixed(1)
        })
      })
    } else {
      exec('free -m | grep Swap', (error, stdout, stderr) => {
        if (error) {
          console.error('exec error:', error)
          return reject(error)
        }
        if (stderr) {
          console.error('stderr:', stderr)
          return reject(stderr)
        }

        const swapInfo = stdout.trim().split(/\s+/)
        const swapTotal = parseInt(swapInfo[1], 10)
        const swapUsed = parseInt(swapInfo[2], 10)
        const swapFree = parseInt(swapInfo[3], 10)

        resolve({
          swapTotal,
          swapUsed,
          swapFree,
          swapPercentage: ((swapUsed / swapTotal) * 100).toFixed(1)
        })
      })
    }
  })
}

module.exports = getSwapMemory