import { withSftp } from './ssh.js'

/** 解析远程真实路径；目标不存在时保留请求路径，让执行阶段返回准确错误。 */
export function resolveRemotePath(hostId, pathname) {
  return withSftp(hostId, (sftp) => new Promise((resolve) => {
    sftp.realpath(pathname, (error, resolved) => {
      resolve(error || !resolved ? pathname : resolved)
    })
  }))
}
