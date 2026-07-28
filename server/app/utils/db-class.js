import Datastore from '@seald-io/nedb'
import {
  credentialsDBPath,
  hostListDBPath,
  keyDBPath,
  notifyDBPath,
  notifyConfigDBPath,
  groupConfDBPath,
  scriptsDBPath,
  scriptGroupDBPath,
  onekeyDBPath,
  plusDBPath,
  aiConfigDBPath,
  chatHistoryDBPath,
  favoriteSftpDBPath,
  proxyDBPath,
  fileTransferDBPath,
  terminalConfigDBPath,
  serverListDBPath,
  sessionDBPath,
  terminalSessionDBPath
} from '../config/index.js'

export class KeyDB {
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

export class HostListDB {
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

export class CredentialsDB {
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

export class NotifyDB {
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

export class NotifyConfigDB {
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

export class GroupDB {
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

export class ScriptsDB {
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

export class ScriptGroupDB {
  constructor() {
    if (!ScriptGroupDB.instance) {
      ScriptGroupDB.instance = new Datastore({ filename: scriptGroupDBPath, autoload: true })
    }
  }
  getInstance() {
    return ScriptGroupDB.instance
  }
}

export class OnekeyDB {
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

export class PlusDB {
  constructor() {
    if (!PlusDB.instance) {
      PlusDB.instance = new Datastore({ filename: plusDBPath, autoload: true })
    }
  }
  getInstance() {
    return PlusDB.instance
  }
}

export class AIConfigDB {
  constructor() {
    if (!AIConfigDB.instance) {
      AIConfigDB.instance = new Datastore({ filename: aiConfigDBPath, autoload: true })
    }
  }
  getInstance() {
    return AIConfigDB.instance
  }
}

export class ChatHistoryDB {
  constructor() {
    if (!ChatHistoryDB.instance) {
      ChatHistoryDB.instance = new Datastore({ filename: chatHistoryDBPath, autoload: true })
    }
  }
  getInstance() {
    return ChatHistoryDB.instance
  }
}

export class FavoriteSftpDB {
  constructor() {
    if (!FavoriteSftpDB.instance) {
      FavoriteSftpDB.instance = new Datastore({ filename: favoriteSftpDBPath, autoload: true })
    }
  }
  getInstance() {
    return FavoriteSftpDB.instance
  }
}

export class ProxyDB {
  constructor() {
    if (!ProxyDB.instance) {
      ProxyDB.instance = new Datastore({ filename: proxyDBPath, autoload: true })
    }
  }
  getInstance() {
    return ProxyDB.instance
  }
}

export class FileTransferDB {
  constructor() {
    if (!FileTransferDB.instance) {
      FileTransferDB.instance = new Datastore({ filename: fileTransferDBPath, autoload: true })
    }
  }
  getInstance() {
    return FileTransferDB.instance
  }
}

export class TerminalConfigDB {
  constructor() {
    if (!TerminalConfigDB.instance) {
      TerminalConfigDB.instance = new Datastore({ filename: terminalConfigDBPath, autoload: true })
    }
  }
  getInstance() {
    return TerminalConfigDB.instance
  }
}

export class ServerListDB {
  constructor() {
    if (!ServerListDB.instance) {
      ServerListDB.instance = new Datastore({ filename: serverListDBPath, autoload: true })
    }
  }
  getInstance() {
    return ServerListDB.instance
  }
}

export class SessionDB {
  constructor() {
    if (!SessionDB.instance) {
      SessionDB.instance = new Datastore({ filename: sessionDBPath, autoload: true })
    }
  }
  getInstance() {
    return SessionDB.instance
  }
}

export class TerminalSessionDB {
  constructor() {
    if (!TerminalSessionDB.instance) {
      TerminalSessionDB.instance = new Datastore({ filename: terminalSessionDBPath, autoload: true })
    }
  }
  getInstance() {
    return TerminalSessionDB.instance
  }
}
