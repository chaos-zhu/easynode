const responseHandler = require('./response')
const useJwt = require('./jwt')
const useCors = require('./cors')
const useLog = require('./log4')
const useKoaBody = require('./body')
const { useRoutes, useAllowedMethods } = require('./router')
const useStatic = require('./static')
const compress = require('./compress')
const history = require('./history')

module.exports = [
  compress,
  history,
  useStatic,
  useCors,
  responseHandler,
  useKoaBody,
  useLog,
  useJwt,
  useAllowedMethods,
  useRoutes
]
