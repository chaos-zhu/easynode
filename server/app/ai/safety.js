/**
 * 命令安全层
 *
 * 三级分类而非二元 normal/deny：
 *   deny   —— 永不执行，任何模式下拒绝，不可通过配置解除
 *   high   —— 强制人工确认，即使在授权模式下也弹窗
 *   normal —— 交由会话模式处理
 *
 * 中间态 high 是关键。二元模型下，把 $(...)、eval 直接拉黑会让
 * `VAR=$(date +%F)` 这类日常写法全部失效，用户最终会清空黑名单，
 * 护栏归零；不拉黑则漏放。high 让两者都不必牺牲。
 *
 * ⚠️ 认知边界：这一层是防呆，不是安全边界。真正的边界是权限模型
 * 与 SSH 账号自身的权限。不要指望正则能拦住有意绕过的人。
 */

import { parseCommandLine, unwrapCommand, expandFlags, positionalArgs } from './shell-lexer.js'
import { classifyReadPath, DataRisk } from './data-policy.js'
import { classifyFileMutations, extractFileMutations } from './file-mutation-policy.js'
import { Effect, Risk } from './policy.js'

export { Effect, Risk }

const RISK_ORDER = { [Risk.NORMAL]: 0, [Risk.HIGH]: 1, [Risk.DENY]: 2 }
const EFFECT_ORDER = { [Effect.READ]: 0, [Effect.WRITE]: 1, [Effect.DELETE]: 2 }

// 块设备
const BLOCK_DEVICE_RE = /^\/dev\/(sd[a-z]|nvme\d|vd[a-z]|hd[a-z]|xvd[a-z]|mmcblk\d|loop\d)/
// 根目录及其等价写法
const ROOT_TARGET_RE = /^\/(\*)?$/
// 系统关键顶级目录
const CRITICAL_DIRS = new Set([
  '/bin', '/sbin', '/lib', '/lib64', '/usr', '/boot', '/dev', '/proc', '/sys', '/etc'
])
// 相对敏感但删除未必致命的目录
const SENSITIVE_DIRS = new Set(['/var', '/root', '/home', '/opt', '/srv', '/data'])
// 承载业务数据的路径前缀：其下的递归删除需要确认
const DATA_DIR_PREFIXES = [
  '/var/lib', '/var/www', '/var/backups', '/var/log', '/var/spool',
  '/etc', '/usr', '/opt', '/srv', '/data', '/home', '/root', '/mnt', '/media'
]

/** 判断递归删除目标是否落在需要确认的数据目录内 */
function isSensitiveTarget(path) {
  if (SENSITIVE_DIRS.has(path)) return true
  return DATA_DIR_PREFIXES.some((prefix) => path === prefix || path.startsWith(`${ prefix }/`))
}
// 凭据文件
const CREDENTIAL_FILES = [
  /\/\.ssh\/id_/, /\/\.ssh\/authorized_keys$/, /\.pem$/, /\.key$/,
  /\/\.env$/, /\/\.pgpass$/, /\/\.my\.cnf$/, /\/\.aws\/credentials$/
]
// SSH 服务单元名
const SSH_UNITS = /^(sshd?|sshd\.service|ssh\.service|ssh\.socket)$/
// 解释器
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh', 'ash', 'fish', 'python', 'python3', 'perl', 'ruby', 'node'])
const COMMAND_SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh', 'ash', 'fish'])
const INTERPRETER_INFO_FLAGS = {
  node: new Set(['-v', '--version', '-h', '--help']),
  python: new Set(['-V', '--version', '-h', '--help']),
  python3: new Set(['-V', '--version', '-h', '--help']),
  perl: new Set(['-v', '--version', '-h', '--help']),
  ruby: new Set(['-v', '--version', '-h', '--help']),
  bash: new Set(['--version', '--help']),
  zsh: new Set(['--version', '--help']),
  fish: new Set(['--version', '--help'])
}
const CLI_INFO_FLAGS = {
  npm: new Set(['-v', '--version', '-h', '--help']),
  git: new Set(['--version', '-h', '--help'])
}
// 下载器
const FETCHERS = new Set(['curl', 'wget', 'fetch', 'aria2c'])
const SQL_CLIENTS = new Set(['mysql', 'mariadb', 'psql', 'sqlite3'])
// 读取类命令
const READERS = new Set(['cat', 'less', 'more', 'head', 'tail', 'bat', 'nl', 'od', 'xxd', 'strings'])
const FILE_READERS = new Set([
  ...READERS,
  'grep', 'egrep', 'fgrep', 'rg', 'awk', 'sed', 'cut', 'sort', 'uniq', 'wc'
])
// 不带写入选项、子命令或执行钩子的命令才可直接视为只读。
// 双用途命令必须走下方参数级校验，不能仅凭命令名放行。
const ALWAYS_READ_ONLY_CMDS = new Set([
  'cat', 'head', 'tail', 'nl', 'od', 'strings',
  'ls', 'stat', 'du', 'df', 'grep', 'egrep', 'fgrep', 'wc',
  'readlink', 'realpath', 'pwd', 'which', 'whereis', 'echo', 'printf', 'test',
  'cd',
  'ps', 'free', 'uptime', 'uname', 'whoami', 'id', 'printenv',
  'md5sum', 'sha256sum', 'cut', 'tr', 'jq'
])

const RECURSIVE_FLAGS = ['-r', '-R', '--recursive']
const FORCE_FLAGS = ['-f', '--force']

function hasAny(flags, candidates) {
  return candidates.some((flag) => flags.has(flag))
}

function isRootTarget(value) {
  return ROOT_TARGET_RE.test(value)
}

function matchesAny(value, patterns) {
  return patterns.some((pattern) => pattern.test(value))
}

/** 归一化路径：去掉尾部斜杠，展开 ~ 之外不做真实解析 */
function normalizePath(value) {
  if (typeof value !== 'string') return ''
  if (value.length > 1 && value.endsWith('/')) return value.replace(/\/+$/, '')
  return value
}

const DELETE_ACTIONS = new Set(['delete', 'prune', 'down'])
const DOCKER_RESOURCE_GROUPS = new Set(['container', 'image', 'volume', 'network', 'system', 'builder'])
const COMPOSE_ACTIONS = new Set([
  'build', 'config', 'create', 'down', 'exec', 'images', 'kill', 'logs', 'pause', 'ps',
  'pull', 'push', 'restart', 'rm', 'run', 'start', 'stop', 'top', 'unpause', 'up'
])
const PACKAGE_MANAGERS = new Set(['apt', 'apt-get', 'yum', 'dnf', 'zypper', 'rpm', 'dpkg', 'apk', 'pacman'])
const PACKAGE_REMOVE_ACTIONS = new Set(['remove', 'purge', 'erase', 'autoremove', 'uninstall', 'del'])

function optionValue(args, shortName, longName) {
  const inline = args.find((arg) => arg.startsWith(`${ longName }=`))
  if (inline) return inline.slice(longName.length + 1)
  const index = args.findIndex((arg) => arg === shortName || arg === longName)
  return index === -1 ? '' : String(args[index + 1] || '')
}

function lifecycleOperation(ctx) {
  const normalizeAction = (action) => action === 'rm' ? 'delete' : action
  const composeOperation = (positionals) => {
    const actionIndex = positionals.findIndex((item) => COMPOSE_ACTIONS.has(item))
    if (actionIndex === -1) return null
    const project = optionValue(ctx.args, '-p', '--project-name')
    return {
      action: normalizeAction(positionals[actionIndex]),
      targets: [...(project ? [project] : []), ...positionals.slice(actionIndex + 1)]
    }
  }

  if (ctx.cmd === 'docker' || ctx.cmd === 'podman') {
    const [resource, action] = ctx.positionals
    if (resource === 'compose') return composeOperation(ctx.positionals.slice(1))
    if (DOCKER_RESOURCE_GROUPS.has(resource)) {
      return { action: normalizeAction(action), targets: ctx.positionals.slice(2) }
    }
    return { action: normalizeAction(resource), targets: ctx.positionals.slice(1) }
  }
  if (ctx.cmd === 'docker-compose') return composeOperation(ctx.positionals)
  if (ctx.cmd === 'systemctl' || ctx.cmd === 'pm2') {
    return { action: normalizeAction(ctx.positionals[0]), targets: ctx.positionals.slice(1) }
  }
  if (ctx.cmd === 'service' || ctx.cmd === 'rc-service') {
    return { action: normalizeAction(ctx.positionals[1]), targets: ctx.positionals.slice(0, 1) }
  }
  if (['kill', 'pkill', 'killall'].includes(ctx.cmd)) {
    return { action: 'kill', targets: ctx.positionals }
  }
  return null
}

function isPackageRemoval(ctx) {
  if (!PACKAGE_MANAGERS.has(ctx.cmd)) return false
  return ctx.positionals.some((arg) => PACKAGE_REMOVE_ACTIONS.has(arg))
    || hasAny(ctx.flags, ['-e', '-R', '--remove', '--purge'])
}

function isInfoQuery(ctx, flagsByCommand) {
  return ctx.args.length === 1
    && Boolean(flagsByCommand[ctx.cmd]?.has(ctx.args[0]))
}

/** 解释器的版本/帮助查询不会执行用户代码，可按普通静态命令判定。 */
function isInterpreterInfoQuery(ctx) {
  return isInfoQuery(ctx, INTERPRETER_INFO_FLAGS)
}

/**
 * 单段命令规则表
 *
 * 每条规则接收 ctx：
 *   { cmd, path, args, flags:Set, positionals:[], redirects, dynamic, raw, argv, joined }
 */
const SEGMENT_RULES = [
  // ---------- 文件变更目标 ----------
  {
    id: 'protected-file-mutation',
    level: Risk.HIGH,
    category: '系统文件保护',
    reason: '该操作会直接破坏账号、提权或启动所依赖的核心系统文件',
    test: (ctx) => classifyFileMutations(ctx).protected.length > 0
  },
  {
    id: 'critical-tree-mutation',
    level: Risk.DENY,
    category: '系统目录保护',
    reason: '该操作会删除或移走系统关键目录树',
    test: (ctx) => classifyFileMutations(ctx).catastrophic.length > 0
  },
  {
    id: 'sensitive-path-mutation',
    level: Risk.HIGH,
    category: '敏感路径变更',
    reason: '该操作会修改系统配置或业务数据路径，请确认',
    test: (ctx) => classifyFileMutations(ctx).sensitive.length > 0
  },
  {
    id: 'unresolved-file-mutation',
    level: Risk.HIGH,
    category: '文件变更',
    reason: '文件变更目标包含路径穿越，无法可靠确定实际位置',
    test: (ctx) => classifyFileMutations(ctx).unresolved.length > 0
  },

  // ---------- 存储销毁 ----------
  {
    id: 'mkfs',
    level: Risk.DENY,
    category: '存储销毁',
    reason: '格式化文件系统会销毁磁盘上的全部数据',
    test: (ctx) => /^mkfs(\.|$)/.test(ctx.cmd) || ctx.cmd === 'mke2fs' || ctx.cmd === 'wipefs'
  },
  {
    id: 'dd',
    level: Risk.DENY,
    category: '存储销毁',
    reason: 'Agent 永不执行 dd 命令，请由用户在终端中自行操作',
    test: (ctx) => ctx.cmd === 'dd'
  },
  {
    id: 'shred-device',
    level: Risk.DENY,
    category: '存储销毁',
    reason: 'shred 作用于块设备会不可恢复地擦除数据',
    test: (ctx) => ctx.cmd === 'shred' && ctx.positionals.some((arg) => BLOCK_DEVICE_RE.test(arg))
  },
  {
    id: 'redirect-to-device',
    level: Risk.DENY,
    category: '存储销毁',
    reason: '重定向写入块设备会破坏磁盘数据',
    test: (ctx) => ctx.redirects.some((item) => BLOCK_DEVICE_RE.test(item.target))
  },
  {
    id: 'copy-to-device',
    level: Risk.DENY,
    category: '存储销毁',
    reason: '复制或写入块设备会覆盖分区表与数据',
    test: (ctx) => ['cp', 'mv', 'install', 'tee'].includes(ctx.cmd)
      && ctx.positionals.some((arg) => BLOCK_DEVICE_RE.test(arg))
  },
  {
    id: 'partition-tools',
    level: Risk.HIGH,
    category: '存储管理',
    reason: '分区与卷管理操作可能导致数据不可访问',
    test: (ctx) => ['fdisk', 'sfdisk', 'parted', 'lvremove', 'vgremove', 'pvremove', 'cfdisk'].includes(ctx.cmd)
  },

  // ---------- 根目录破坏 ----------
  {
    id: 'rm-root',
    level: Risk.DENY,
    category: '根目录破坏',
    reason: '递归删除根目录会彻底摧毁系统',
    test: (ctx) => {
      if (ctx.cmd !== 'rm') return false
      if (!hasAny(ctx.flags, RECURSIVE_FLAGS)) return false
      return ctx.positionals.some((arg) => isRootTarget(normalizePath(arg)))
    }
  },
  {
    id: 'rm-critical-dir',
    level: Risk.DENY,
    category: '根目录破坏',
    reason: '递归删除系统关键目录会导致系统无法启动',
    test: (ctx) => {
      if (ctx.cmd !== 'rm') return false
      if (!hasAny(ctx.flags, RECURSIVE_FLAGS)) return false
      return ctx.positionals.some((arg) => {
        const path = normalizePath(arg).replace(/\/\*$/, '')
        return CRITICAL_DIRS.has(path)
      })
    }
  },
  {
    id: 'rm-sensitive-dir',
    level: Risk.HIGH,
    category: '数据删除',
    reason: '递归删除该目录可能造成数据或服务丢失',
    test: (ctx) => {
      if (ctx.cmd !== 'rm') return false
      if (!hasAny(ctx.flags, RECURSIVE_FLAGS)) return false
      return ctx.positionals.some((arg) => isSensitiveTarget(normalizePath(arg).replace(/\/\*$/, '')))
    }
  },
  {
    id: 'forced-or-bulk-file-delete',
    level: Risk.HIGH,
    category: '数据删除',
    reason: '单次、递归、批量文件删除的影响较大，请确认',
    test: (ctx) => (ctx.cmd === 'rm' && hasAny(ctx.flags, [...RECURSIVE_FLAGS, ...FORCE_FLAGS]))
      || extractFileMutations(ctx).some((mutation) => mutation.action === 'bulk-delete')
  },
  {
    id: 'mv-root',
    level: Risk.DENY,
    category: '根目录破坏',
    reason: '移动根目录内容等同于摧毁系统',
    test: (ctx) => ctx.cmd === 'mv' && ctx.positionals.slice(0, -1).some((arg) => isRootTarget(normalizePath(arg)))
  },
  {
    id: 'find-delete-root',
    level: Risk.DENY,
    category: '根目录破坏',
    reason: '从根目录开始批量删除会摧毁系统',
    test: (ctx) => ctx.cmd === 'find'
      && ctx.positionals.some((arg) => isRootTarget(normalizePath(arg)))
      && (ctx.flags.has('-delete') || ctx.args.includes('-delete') || /-exec\s*rm/.test(ctx.joined))
  },
  {
    id: 'find-exec',
    level: Risk.HIGH,
    category: '间接执行',
    reason: 'find 会对匹配到的多个路径执行子命令，请确认',
    test: (ctx) => ctx.cmd === 'find'
      && ctx.args.some((arg) => ['-exec', '-execdir', '-ok', '-okdir'].includes(arg))
  },

  // ---------- 自断连接 ----------
  {
    id: 'stop-ssh',
    level: Risk.HIGH,
    category: '自断连接',
    reason: '停止 SSH 服务会导致失去对该主机的全部远程访问',
    test: (ctx) => {
      if (ctx.cmd === 'systemctl') {
        const action = ctx.positionals[0]
        if (!['stop', 'disable', 'mask', 'kill', 'restart', 'reload'].includes(action)) return false
        return ctx.positionals.slice(1).some((unit) => SSH_UNITS.test(unit))
      }
      if (ctx.cmd === 'service') {
        return SSH_UNITS.test(ctx.positionals[0] || '')
          && ['stop', 'disable', 'restart', 'reload'].includes(ctx.positionals[1])
      }
      if (ctx.cmd === 'rc-service') {
        return SSH_UNITS.test(ctx.positionals[0] || '')
          && ['stop', 'restart', 'reload'].includes(ctx.positionals[1])
      }
      return false
    }
  },
  {
    id: 'flush-firewall',
    level: Risk.HIGH,
    category: '自断连接',
    reason: '清空防火墙规则可能立即中断当前连接',
    test: (ctx) => ['iptables', 'ip6tables', 'nft'].includes(ctx.cmd)
      && (ctx.flags.has('-F') || ctx.flags.has('--flush') || /flush\s+ruleset/.test(ctx.joined))
  },
  {
    id: 'iface-down',
    level: Risk.HIGH,
    category: '自断连接',
    reason: '关闭网卡会立即断开远程连接且无法自行恢复',
    test: (ctx) => {
      if (ctx.cmd === 'ip') {
        return ctx.positionals[0] === 'link' && ctx.positionals[1] === 'set' && ctx.positionals.includes('down')
      }
      if (ctx.cmd === 'ifconfig') return ctx.positionals.includes('down')
      return ctx.cmd === 'ifdown'
    }
  },
  {
    id: 'firewall-panic',
    level: Risk.HIGH,
    category: '自断连接',
    reason: 'panic 模式会丢弃所有网络包，立即失联',
    test: (ctx) => ctx.cmd === 'firewall-cmd' && ctx.flags.has('--panic-on')
  },
  {
    id: 'firewall-change',
    level: Risk.HIGH,
    category: '网络配置',
    reason: '防火墙规则变更有失联风险，需确认放行 SSH 端口',
    test: (ctx) => ['ufw', 'firewall-cmd', 'iptables', 'ip6tables', 'nft'].includes(ctx.cmd)
  },
  // ---------- 系统可用性 ----------
  {
    id: 'power-off',
    level: Risk.HIGH,
    category: '系统可用性',
    reason: '关机或重启会中断服务，且远程无法自行恢复',
    test: (ctx) => {
      if (['shutdown', 'poweroff', 'halt', 'reboot'].includes(ctx.cmd)) return true
      if (ctx.cmd === 'systemctl') {
        return ['poweroff', 'reboot', 'halt', 'kexec', 'emergency', 'rescue'].includes(ctx.positionals[0])
      }
      if (ctx.cmd === 'init' || ctx.cmd === 'telinit') return ['0', '6'].includes(ctx.positionals[0])
      return false
    }
  },
  {
    id: 'fork-bomb',
    level: Risk.DENY,
    category: '系统可用性',
    reason: '进程炸弹会耗尽系统资源',
    test: (ctx) => /^\s*:\s*\(\s*\)\s*\{.*\|.*&.*\}\s*;\s*:/.test(ctx.rawLine)
      || /^\s*while\s+true\s*;?\s*do\s*.*&\s*done/.test(ctx.rawLine)
  },

  // ---------- 权限账号 ----------
  {
    id: 'chmod-critical-tree',
    level: Risk.DENY,
    category: '权限账号',
    reason: '递归锁死或完全放开系统关键目录权限会让系统失效或无法安全修复',
    test: (ctx) => ctx.cmd === 'chmod'
      && hasAny(ctx.flags, RECURSIVE_FLAGS)
      && ctx.positionals.some((arg) => /^(?:0{3,4}|7{3,4})$/.test(arg))
      && ctx.positionals.some((arg) => isRootTarget(normalizePath(arg)) || CRITICAL_DIRS.has(normalizePath(arg)))
  },
  {
    id: 'remove-sudoers',
    level: Risk.HIGH,
    category: '权限账号',
    reason: '删除 sudoers 会导致所有提权操作失效',
    test: (ctx) => ctx.cmd === 'rm' && ctx.positionals.some((arg) => /^\/etc\/sudoers/.test(normalizePath(arg)))
  },
  {
    id: 'account-change',
    level: Risk.HIGH,
    category: '权限账号',
    reason: '账号或提权配置变更可能导致失去登录能力',
    test: (ctx) => ['userdel', 'usermod', 'groupdel', 'visudo', 'chpasswd'].includes(ctx.cmd)
      || (ctx.cmd === 'passwd' && ctx.positionals.length > 0)
  },
  {
    id: 'chown-top-level',
    level: Risk.HIGH,
    category: '权限账号',
    reason: '递归修改系统目录归属会破坏服务运行',
    test: (ctx) => ['chown', 'chgrp'].includes(ctx.cmd)
      && hasAny(ctx.flags, RECURSIVE_FLAGS)
      && ctx.positionals.some((arg) => {
        const path = normalizePath(arg)
        return isRootTarget(path) || CRITICAL_DIRS.has(path) || SENSITIVE_DIRS.has(path)
      })
  },

  // ---------- 包管理 ----------
  {
    id: 'remove-core-package',
    level: Risk.HIGH,
    category: '包管理',
    reason: '卸载该核心组件会导致系统或远程访问不可用',
    test: (ctx) => {
      if (!isPackageRemoval(ctx)) return false
      return /\b(openssh-server|openssh|glibc|libc6|systemd|coreutils|bash|kernel|linux-image)\b/.test(ctx.joined)
    }
  },
  {
    id: 'package-removal',
    level: Risk.HIGH,
    category: '包管理',
    reason: '卸载软件包可能影响依赖它的服务',
    test: (ctx) => isPackageRemoval(ctx) || (PACKAGE_MANAGERS.has(ctx.cmd)
      && hasAny(ctx.flags, ['--force-all', '--nodeps']))
  },

  // ---------- 数据销毁 ----------
  {
    id: 'redis-flush',
    level: Risk.HIGH,
    category: '数据销毁',
    reason: '清空 Redis 会丢失全部缓存与持久化数据',
    test: (ctx) => ctx.cmd === 'redis-cli' && /\bflush(all|db)\b/i.test(ctx.joined)
  },
  {
    id: 'drop-database',
    level: Risk.HIGH,
    category: '数据销毁',
    reason: '删除数据库会造成不可恢复的数据丢失',
    test: (ctx) => SQL_CLIENTS.has(ctx.cmd) && /\bdrop\s+(database|schema)\b/i.test(ctx.joined)
  },
  {
    id: 'sql-truncate',
    level: Risk.HIGH,
    category: '数据销毁',
    reason: '清空表数据不可撤销',
    test: (ctx) => SQL_CLIENTS.has(ctx.cmd)
      && /\b(truncate\s+table|delete\s+from)\b/i.test(ctx.joined)
  },

  // ---------- 容器批量 ----------
  {
    id: 'docker-wipe-all',
    level: Risk.HIGH,
    category: '容器批量',
    reason: '批量删除全部容器/镜像/卷会摧毁该主机上的所有服务与数据',
    test: (ctx) => {
      if (!['docker', 'podman'].includes(ctx.cmd)) return false
      const isPrune = ctx.positionals.includes('prune')
      if (isPrune && (ctx.flags.has('-a') || ctx.flags.has('--all')) && ctx.flags.has('--volumes')) return true
      // 仅当销毁类子命令的参数里嵌套了"列出全部容器/镜像"的子 shell 时才拦截，
      // 否则 `docker ps -a` 这类只读命令会被误杀
      if (!['rm', 'rmi', 'stop', 'kill', 'restart'].includes(ctx.positionals[0])) return false
      return /\$\(\s*(docker|podman)\s+(ps|images)\b[^)]*-[a-z]*q/.test(ctx.joined)
    }
  },
  {
    id: 'k8s-delete-namespace',
    level: Risk.HIGH,
    category: '容器批量',
    reason: '删除命名空间或持久化存储会造成工作负载或数据丢失',
    test: (ctx) => ctx.cmd === 'kubectl'
      && ctx.positionals[0] === 'delete'
      && (/^(ns|namespace|namespaces|pv|persistentvolumes?|pvc|persistentvolumeclaims?)$/.test(
        ctx.positionals[1] || ''
      ) || ctx.flags.has('--all'))
  },
  {
    id: 'container-remove',
    level: Risk.HIGH,
    category: '容器',
    reason: '强制删除容器或镜像可能中断服务并丢失未持久化的数据',
    test: (ctx) => ['docker', 'podman', 'docker-compose'].includes(ctx.cmd)
      && lifecycleOperation(ctx)?.action === 'delete'
      && hasAny(ctx.flags, FORCE_FLAGS)
  },
  {
    id: 'container-prune',
    level: Risk.HIGH,
    category: '容器批量',
    reason: '批量清理容器资源可能删除仍有用途的数据',
    test: (ctx) => ['docker', 'podman'].includes(ctx.cmd)
      && lifecycleOperation(ctx)?.action === 'prune'
  },
  {
    id: 'docker-volume-remove',
    level: Risk.HIGH,
    category: '容器',
    reason: '删除数据卷会造成持久化数据丢失',
    test: (ctx) => {
      if (!['docker', 'podman', 'docker-compose'].includes(ctx.cmd)) return false
      if (ctx.positionals[0] === 'volume' && ['rm', 'prune'].includes(ctx.positionals[1])) return true
      return ['delete', 'down'].includes(lifecycleOperation(ctx)?.action)
        && hasAny(ctx.flags, ['-v', '--volumes'])
    }
  },

  // ---------- 痕迹清除 ----------
  {
    id: 'clear-history',
    level: Risk.HIGH,
    category: '痕迹清除',
    reason: '清除操作记录会影响事后审计',
    test: (ctx) => (ctx.cmd === 'history' && ctx.flags.has('-c'))
      || (ctx.cmd === 'journalctl' && /--vacuum-(time|size)=(0|1s)/.test(ctx.joined))
      || ctx.redirects.some((item) => /^\/var\/log\//.test(item.target))
  },

  // ---------- 动态执行 ----------
  {
    id: 'eval-usage',
    level: Risk.HIGH,
    category: '动态构造',
    reason: 'eval 会执行拼接出的字符串，实际行为难以静态确认',
    test: (ctx) => ctx.cmd === 'eval'
  },
  {
    id: 'interpreter-code',
    level: Risk.HIGH,
    category: '间接执行',
    reason: '包含解释器代码，Shell 规则无法完整判断其行为',
    test: (ctx) => SHELLS.has(ctx.cmd)
      && !isInterpreterInfoQuery(ctx)
      && !(COMMAND_SHELLS.has(ctx.cmd) && extractNestedPayloads(ctx).length > 0)
  },

  // ---------- 数据外传 ----------
  {
    id: 'network-file-upload',
    level: Risk.HIGH,
    category: '数据外传',
    reason: '命令会把本地文件或标准输入发送到外部地址',
    test: (ctx) => {
      if (ctx.cmd === 'curl') {
        return ctx.args.some((arg, index) => {
          if (/^(?:-T|--upload-file)(?:=|$)/.test(arg)) return true
          if (/^(?:-d|--data|--data-binary|--data-raw|--data-urlencode)(?:=|$)/.test(arg)) {
            return arg.includes('@') || String(ctx.args[index + 1] || '').startsWith('@')
          }
          return /^(?:-F|--form)(?:=|$)/.test(arg)
            && (arg.includes('@') || String(ctx.args[index + 1] || '').includes('@'))
        })
      }
      if (ctx.cmd === 'wget') {
        return ctx.args.some((arg) => /^--post-file(?:=|$)/.test(arg))
      }
      if (['scp', 'sftp', 'rsync'].includes(ctx.cmd)) return true
      return ['nc', 'ncat', 'netcat', 'socat'].includes(ctx.cmd)
        && ctx.redirects.some((item) => item.op === '<' && !item.duplicate)
    }
  },
  {
    id: 'blocked-file-egress',
    level: Risk.DENY,
    category: '凭据外泄',
    reason: '禁止把核心凭据文件发送到外部地址',
    test: (ctx) => {
      const candidates = [
        ...ctx.positionals,
        ...ctx.args.flatMap((arg) => {
          const values = [arg]
          const at = arg.indexOf('@')
          if (at !== -1) values.push(arg.slice(at + 1))
          const equal = arg.indexOf('=')
          if (equal !== -1) values.push(arg.slice(equal + 1).replace(/^@/, ''))
          return values
        }),
        ...ctx.redirects.map((item) => item.target)
      ]
      const hasBlocked = candidates.some((item) => classifyReadPath(item).core)
      if (!hasBlocked) return false
      return ['curl', 'wget', 'scp', 'sftp', 'rsync', 'nc', 'ncat', 'netcat', 'socat'].includes(ctx.cmd)
    }
  },

  // ---------- 凭据读取 ----------
  {
    id: 'read-blocked-credentials',
    level: Risk.HIGH,
    category: '敏感读取',
    reason: '读取核心认证材料会把真实内容发送给当前 AI Provider',
    test: (ctx) => FILE_READERS.has(ctx.cmd)
      && ctx.positionals.some((arg) => classifyReadPath(arg).core)
  },
  {
    id: 'read-credentials',
    level: Risk.HIGH,
    category: '凭据外泄',
    reason: '读取凭据文件，内容可能被发送至第三方模型服务',
    test: (ctx) => FILE_READERS.has(ctx.cmd) && ctx.positionals.some((arg) => (
      classifyReadPath(arg).risk === DataRisk.HIGH || matchesAny(arg, CREDENTIAL_FILES)
    ))
  }
]

/**
 * 跨段规则：作用于整条管道/命令链
 */
const PIPELINE_RULES = [
  {
    id: 'blocked-credential-pipeline-egress',
    level: Risk.DENY,
    category: '凭据外泄',
    reason: '禁止通过管道把核心凭据发送到外部地址',
    test: (segments) => {
      for (let index = 0; index < segments.length; index += 1) {
        const readsBlocked = FILE_READERS.has(segments[index].ctx.cmd)
          && segments[index].ctx.positionals.some((item) => classifyReadPath(item).core)
        if (!readsBlocked) continue
        for (let next = index + 1; next < segments.length && segments[next].connector === '|'; next += 1) {
          if (consumesPipedInputForEgress(segments[next].ctx)) return true
        }
      }
      return false
    }
  },
  {
    id: 'curl-pipe-shell',
    level: Risk.HIGH,
    category: '供应链',
    reason: '下载内容直接交给解释器执行，无法审计将要运行的代码',
    test: (segments) => segments.some((segment, index) => {
      if (!FETCHERS.has(segment.ctx.cmd)) return false
      const next = segments[index + 1]
      return next?.connector === '|' && SHELLS.has(next.ctx.cmd)
    })
  },
  {
    id: 'base64-pipe-shell',
    level: Risk.DENY,
    category: '供应链',
    reason: '解码后直接执行，属于典型的载荷隐藏手法',
    test: (segments) => segments.some((segment, index) => {
      if (segment.ctx.cmd !== 'base64') return false
      const next = segments[index + 1]
      return next?.connector === '|' && SHELLS.has(next.ctx.cmd)
    })
  },
  {
    id: 'process-substitution-exec',
    level: Risk.HIGH,
    category: '供应链',
    reason: '通过进程替换执行远程脚本，无法审计其内容',
    test: (segments) => segments.some((segment) => SHELLS.has(segment.ctx.cmd)
      && /<\(\s*(curl|wget)/.test(segment.ctx.joined))
  },
  {
    id: 'remote-script-exec',
    level: Risk.HIGH,
    category: '供应链',
    reason: '从网络下载并执行脚本，需确认来源可信',
    test: (segments) => segments.some((segment) => FETCHERS.has(segment.ctx.cmd))
      && segments.some((segment) => SHELLS.has(segment.ctx.cmd))
  }
]

function buildSegmentContext(segment, rawLine) {
  const { cmd, path, args, wrappers } = unwrapCommand(segment.argv)
  const flags = expandFlags(args)
  return {
    cmd,
    path,
    args,
    wrappers,
    flags,
    positionals: positionalArgs(args),
    redirects: segment.redirects,
    dynamic: segment.dynamic,
    argv: segment.argv,
    joined: segment.argv.join(' '),
    rawLine
  }
}

function riskMax(a, b) {
  return RISK_ORDER[a] >= RISK_ORDER[b] ? a : b
}

function effectMax(a, b) {
  return EFFECT_ORDER[a] >= EFFECT_ORDER[b] ? a : b
}

function hasOption(ctx, options) {
  return hasAny(ctx.flags, options)
    || ctx.args.some((arg) => options.some((option) => (
      option.startsWith('--') && arg.startsWith(`${ option }=`)
    )))
}

function isReadOnlyFile(ctx) {
  return !hasOption(ctx, ['-C', '--compile'])
}

function isReadOnlyRipgrep(ctx) {
  return !ctx.args.some((arg) => (
    ['--pre', '--hostname-bin'].includes(arg)
    || arg.startsWith('--pre=')
    || arg.startsWith('--hostname-bin=')
  ))
}

function isReadOnlySort(ctx) {
  return !hasOption(ctx, ['-o', '--output', '--compress-program'])
}

function isReadOnlyUniq(ctx) {
  // uniq 的第二个位置参数是输出文件，而不是另一个输入文件。
  return ctx.positionals.length <= 1
}

function isReadOnlyXxd(ctx) {
  // xxd 无论是否使用 -r，第二个位置参数都会作为输出文件。
  return ctx.positionals.length <= 1
}

function isReadOnlyDiff(ctx) {
  return !hasOption(ctx, ['--output'])
}

function isReadOnlyDate(ctx) {
  if (hasOption(ctx, ['-s', '--set'])) return false
  // GNU/BSD date 都支持用纯数字位置参数设置系统时间。
  return !ctx.positionals.some((arg) => /^\d{4,14}(?:\.\d+)?$/.test(arg))
}

function isReadOnlyFind(ctx) {
  const mutationActions = new Set([
    '-delete', '-exec', '-execdir', '-ok', '-okdir',
    '-fprint', '-fprint0', '-fprintf', '-fls'
  ])
  return !ctx.args.some((arg) => mutationActions.has(arg))
}

function isReadOnlyGit(ctx) {
  const [action = '', ...rest] = ctx.positionals
  if (hasOption(ctx, ['--ext-diff', '--textconv'])) return false
  if (['status', 'log', 'show', 'rev-parse'].includes(action)) return true
  if (action === 'diff') {
    return !hasOption(ctx, ['--output'])
  }
  if (action === 'branch') {
    if (hasOption(ctx, [
      '-d', '-D', '-m', '-M', '-c', '-C', '--delete', '--move', '--copy',
      '--edit-description', '--set-upstream-to', '--unset-upstream', '--track', '--no-track'
    ])) return false
    if (rest.length === 0) return true
    return hasOption(ctx, [
      '-l', '--list', '--contains', '--no-contains', '--merged', '--no-merged', '--points-at'
    ])
  }
  if (action === 'remote') {
    if (rest.length === 0) return true
    return ['get-url', 'show'].includes(rest[0])
  }
  return false
}

const CURL_READ_ONLY_FLAGS = new Set([
  '--head', '--include', '--silent', '--show-error', '--location', '--fail',
  '--fail-with-body', '--compressed', '--insecure', '--verbose', '--ipv4', '--ipv6',
  '--http1.0', '--http1.1', '--http2', '--http2-prior-knowledge', '--http3',
  '--no-progress-meter', '--globoff', '--help', '--version'
])
const CURL_READ_ONLY_VALUE_OPTIONS = new Set([
  '-A', '--user-agent', '-e', '--referer', '-u', '--user', '--url',
  '--connect-timeout', '-m', '--max-time', '--retry', '--retry-delay',
  '--resolve', '--connect-to', '-x', '--proxy', '--proxy-user', '-b', '--cookie',
  '--cacert', '--capath', '--cert', '--key', '-r', '--range'
])

function isReadOnlyCurl(ctx) {
  for (let index = 0; index < ctx.args.length; index += 1) {
    const arg = ctx.args[index]
    if (arg === '--') return true
    if (!arg.startsWith('-') || arg === '-') continue
    if (/^-[46fgIiIkLqNsSv]+$/.test(arg)) continue
    if (CURL_READ_ONLY_FLAGS.has(arg)) continue

    if (arg === '-X' || arg === '--request') {
      const method = String(ctx.args[index + 1] || '').toUpperCase()
      if (!['GET', 'HEAD', 'OPTIONS'].includes(method)) return false
      index += 1
      continue
    }
    const inlineMethod = /^(?:-X|--request=)(.+)$/.exec(arg)
    if (inlineMethod) {
      if (!['GET', 'HEAD', 'OPTIONS'].includes(inlineMethod[1].toUpperCase())) return false
      continue
    }

    const option = arg.startsWith('--') ? arg.split('=')[0] : arg
    if (!CURL_READ_ONLY_VALUE_OPTIONS.has(option)) return false
    if (!arg.includes('=')) index += 1
  }
  return true
}

function isReadOnlyCrontab(ctx) {
  let hasList = false
  let hasUser = false
  for (let index = 0; index < ctx.args.length; index += 1) {
    const arg = ctx.args[index]
    if (arg === '-l' && !hasList) {
      hasList = true
      continue
    }
    if (arg === '-u' && !hasUser) {
      const user = ctx.args[index + 1]
      if (!user || user.startsWith('-')) return false
      hasUser = true
      index += 1
      continue
    }
    return false
  }
  return hasList
}

function isReadOnlyJournalctl(ctx) {
  return !ctx.args.some((arg) => (
    /^--vacuum-(?:size|time|files)(?:=|$)/.test(arg)
    || [
      '--rotate', '--flush', '--sync', '--relinquish-var', '--smart-relinquish-var',
      '--update-catalog', '--setup-keys'
    ].includes(arg)
  ))
}

function isReadOnlyDmesg(ctx) {
  return !hasOption(ctx, [
    '-c', '-C', '-D', '-E', '-n', '--read-clear', '--clear',
    '--console-off', '--console-on', '--console-level'
  ])
}

function isReadOnlySs(ctx) {
  return !hasOption(ctx, ['-K', '--kill'])
}

const READ_ONLY_VALIDATORS = {
  file: isReadOnlyFile,
  rg: isReadOnlyRipgrep,
  sort: isReadOnlySort,
  uniq: isReadOnlyUniq,
  xxd: isReadOnlyXxd,
  diff: isReadOnlyDiff,
  date: isReadOnlyDate,
  find: isReadOnlyFind,
  git: isReadOnlyGit,
  curl: isReadOnlyCurl,
  crontab: isReadOnlyCrontab,
  journalctl: isReadOnlyJournalctl,
  dmesg: isReadOnlyDmesg,
  ss: isReadOnlySs
}

function isReadOnlySegment(ctx) {
  if (ctx.dynamic) return false
  if (ctx.redirects?.some((redirect) => !redirect.duplicate && redirect.target !== '/dev/null')) return false
  if (isInterpreterInfoQuery(ctx) || isInfoQuery(ctx, CLI_INFO_FLAGS)) return true
  if (ALWAYS_READ_ONLY_CMDS.has(ctx.cmd)) return true
  if (READ_ONLY_VALIDATORS[ctx.cmd]) return READ_ONLY_VALIDATORS[ctx.cmd](ctx)

  const action = ctx.positionals[0] || ''
  if (ctx.cmd === 'systemctl') {
    return ['status', 'is-active', 'is-enabled', 'is-failed', 'show', 'list-units', 'list-unit-files'].includes(action)
  }
  if (ctx.cmd === 'docker' || ctx.cmd === 'podman') {
    if (ctx.positionals[0] === 'config') return ['ls', 'inspect'].includes(ctx.positionals[1])
    const operation = lifecycleOperation(ctx)?.action
    if (operation === 'config') {
      return ctx.positionals[0] === 'compose'
        && !hasOption(ctx, ['-o', '--output', '--lock-image-digests'])
    }
    return ['ps', 'images', 'inspect', 'logs', 'info', 'version', 'top'].includes(operation)
  }
  if (ctx.cmd === 'docker-compose') {
    const operation = lifecycleOperation(ctx)?.action
    if (operation === 'config') {
      return !hasOption(ctx, ['-o', '--output', '--lock-image-digests'])
    }
    return ['ps', 'images', 'logs', 'top'].includes(operation)
  }
  if (ctx.cmd === 'pm2') {
    return ['list', 'status', 'show', 'describe', 'logs'].includes(action)
  }
  if (ctx.cmd === 'apt' || ctx.cmd === 'apt-cache') {
    return ['list', 'show', 'policy', 'search'].includes(action)
  }
  if (ctx.cmd === 'ip') {
    return ['addr', 'address', 'route', 'link', 'neigh'].includes(action)
      && ['show', 'list', 'get'].includes(ctx.positionals[1] || 'show')
  }
  if (ctx.cmd === 'timedatectl') {
    return ['', 'status', 'show', 'timesync-status', 'show-timesync'].includes(action)
  }
  if (ctx.cmd === 'nginx') return ctx.flags.has('-t') || ctx.flags.has('-T')
  return ctx.cmd === 'lsblk'
}

function consumesPipedInputForEgress(ctx) {
  if (['nc', 'ncat', 'netcat', 'socat'].includes(ctx.cmd)) return true
  if (ctx.cmd === 'curl') {
    return ctx.args.some((arg, index) => {
      const next = String(ctx.args[index + 1] || '')
      if (['-T', '--upload-file'].includes(arg)) return next === '-'
      if (/^(?:-T|--upload-file)=/.test(arg)) return arg.endsWith('=-')
      if (['-d', '--data', '--data-binary', '--data-raw', '--data-urlencode', '-F', '--form'].includes(arg)) {
        return next.includes('@-')
      }
      return /^(?:-d|--data|--data-binary|--data-raw|--data-urlencode|-F|--form)=/.test(arg)
        && arg.includes('@-')
    })
  }
  if (ctx.cmd === 'wget') {
    return ctx.args.some((arg, index) => (
      (arg === '--post-file' && ctx.args[index + 1] === '-') || arg === '--post-file=-'
    ))
  }
  return false
}

function hasDeleteSemantics(ctx, mutations) {
  if (mutations.some((item) => ['delete', 'bulk-delete', 'move-source', 'truncate'].includes(item.action))) return true
  if (['userdel', 'groupdel'].includes(ctx.cmd)) return true
  if (SQL_CLIENTS.has(ctx.cmd)
    && /\b(drop\s+(database|schema)|truncate\s+table|delete\s+from)\b/i.test(ctx.joined)) return true
  if (ctx.cmd === 'redis-cli' && /\bflush(all|db)\b/i.test(ctx.joined)) return true
  if (['docker', 'podman', 'docker-compose'].includes(ctx.cmd)) {
    const action = lifecycleOperation(ctx)?.action
    return DELETE_ACTIONS.has(action) || action === 'rmi'
  }
  if (ctx.cmd === 'kubectl' && ctx.positionals[0] === 'delete') return true
  return isPackageRemoval(ctx)
}

function classifySegmentEffect(ctx) {
  const mutations = extractFileMutations(ctx)
  if (hasDeleteSemantics(ctx, mutations)) return Effect.DELETE
  if (ctx.dynamic || ctx.cmd === 'eval') return Effect.WRITE
  if (isInterpreterInfoQuery(ctx)) return Effect.READ
  if (COMMAND_SHELLS.has(ctx.cmd) && extractNestedPayloads(ctx).length > 0) return Effect.READ
  if (SHELLS.has(ctx.cmd)) return Effect.WRITE
  if (isReadOnlySegment(ctx)) return Effect.READ
  return Effect.WRITE
}

function collectTargets(segments) {
  const targets = []
  for (const { ctx } of segments) {
    for (const mutation of extractFileMutations(ctx)) targets.push(mutation.path)
    for (const item of ctx.positionals) {
      if (String(item).startsWith('/')) targets.push(normalizePath(item))
    }
    if (['systemctl', 'service', 'rc-service', 'docker', 'podman', 'docker-compose', 'pm2'].includes(ctx.cmd)) {
      targets.push(...(lifecycleOperation(ctx)?.targets || []))
    }
    if (['userdel', 'groupdel'].includes(ctx.cmd)) targets.push(...ctx.positionals)
    if (ctx.cmd === 'kubectl' && ctx.positionals[0] === 'delete') targets.push(...ctx.positionals.slice(1))
    if (PACKAGE_MANAGERS.has(ctx.cmd)) {
      const removalIndex = ctx.positionals.findIndex((item) => PACKAGE_REMOVE_ACTIONS.has(item))
      if (removalIndex !== -1) targets.push(...ctx.positionals.slice(removalIndex + 1))
      else if (isPackageRemoval(ctx)) targets.push(...ctx.positionals)
    }
  }
  return [...new Set(targets.filter(Boolean))]
}

function collectTraits(segments, hits) {
  const traits = new Set()
  for (const { ctx } of segments) {
    if (hasAny(ctx.flags, RECURSIVE_FLAGS)) traits.add('recursive')
    if (hasAny(ctx.flags, FORCE_FLAGS)) traits.add('force')
    if (ctx.dynamic) traits.add('dynamic')
  }
  for (const hit of hits) {
    if (/dynamic-expansion/.test(hit.id)) traits.add('dynamic')
    if (/sensitive|credential|protected/.test(hit.id)) traits.add('sensitive')
    if (/upload|egress/.test(hit.id)) traits.add('external')
    if (/wipe-all|namespace|bulk|find-delete/.test(hit.id)) traits.add('bulk')
    if (/base64-pipe-shell/.test(hit.id)) traits.add('hidden')
    if (/interpreter|eval|remote-script|process-substitution/.test(hit.id)) traits.add('opaque')
  }
  return [...traits]
}

/**
 * 取出嵌套在参数里的命令负载。
 *
 * `sudo bash -c 'rm -rf /'` 的危险内容是一个字符串参数，逐段规则看到的
 * 只是 cmd=bash，必须把 payload 取出来递归判定，否则等于开了个后门。
 */
function extractNestedPayloads(ctx) {
  const payloads = []

  if (SHELLS.has(ctx.cmd) || ctx.cmd === 'su') {
    for (const flag of ['-c', '--command']) {
      const index = ctx.args.indexOf(flag)
      if (index !== -1 && ctx.args[index + 1]) payloads.push(ctx.args[index + 1])
    }
  }

  if (ctx.cmd === 'eval') {
    payloads.push(ctx.args.join(' '))
  }

  // ssh host '<payload>'：最后一个位置参数是远端命令
  if (ctx.cmd === 'ssh' && ctx.positionals.length > 1) {
    payloads.push(ctx.positionals.slice(1).join(' '))
  }

  // systemd-run 的第一个非选项参数开始是实际执行的命令。
  if (ctx.cmd === 'systemd-run' && ctx.positionals.length) {
    payloads.push(ctx.positionals.join(' '))
  }

  return payloads.filter((item) => typeof item === 'string' && item.trim())
}

/**
 * 判定一条命令的风险级别。
 *
 * @param {string} command 待执行的命令行
 * @returns {{ risk: string, effect: string, reason?: string, targets: string[],
 *             traits: string[], hits: Array<{id,level,category,reason}>, segments: Array }}
 */
function classify(command, depth) {
  const hits = []
  const nestedVerdicts = []

  if (typeof command !== 'string' || !command.trim()) {
    return { risk: Risk.NORMAL, effect: Effect.READ, targets: [], traits: [], hits, segments: [] }
  }

  const parsed = parseCommandLine(command)
  const segments = parsed.map((segment) => ({
    connector: segment.connector,
    ctx: buildSegmentContext(segment, command)
  }))

  // 单段规则
  for (const { ctx } of segments) {
    for (const rule of SEGMENT_RULES) {
      try {
        if (rule.test(ctx)) {
          hits.push({ id: rule.id, level: rule.level, category: rule.category, reason: rule.reason })
        }
      } catch (error) {
        logger?.warn?.(`[ai-safety] 规则 ${ rule.id } 执行异常: ${ error.message }`)
      }
    }
  }

  // 嵌套负载：sh -c / su -c / eval / ssh host '...'
  if (depth < 3) {
    for (const { ctx } of segments) {
      for (const payload of extractNestedPayloads(ctx)) {
        const nested = classify(payload, depth + 1)
        nestedVerdicts.push(nested)
        for (const hit of nested.hits) {
          hits.push({ ...hit, id: `nested:${ hit.id }` })
        }
      }
    }
  }

  // 跨段规则
  for (const rule of PIPELINE_RULES) {
    try {
      if (rule.test(segments)) {
        hits.push({ id: rule.id, level: rule.level, category: rule.category, reason: rule.reason })
      }
    } catch (error) {
      logger?.warn?.(`[ai-safety] 管道规则 ${ rule.id } 执行异常: ${ error.message }`)
    }
  }

  // 含无法静态求值的动态构造：不拒绝，但升级为需确认。
  // 这是三级分类的核心价值：`VAR=$(date)` 不该被拒绝，
  // 但 `rm -rf $DIR` 的实际作用对象在执行前无法确定。
  if (segments.some(({ ctx }) => ctx.dynamic) && !hits.some((hit) => hit.level === Risk.DENY)) {
    hits.push({
      id: 'dynamic-expansion',
      level: Risk.HIGH,
      category: '动态构造',
      reason: '命令包含变量或子 shell，实际执行内容在运行前无法确定'
    })
  }

  const risk = hits.reduce((acc, hit) => riskMax(acc, hit.level), Risk.NORMAL)
  const nestedEffect = nestedVerdicts.reduce(
    (effect, verdict) => effectMax(effect, verdict.effect),
    Effect.READ
  )
  const effect = segments.reduce(
    (current, { ctx }) => effectMax(current, classifySegmentEffect(ctx)),
    nestedEffect
  )
  const primary = primaryReason({ hits })
  const traits = new Set([
    ...collectTraits(segments, hits),
    ...nestedVerdicts.flatMap((verdict) => verdict.traits)
  ])
  return {
    risk,
    effect,
    reason: primary?.reason,
    category: primary?.category,
    targets: collectTargets(segments),
    traits: [...traits],
    hits,
    segments
  }
}

export function classifyCommand(command) {
  return classify(command, 0)
}

/**
 * 便捷判定：是否应直接拒绝执行
 */
export function isDenied(command) {
  return classifyCommand(command).risk === Risk.DENY
}

/**
 * Web 终端 AI 的“自动”档只允许这一小类确定的查询命令直发。
 * normal 风险同时包含读写命令，不能把它直接当成只读依据。
 */
export function isStrictReadOnlyCommand(command) {
  const verdict = classifyCommand(command)
  return verdict.risk === Risk.NORMAL && verdict.effect === Effect.READ && verdict.segments.length > 0
}

/** 取最高优先级的命中原因，用于回给模型和展示给用户 */
export function primaryReason(result) {
  const denied = result.hits.find((hit) => hit.level === Risk.DENY)
  if (denied) return denied
  return result.hits.find((hit) => hit.level === Risk.HIGH) || null
}
