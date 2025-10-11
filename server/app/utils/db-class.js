const Datastore = require('@seald-io/nedb')
const {
  credentialsDBPath,
  hostListDBPath,
  keyDBPath,
  notifyDBPath,
  notifyConfigDBPath,
  groupConfDBPath,
  scriptsDBPath,
  scriptGroupDBPath,
  onekeyDBPath,
  logDBPath,
  plusDBPath,
  aiConfigDBPath,
  chatHistoryDBPath,
  favoriteSftpDBPath,
  proxyDBPath,
  fileTransferDBPath,
  terminalConfigDBPath
} = require('../config')

module.exports.KeyDB = class KeyDB {
  constructor() {
    if (!KeyDB.instance) {
      KeyDB.instance = new Datastore({ filename: keyDBPath, autoload: true })
      // KeyDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return KeyDB.instance
  }
}

module.exports.HostListDB = class HostListDB {
  constructor() {
    if (!HostListDB.instance) {
      HostListDB.instance = new Datastore({ filename: hostListDBPath, autoload: true })
      // HostListDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return HostListDB.instance
  }
}

module.exports.CredentialsDB = class CredentialsDB {
  constructor() {
    if (!CredentialsDB.instance) {
      CredentialsDB.instance = new Datastore({ filename: credentialsDBPath, autoload: true })
      // CredentialsDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return CredentialsDB.instance
  }
}

module.exports.NotifyDB = class NotifyDB {
  constructor() {
    if (!NotifyDB.instance) {
      NotifyDB.instance = new Datastore({ filename: notifyDBPath, autoload: true })
      // NotifyDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return NotifyDB.instance
  }
}

module.exports.NotifyConfigDB = class NotifyConfigDB {
  constructor() {
    if (!NotifyConfigDB.instance) {
      NotifyConfigDB.instance = new Datastore({ filename: notifyConfigDBPath, autoload: true })
      // NotifyConfigDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return NotifyConfigDB.instance
  }
}

module.exports.GroupDB = class GroupDB {
  constructor() {
    if (!GroupDB.instance) {
      GroupDB.instance = new Datastore({ filename: groupConfDBPath, autoload: true })
      // GroupDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return GroupDB.instance
  }
}

module.exports.ScriptsDB = class ScriptsDB {
  constructor() {
    if (!ScriptsDB.instance) {
      ScriptsDB.instance = new Datastore({ filename: scriptsDBPath, autoload: true })
      // ScriptsDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return ScriptsDB.instance
  }
}

module.exports.ScriptGroupDB = class ScriptGroupDB {
  constructor() {
    if (!ScriptGroupDB.instance) {
      ScriptGroupDB.instance = new Datastore({ filename: scriptGroupDBPath, autoload: true })
    }
  }
  getInstance() {
    return ScriptGroupDB.instance
  }
}

module.exports.OnekeyDB = class OnekeyDB {
  constructor() {
    if (!OnekeyDB.instance) {
      OnekeyDB.instance = new Datastore({ filename: onekeyDBPath, autoload: true })
      // OnekeyDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return OnekeyDB.instance
  }
}

module.exports.LogDB = class LogDB {
  constructor() {
    if (!LogDB.instance) {
      LogDB.instance = new Datastore({ filename: logDBPath, autoload: true })
      // LogDB.instance.setAutocompactionInterval(5000)
    }
  }
  getInstance() {
    return LogDB.instance
  }
}

module.exports.PlusDB = class PlusDB {
  constructor() {
    if (!PlusDB.instance) {
      PlusDB.instance = new Datastore({ filename: plusDBPath, autoload: true })
    }
  }
  getInstance() {
    return PlusDB.instance
  }
}

module.exports.AIConfigDB = class AIConfigDB {
  constructor() {
    if (!AIConfigDB.instance) {
      AIConfigDB.instance = new Datastore({ filename: aiConfigDBPath, autoload: true })
    }
  }
  getInstance() {
    return AIConfigDB.instance
  }
}

module.exports.ChatHistoryDB = class ChatHistoryDB {
  constructor() {
    if (!ChatHistoryDB.instance) {
      ChatHistoryDB.instance = new Datastore({ filename: chatHistoryDBPath, autoload: true })
    }
  }
  getInstance() {
    return ChatHistoryDB.instance
  }
}

module.exports.FavoriteSftpDB = class FavoriteSftpDB {
  constructor() {
    if (!FavoriteSftpDB.instance) {
      FavoriteSftpDB.instance = new Datastore({ filename: favoriteSftpDBPath, autoload: true })
    }
  }
  getInstance() {
    return FavoriteSftpDB.instance
  }
}

module.exports.ProxyDB = class ProxyDB {
  constructor() {
    if (!ProxyDB.instance) {
      ProxyDB.instance = new Datastore({ filename: proxyDBPath, autoload: true })
    }
  }
  getInstance() {
    return ProxyDB.instance
  }
}

module.exports.FileTransferDB = class FileTransferDB {
  constructor() {
    if (!FileTransferDB.instance) {
      FileTransferDB.instance = new Datastore({ filename: fileTransferDBPath, autoload: true })
    }
  }
  getInstance() {
    return FileTransferDB.instance
  }
}

module.exports.HighlightConfigDB = class HighlightConfigDB {
  constructor() {
    if (!HighlightConfigDB.instance) {
      HighlightConfigDB.instance = new Datastore({ filename: terminalConfigDBPath, autoload: true })
    }
  }
  getInstance() {
    return HighlightConfigDB.instance
  }
}

module.exports.TerminalConfigDB = class TerminalConfigDB {
  constructor() {
    if (!TerminalConfigDB.instance) {
      TerminalConfigDB.instance = new Datastore({ filename: terminalConfigDBPath, autoload: true })
    }
  }
  getInstance() {
    return TerminalConfigDB.instance
  }
}