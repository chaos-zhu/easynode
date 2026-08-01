/**
 * 工具元数据表 —— 单一事实来源
 *
 * schema、权限判定、system prompt 全部从这张表派生。三处各写一份
 * 迟早会不一致：模型以为能调的工具其实被权限挡了，或者 prompt 里
 * 描述的参数和 schema 对不上。
 *
 * 字段说明：
 *   effect     —— 固定操作类型
 *   shell      —— 需要按实际命令或脚本内容分类
 *   plusPolicy —— free 免费 / required 始终 Plus / by-effect 按实际效果判定
 *   sensitive  —— 输出可能包含凭据，需要脱敏
 */

import { z } from 'zod'
import { Effect } from '../policy.js'

export const PlusPolicy = {
  FREE: 'free',
  REQUIRED: 'required',
  BY_EFFECT: 'by-effect'
}

export function requiresPlus(spec, effect = spec?.effect) {
  if (!spec) return false
  if (spec.plusPolicy === PlusPolicy.REQUIRED) return true
  return spec.plusPolicy === PlusPolicy.BY_EFFECT && effect !== Effect.READ
}

const hostIdField = z.string().min(1).describe('目标主机 ID，来自 host_list 的返回结果')

export const TOOL_SPECS = [
  {
    name: 'host_list',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    description: '列出本次会话已选择的目标主机，包含 hostId、名称、地址、分组与是否允许 AI 操作。'
      + '只能在这些主机范围内执行后续操作。',
    inputSchema: z.object({
      keyword: z.string().optional().describe('按名称、地址或分组模糊筛选，留空返回全部')
    })
  },
  {
    name: 'host_status',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    description: '获取一台主机的实时运行状态：系统信息、负载、CPU、内存、磁盘、开机时长。'
      + '排查问题时优先用它，比自己拼一堆 shell 命令更省 token。',
    inputSchema: z.object({
      hostId: hostIdField
    })
  },
  {
    name: 'script_list',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    description: '列出 easynode 脚本库中的可用脚本，包含脚本 ID、名称、说明、分组和是否为内置脚本。'
      + '当用户询问有哪些脚本或希望使用既有脚本时，先调用此工具；不要猜测脚本名称或内容。',
    inputSchema: z.object({
      keyword: z.string().optional().describe('按脚本名称、说明或分组模糊筛选，留空返回全部')
    })
  },
  {
    name: 'run_script',
    shell: true,
    plusPolicy: PlusPolicy.BY_EFFECT,
    description: '在指定主机上运行脚本库中已保存的一份脚本。只能按 script_list 返回的 scriptId 原样运行，'
      + '不能自行修改、拼接脚本内容；运行前会按实际脚本内容进行风险分类。',
    inputSchema: z.object({
      hostId: hostIdField,
      scriptId: z.string().min(1).describe('script_list 返回的脚本 ID'),
      timeoutSeconds: z.number().int().min(1).max(1800).optional()
        .describe('超时秒数，默认 60；长时间脚本请显式调大')
    })
  },
  {
    name: 'exec_command',
    shell: true,
    plusPolicy: PlusPolicy.BY_EFFECT,
    description: '在指定主机上执行一条 shell 命令，返回 stdout、stderr 与退出码。'
      + '命令在非交互环境中执行：不要使用 vim / top / less 这类全屏程序，'
      + '包管理等需要确认的命令请自行加 -y。执行前先向用户说明这条命令做什么。',
    inputSchema: z.object({
      hostId: hostIdField,
      command: z.string().min(1).describe('要执行的 shell 命令，单条'),
      cwd: z.string().optional().describe('执行前切换到的工作目录'),
      timeoutSeconds: z.number().int().min(1).max(1800).optional()
        .describe('超时秒数，默认 60。耗时长的任务（编译、大文件传输）请显式调大')
    })
  },
  {
    name: 'read_file',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    sensitive: true,
    description: '通过 SFTP 读取远程文件内容。比 cat 更可靠，不受 shell 转义与输出缓冲影响。',
    inputSchema: z.object({
      hostId: hostIdField,
      path: z.string().min(1).describe('远程文件绝对路径'),
      maxBytes: z.number().int().min(1).max(1024 * 1024).optional()
        .describe('最多读取的字节数，默认 65536')
    })
  },
  {
    name: 'write_file',
    effect: Effect.WRITE,
    plusPolicy: PlusPolicy.REQUIRED,
    description: '通过 SFTP 写入远程文件。默认会先备份原文件。'
      + '修改配置文件时优先用它而不是 sed -i，出错更容易回滚。',
    inputSchema: z.object({
      hostId: hostIdField,
      path: z.string().min(1).describe('远程文件绝对路径'),
      content: z.string().max(256 * 1024).describe('要写入的完整内容，最多 256 KiB'),
      backup: z.boolean().optional().describe('写入前是否创建带时间戳且不覆盖旧文件的 .bak 备份，默认 true'),
      mode: z.string().optional().describe('八进制权限，如 "644"，留空则保持原权限')
    })
  },
  {
    name: 'list_dir',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    description: '列出远程目录内容，含类型、大小、权限与修改时间。',
    inputSchema: z.object({
      hostId: hostIdField,
      path: z.string().min(1).describe('远程目录绝对路径')
    })
  },
  {
    name: 'read_output',
    effect: Effect.READ,
    plusPolicy: PlusPolicy.FREE,
    description: '回读被截断的工具输出。当上一次结果提示了 handle 时，用它查看完整内容，'
      + '可以配合 pattern 只取关心的行，避免把整份日志读进上下文。',
    inputSchema: z.object({
      handle: z.string().min(1).describe('上一次工具结果中给出的 handle'),
      pattern: z.string().optional().describe('只返回匹配该正则的行'),
      offset: z.number().int().min(0).optional().describe('起始字符位置，默认 0'),
      limit: z.number().int().min(1).optional().describe('读取长度，默认 8192')
    })
  },
  {
    // 仅供 Web 终端 AI 使用。它不会由服务端 SSH 执行，而是由已经连接的
    // 浏览器终端接收并执行，所以必须与普通 exec_command 保持两套路径。
    name: 'terminal_command',
    shell: true,
    plusPolicy: PlusPolicy.BY_EFFECT,
    description: '向当前用户已连接的 Web 终端提交一条 shell 命令。只能使用当前会话指定的 hostId。'
      + '命令在同一 PTY 中执行，结果会精确返回本次输出和退出码；持续输出会实时展示。命令必须非交互，systemctl/journalctl 等可能分页的命令须显式使用 --no-pager。',
    inputSchema: z.object({
      hostId: hostIdField,
      command: z.string().min(1).describe('要写入当前 Web 终端并执行的单条命令'),
      explanation: z.string().optional().describe('向用户说明这条命令的用途')
    })
  }
]

export const TOOL_SPEC_MAP = new Map(TOOL_SPECS.map((spec) => [spec.name, spec]))

export function getToolSpec(name) {
  return TOOL_SPEC_MAP.get(name)
}
