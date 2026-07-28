import koaBodyModule from 'koa-body'

const { koaBody } = koaBodyModule

export default koaBody({
  multipart: false
})
