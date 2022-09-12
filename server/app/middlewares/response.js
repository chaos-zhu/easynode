const responseHandler = async (ctx, next) => {
  // 统一成功响应
  ctx.res.success = ({ status, data, msg = 'success' } = {}) => {
    ctx.status = status || 200 // 没传默认200
    ctx.body = {
      status: ctx.status, // 响应成功默认 200
      data,
      msg
    }
  }
  // 统一错误响应
  ctx.res.fail = ({ status, msg = 'fail', data = {} } = {}) => {
    ctx.status = status || 400 // 响应失败默认 400
    ctx.body = {
      status, // 失败默认 400
      data,
      msg
    }
  }

  // 错误响应捕获
  try {
    await next() // 每个中间件都需等待next完成调用，不然会返回404给前端!!!
  } catch (err) {
    consola.error('中间件错误：', err)
    if (err.status)
      ctx.res.fail({ status: err.status, msg: err.message }) // 自己主动抛出的错误 throwError
    else
      ctx.app.emit('error', err, ctx) // 程序运行时的错误 main.js中监听
  }
}

module.exports = responseHandler
