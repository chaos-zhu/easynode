/** Pure tool schemas: importing tool metadata must not initialize databases. */
import { z } from 'zod'

const id = z.string().trim().min(1)
const name = z.string().trim().min(1).max(200)
const command = z.string().min(1).refine(value => value.trim() && Buffer.byteLength(value) <= 256 * 1024, '脚本不能为空或超过 256 KiB')
const scriptFields = { name, description: z.string().max(10000), command, groupId: id, useBase64: z.boolean() }
const batch = schema => z.object({ items: z.array(schema).min(1).max(50) }).strict()
const patch = fields => z.object(fields).partial().strict().refine(value => Object.keys(value).length > 0, '修改内容不能为空')
const hostPatch = patch({
  name, groupId: id, tag: z.array(z.string().trim().min(1).max(200)).max(100),
  tagMode: z.enum(['replace', 'add', 'remove']),
  expired: z.union([z.number().int().nonnegative(), z.string().regex(/^\d+$/)]).nullable(),
  expiredNotify: z.boolean(), consoleUrl: z.union([z.literal(''), z.url().refine(value => /^https?:\/\//i.test(value), '只支持 HTTP(S) URL')])
}).refine(value => !value.tagMode || value.tag !== undefined, 'tagMode 必须配合 tag 使用')

export const PANEL_BATCH_SCHEMAS = {
  host_metadata_batch_update: batch(z.object({ hostId: id, changes: hostPatch }).strict()),
  script_batch_create: batch(z.object({ name, command, description: scriptFields.description.optional(), groupId: id.optional(), useBase64: z.boolean().optional() }).strict()),
  script_batch_update: batch(z.object({ scriptId: id, changes: patch(scriptFields) }).strict()),
  script_batch_delete: batch(z.object({ scriptId: id }).strict()),
  script_group_batch_create: batch(z.object({ name }).strict()),
  script_group_batch_update: batch(z.object({ groupId: id, name }).strict()),
  script_group_batch_delete: batch(z.object({ groupId: id }).strict())
}
