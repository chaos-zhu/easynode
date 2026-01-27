const io = require('socket.io-client')

const SERVER_URL = 'http://localhost:8082'
const VALID_TOKEN = 'U2FsdGVkX1+26QCTo4JlGxKnQFcDjOxHyZthx/zucoUMh4CVGc3d4DdBPG2LK52gLuO5RRtmnclYoZESSyQrP7RDoJxh4PLkF6Dm7m3PiO112i1DWxp/xANsRQBzotJ1soPa1ym82BNQRNoziZHbG2RmC/wM953x1zEBgK0wD6LW0I9cQMNIaiO+TV8f/qYt9m4QEoG3UBnLWCN5+oHU0DTOMJQgXBl7zFVwj/9YENt0rN5tBLZSSZv6krM94lmTO7V/mXycUqa/fWJuz7+B0ThlxFNFwzHdizGB+iqTHLoFrDL9Nw0d4oHnBOEkzSmwjIzNysVttfESpjAjNZ6gfmpV7+qERGxt9VHTogWP2cIaT5Dqjkc1ldG63yfYzXCx'
const VALID_SESSION = 'b6374f59-06d3-44a1-8da5-c1ace74cd0bc'

// 所有需要测试的WebSocket路径
const SOCKET_PATHS = [
  '/terminal',
  '/sftp-v2',
  '/docker',
  '/onekey',
  '/server-status',
  '/file-transfer'
]

// 测试用例
const testCases = [
  {
    name: '无Token连接',
    config: {
      auth: {},
      extraHeaders: { cookie: `session=${ VALID_SESSION }` }
    },
    expectedError: 'No Token'
  },
  {
    name: '无Cookie连接',
    config: {
      auth: { token: VALID_TOKEN },
      extraHeaders: {}
    },
    expectedError: 'No Cookie'
  },
  {
    name: '无Session连接',
    config: {
      auth: { token: VALID_TOKEN },
      extraHeaders: { cookie: 'other=value' }
    },
    expectedError: 'No Session Cookie'
  },
  {
    name: '伪造Token连接',
    config: {
      auth: { token: 'fake-invalid-token-12345' },
      extraHeaders: { cookie: `session=${ VALID_SESSION }` }
    },
    expectedError: 'Authentication Failed'
  },
  {
    name: '正常连接',
    config: {
      auth: { token: VALID_TOKEN },
      extraHeaders: { cookie: `session=${ VALID_SESSION }` }
    },
    expectedError: null // 预期成功
  }
]

async function runTest(testCase, path) {
  return new Promise((resolve) => {
    const socket = io(SERVER_URL, {
      path,
      ...testCase.config,
      transports: ['websocket'],
      reconnection: false
    })

    const timeout = setTimeout(() => {
      socket.disconnect()
      console.log('    ⏱️  超时（5秒）')
      resolve({ passed: false, error: 'timeout' })
    }, 5000)

    socket.on('connect', () => {
      clearTimeout(timeout)
      if (testCase.expectedError) {
        console.log(`    ❌ 预期失败但连接成功 (Socket ID: ${ socket.id })`)
        socket.disconnect()
        resolve({ passed: false, error: 'unexpected_success' })
      } else {
        console.log(`    ✅ 连接成功 (Socket ID: ${ socket.id })`)
        socket.disconnect()
        resolve({ passed: true })
      }
    })

    socket.on('connect_error', (error) => {
      clearTimeout(timeout)
      const errorMsg = error.message

      if (testCase.expectedError) {
        const passed = errorMsg.includes(testCase.expectedError)
        if (passed) {
          console.log(`    ✅ 预期错误: ${ errorMsg }`)
        } else {
          console.log('    ❌ 错误不匹配')
          console.log(`       实际: ${ errorMsg }`)
          console.log(`       预期: ${ testCase.expectedError }`)
        }
        resolve({ passed, error: errorMsg })
      } else {
        console.log(`    ❌ 不应该失败: ${ errorMsg }`)
        resolve({ passed: false, error: errorMsg })
      }
    })
  })
}

async function runAllTests() {
  console.log('========================================')
  console.log('WebSocket 全面权限测试')
  console.log('========================================')
  console.log(`服务器地址: ${ SERVER_URL }`)
  console.log(`Session: ${ VALID_SESSION.substring(0, 20) }...`)
  console.log(`Token: ${ VALID_TOKEN.substring(0, 20) }...`)
  console.log('========================================\n')

  const results = {}
  let totalTests = 0
  let totalPassed = 0
  let totalFailed = 0

  for (const path of SOCKET_PATHS) {
    console.log(`\n${ '='.repeat(60) }`)
    console.log(`测试路径: ${ path }`)
    console.log('='.repeat(60))

    results[path] = { passed: 0, failed: 0, tests: [] }

    for (const testCase of testCases) {
      console.log(`\n  测试: ${ testCase.name }`)
      const result = await runTest(testCase, path)

      totalTests++
      results[path].tests.push({
        name: testCase.name,
        ...result
      })

      if (result.passed) {
        results[path].passed++
        totalPassed++
      } else {
        results[path].failed++
        totalFailed++
      }

      // 延迟避免请求过快
      await new Promise(resolve => setTimeout(resolve, 500))
    }

    console.log(`\n  路径 ${ path } 总结: ${ results[path].passed }/${ testCases.length } 通过`)
  }

  // 打印总结
  console.log('\n\n' + '='.repeat(60))
  console.log('测试总结')
  console.log('='.repeat(60))

  console.log('\n各路径测试结果:')
  for (const path of SOCKET_PATHS) {
    const pathResult = results[path]
    const status = pathResult.failed === 0 ? '✅' : '❌'
    console.log(`  ${ status } ${ path }: ${ pathResult.passed }/${ testCases.length } 通过`)
  }

  console.log('\n整体统计:')
  console.log(`  总计测试: ${ totalTests }`)
  console.log(`  通过: ${ totalPassed } ✅`)
  console.log(`  失败: ${ totalFailed } ❌`)
  console.log(`  成功率: ${ ((totalPassed / totalTests) * 100).toFixed(2) }%`)

  console.log('\n' + '='.repeat(60))
  console.log(totalFailed === 0 ? '✅ 所有测试通过！' : '❌ 部分测试失败')
  console.log('='.repeat(60))

  process.exit(totalFailed > 0 ? 1 : 0)
}

// 检查配置
if (VALID_TOKEN === '你的有效token' || VALID_SESSION === '你的有效session') {
  console.error('❌ 错误：请先配置有效的 TOKEN 和 SESSION')
  console.error('\n获取方法：')
  console.error('1. 登录到系统')
  console.error('2. 打开浏览器开发者工具 (F12)')
  console.error('3. Session: Application → Cookies → session')
  console.error('4. Token: Console 中执行 localStorage.getItem("token")')
  console.error('\n然后修改本文件顶部的 VALID_TOKEN 和 VALID_SESSION')
  process.exit(1)
}

runAllTests()
