const axios = require('axios')

const BASE_URL = 'http://localhost:8082/api/v1'

// 配置 - 请替换为你的有效凭证
const VALID_TOKEN = 'U2FsdGVkX1+26QCTo4JlGxKnQFcDjOxHyZthx/zucoUMh4CVGc3d4DdBPG2LK52gLuO5RRtmnclYoZESSyQrP7RDoJxh4PLkF6Dm7m3PiO112i1DWxp/xANsRQBzotJ1soPa1ym82BNQRNoziZHbG2RmC/wM953x1zEBgK0wD6LW0I9cQMNIaiO+TV8f/qYt9m4QEoG3UBnLWCN5+oHU0DTOMJQgXBl7zFVwj/9YENt0rN5tBLZSSZv6krM94lmTO7V/mXycUqa/fWJuz7+B0ThlxFNFwzHdizGB+iqTHLoFrDL9Nw0d4oHnBOEkzSmwjIzNysVttfESpjAjNZ6gfmpV7+qERGxt9VHTogWP2cIaT5Dqjkc1ldG63yfYzXCx'
const VALID_SESSION = 'b6374f59-06d3-44a1-8da5-c1ace74cd0bc'

// 测试用例
const testCases = [
  {
    name: '1. 无Token访问受保护接口',
    request: {
      url: `${ BASE_URL }/host-list`,
      headers: {
        Cookie: `session=${ VALID_SESSION }`
      }
    },
    expected: { status: 401, msg: '未登录(token)' }
  },
  {
    name: '2. 无Session访问受保护接口',
    request: {
      url: `${ BASE_URL }/host-list`,
      headers: {
        token: VALID_TOKEN
      }
    },
    expected: { status: 401, msg: '未登录(session)' }
  },
  {
    name: '3. 伪造Token访问',
    request: {
      url: `${ BASE_URL }/host-list`,
      headers: {
        token: 'fake-invalid-token-12345',
        Cookie: `session=${ VALID_SESSION }`
      }
    },
    expected: { status: 403, msg: 'TOKEN校验失败, 请重新登录' }
  },
  {
    name: '4. 白名单路由访问（无需认证）',
    request: {
      url: `${ BASE_URL }/get-pub-pem`
    },
    expected: { status: 200 }
  },
  {
    name: '5. 正常访问受保护接口',
    request: {
      url: `${ BASE_URL }/host-list`,
      headers: {
        token: VALID_TOKEN,
        Cookie: `session=${ VALID_SESSION }`
      }
    },
    expected: { status: 200, success: true }
  },
  {
    name: '6. 访问其他受保护接口 - 获取分组',
    request: {
      url: `${ BASE_URL }/group`,
      headers: {
        token: VALID_TOKEN,
        Cookie: `session=${ VALID_SESSION }`
      }
    },
    expected: { status: 200, success: true }
  },
  {
    name: '7. 访问其他受保护接口 - 获取脚本列表',
    request: {
      url: `${ BASE_URL }/script`,
      headers: {
        token: VALID_TOKEN,
        Cookie: `session=${ VALID_SESSION }`
      }
    },
    expected: { status: 200, success: true }
  }
]

// 执行测试
async function runTests() {
  console.log('========================================')
  console.log('RESTful API 权限测试')
  console.log('========================================')
  console.log(`服务器地址: ${ BASE_URL }`)
  console.log(`Session: ${ VALID_SESSION.substring(0, 20) }...`)
  console.log(`Token: ${ VALID_TOKEN.substring(0, 20) }...`)
  console.log('========================================\n')

  let passedCount = 0
  let failedCount = 0

  for (const testCase of testCases) {
    try {
      console.log(`测试: ${ testCase.name }`)

      const response = await axios.get(testCase.request.url, {
        headers: testCase.request.headers || {},
        validateStatus: () => true // 接受所有状态码
      })

      let testPassed = true

      // 检查状态码
      const statusPassed = response.status === testCase.expected.status
      console.log(`  状态码: ${ response.status } (预期: ${ testCase.expected.status }) ${ statusPassed ? '✅' : '❌' }`)
      if (!statusPassed) testPassed = false

      // 检查消息（如果有）
      if (testCase.expected.msg) {
        const msgPassed = response.data.msg === testCase.expected.msg
        console.log(`  消息: "${ response.data.msg }" ${ msgPassed ? '✅' : '❌' }`)
        if (!msgPassed) {
          console.log(`      预期: "${ testCase.expected.msg }"`)
          testPassed = false
        }
      }

      // 检查success字段（如果有）
      // 智能判断：如果响应是数组，或者有data字段，也认为是成功的
      if (testCase.expected.success !== undefined) {
        const isActuallySuccess = response.data.success === true ||
                                 Array.isArray(response.data) ||
                                 (response.data.data !== undefined && response.status === 200)
        const successPassed = isActuallySuccess === testCase.expected.success

        if (response.data.success !== undefined) {
          console.log(`  成功标志: ${ response.data.success } (预期: ${ testCase.expected.success }) ${ successPassed ? '✅' : '❌' }`)
        } else if (Array.isArray(response.data)) {
          console.log(`  响应类型: 数组 (长度: ${ response.data.length }) ${ successPassed ? '✅' : '❌' }`)
        } else if (response.data.data !== undefined) {
          console.log(`  响应类型: 对象包含data字段 ${ successPassed ? '✅' : '❌' }`)
        } else {
          console.log(`  响应类型: 其他 (状态200视为成功) ${ successPassed ? '✅' : '❌' }`)
        }

        if (!successPassed) testPassed = false
      }

      if (testPassed) {
        console.log('  结果: ✅ 通过\n')
        passedCount++
      } else {
        console.log('  结果: ❌ 失败\n')
        failedCount++
      }

    } catch (error) {
      console.log(`  ❌ 测试异常: ${ error.message }\n`)
      failedCount++
    }

    // 添加延迟避免请求过快
    await new Promise(resolve => setTimeout(resolve, 300))
  }

  console.log('========================================')
  console.log('测试总结')
  console.log('========================================')
  console.log(`总计: ${ testCases.length } 个测试`)
  console.log(`通过: ${ passedCount } ✅`)
  console.log(`失败: ${ failedCount } ❌`)
  console.log(`成功率: ${ ((passedCount / testCases.length) * 100).toFixed(2) }%`)
  console.log('========================================')

  process.exit(failedCount > 0 ? 1 : 0)
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

runTests()
