// 响应压缩模块，自适应头部压缩方式
import compress from 'koa-compress'

const options = { threshold: 2048 }

export default compress(options)
