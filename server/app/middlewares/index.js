import ipFilter from './ipFilter.js' // IP过滤
import responseHandler from './response.js' // 统一返回格式, 错误捕获
import useAuth from './auth.js' // 鉴权
// import useCors from './cors.js' // 处理跨域[暂时禁止]
import useLog from './useLog.js' // 记录日志，需要等待路由处理完成，所以得放路由前
import useKoaBody from './body.js' // 处理body参数 【请求需先走该中间件】
import { useRoutes, useAllowedMethods } from './router.js' // 路由管理
import useStatic from './static.js' // 静态目录
import useSftpCacheStatic from './sftp-cache.js' // SFTP缓存文件服务
import compress from './compress.js' // br/gzip压缩
import history from './history.js' // vue-router的history模式

export default [
  ipFilter,
  useSftpCacheStatic, // SFTP缓存文件服务
  compress,
  history,
  useStatic, // staic先注册，不然会被useAuth拦截
  // useCors,
  responseHandler,
  useKoaBody, // 先处理body，log和router都要用到
  useLog, // 日志记录开始【该module使用到了fs.mkdir()等读写api， 设置保存日志的目录需使用process.cwd()】
  useAuth,
  useAllowedMethods,
  useRoutes
]
