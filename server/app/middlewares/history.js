import koa2ConnectHistoryApiFallbackModule from 'koa2-connect-history-api-fallback'
const { historyApiFallback } = koa2ConnectHistoryApiFallbackModule

export default historyApiFallback({ whiteList: ['/api'] })
