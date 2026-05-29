class RuntimeState {
  constructor() {
    if (!RuntimeState.instance) {
      this.decryptKeyCipher = null
      this.token = null
      this.tokenExpireAt = 0
      RuntimeState.instance = this
    }
    return RuntimeState.instance
  }

  getInstance() {
    return RuntimeState.instance
  }

  setDecryptKey(cipher) {
    this.decryptKeyCipher = cipher || null
  }

  getDecryptKey() {
    return this.decryptKeyCipher
  }

  clearDecryptKey() {
    this.decryptKeyCipher = null
  }

  setToken(value, expireAt) {
    this.token = value || null
    this.tokenExpireAt = Number(expireAt) || 0
  }

  getToken() {
    if (!this.token) return null
    if (this.tokenExpireAt && Date.now() > this.tokenExpireAt) return null
    return this.token
  }

  getTokenExpireAt() {
    return this.tokenExpireAt
  }

  clearToken() {
    this.token = null
    this.tokenExpireAt = 0
  }
}

module.exports = { RuntimeState }
