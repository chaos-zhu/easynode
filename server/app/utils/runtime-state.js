class RuntimeState {
  constructor() {
    if (!RuntimeState.instance) {
      this.decryptKeyCipher = null
      this.token = null
      this.tokenExpireAt = 0
      this.sessionId = null
      this.plusKicked = false
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

  // sessionId: 进程级在线会话标识，每次进程启动新生成，仅存内存，进程退出即销毁，绝不落盘
  setSessionId(id) {
    this.sessionId = id || null
  }

  getSessionId() {
    return this.sessionId
  }

  clearSessionId() {
    this.sessionId = null
  }

  // plusKicked: 当前进程是否已被授权端踢出（脏会话），进程级标志，重启清零
  setPlusKicked(value) {
    this.plusKicked = Boolean(value)
  }

  getPlusKicked() {
    return this.plusKicked === true
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
