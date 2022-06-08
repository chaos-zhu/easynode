const responseHandler = async (ctx, next) => {

  ctx.res.success = ({ status, data, msg = 'success' } = {}) => {
    ctx.status = status || 200
    ctx.body = {
      status: ctx.status,
      data,
      msg
    }
  }
  ctx.res.fail = ({ status, msg = 'fail', data = {} } = {}) => {
    ctx.status = status || 400
    ctx.body = {
      status,
      data,
      msg
    }
  }

  try {
    await next()
  } catch (err) {
    console.log('中间件错误：', err)
    if (err.status)
      ctx.res.fail({ status: err.status, msg: err.message })
    else
      ctx.app.emit('error', err, ctx)
  }
}

module.exports = responseHandler
