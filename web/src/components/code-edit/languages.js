import { javascript } from '@codemirror/lang-javascript'
import { html } from '@codemirror/lang-html'
import { cpp } from '@codemirror/lang-cpp'
import { css } from '@codemirror/lang-css'
import { StreamLanguage } from '@codemirror/language'
import { dockerFile } from '@codemirror/legacy-modes/mode/dockerfile'
import { julia } from '@codemirror/legacy-modes/mode/julia'
import { nginx } from '@codemirror/legacy-modes/mode/nginx'
import { r } from '@codemirror/legacy-modes/mode/r'
import { ruby } from '@codemirror/legacy-modes/mode/ruby'
import { shell } from '@codemirror/legacy-modes/mode/shell'
import { swift } from '@codemirror/legacy-modes/mode/swift'
import { vb } from '@codemirror/legacy-modes/mode/vb'
import { yaml } from '@codemirror/legacy-modes/mode/yaml'

import { go } from '@codemirror/legacy-modes/mode/go'
import { java } from '@codemirror/lang-java'
import { json } from '@codemirror/lang-json'
import { markdown } from '@codemirror/lang-markdown'
import { sql, MySQL } from '@codemirror/lang-sql'
import { php } from '@codemirror/lang-php'
import { python } from '@codemirror/lang-python'
import { xml } from '@codemirror/lang-xml'

export default {
  javascript,
  typescript: () => javascript({ typescript: true }),
  jsx: () => javascript({ jsx: true }),
  tsx: () => javascript({ typescript: true, jsx: true }),
  html,
  css,
  json,
  swift: () => StreamLanguage.define(swift),
  yaml: () => StreamLanguage.define(yaml),
  vb: () => StreamLanguage.define(vb),
  dockerFile: () => StreamLanguage.define(dockerFile),
  shell: () => StreamLanguage.define(shell),
  r: () => StreamLanguage.define(r),
  ruby: () => StreamLanguage.define(ruby),
  go: () => StreamLanguage.define(go),
  julia: () => StreamLanguage.define(julia),
  nginx: () => StreamLanguage.define(nginx),
  cpp,
  java,
  xml,
  php,
  sql: () => sql({ dialect: MySQL }),
  markdown,
  python
}
