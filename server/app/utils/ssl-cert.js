const selfsigned = require('selfsigned')

/**
 * 生成自签名证书
 * @returns {Object} 包含 cert 和 key 的对象
 */
function generateSelfSignedCert() {
  const attrs = [{ name: 'commonName', value: 'localhost' }]
  const pems = selfsigned.generate(attrs, {
    keySize: 2048,
    days: 3650, // 10年有效期
    algorithm: 'sha256',
    extensions: [
      {
        name: 'basicConstraints',
        cA: true
      },
      {
        name: 'keyUsage',
        keyCertSign: true,
        digitalSignature: true,
        nonRepudiation: true,
        keyEncipherment: true,
        dataEncipherment: true
      },
      {
        name: 'extKeyUsage',
        serverAuth: true,
        clientAuth: true,
        codeSigning: true,
        timeStamping: true
      },
      {
        name: 'subjectAltName',
        altNames: [
          {
            type: 2, // DNS
            value: 'localhost'
          },
          {
            type: 7, // IP
            ip: '127.0.0.1'
          }
        ]
      }
    ]
  })

  logger.info('已生成自签名证书')
  return {
    cert: pems.cert,
    key: pems.private
  }
}

module.exports = {
  generateSelfSignedCert
}
