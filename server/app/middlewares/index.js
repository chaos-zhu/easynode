const ipFilter = require('./ipFilter') // IP过滤
const responseHandler = require('./response') // 统一返回格式, 错误捕获
const useAuth = require('./auth') // 鉴权
// const useCors = require('./cors') // 处理跨域[暂时禁止]
const useLog = require('./log4') // 记录日志，需要等待路由处理完成，所以得放路由前
const useKoaBody = require('./body') // 处理body参数 【请求需先走该中间件】
const { useRoutes, useAllowedMethods } = require('./router') // 路由管理
const useStatic = require('./static') // 静态目录
const useSftpCacheStatic = require('./sftp-cache') // SFTP缓存文件服务
const compress = require('./compress') // br/gzip压缩
const history = require('./history') // vue-router的history模式

module.exports = [
  ipFilter,
  useSftpCacheStatic, // SFTP缓存文件服务
  compress,
  history,
  useStatic, // staic先注册，不然会被jwt拦截
  // useCors,
  responseHandler,
  useKoaBody, // 先处理body，log和router都要用到
  useLog, // 日志记录开始【该module使用到了fs.mkdir()等读写api， 设置保存日志的目录需使用process.cwd()】
  useAuth,
  useAllowedMethods,
  useRoutes
]
