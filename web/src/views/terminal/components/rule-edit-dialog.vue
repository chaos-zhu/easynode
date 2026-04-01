<template>
  <Teleport :to="teleportTarget">
    <el-dialog
      v-model="dialogVisible"
      :title="t('terminal.editHighlightRule')"
      width="900px"
      :append-to-body="false"
      :close-on-click-modal="false"
      :before-close="handleBeforeClose"
    >
    <div class="rule-edit">
      <el-form
        ref="formRef"
        :model="formData"
        :rules="formRules"
        label-width="120px"
      >
        <el-form-item :label="t('terminal.ruleTitle')" prop="title">
          <el-input
            v-model="formData.title"
            :placeholder="t('terminal.emptyUseDefaultName')"
            maxlength="10"
            show-word-limit
            clearable
          />
        </el-form-item>

        <el-form-item :label="t('terminal.colorSettings')">
          <div class="color-row">
            <div class="color-item">
              <label>{{ t('terminal.textColor') }}</label>
              <el-color-picker
                v-model="formData.displayColor"
                size="small"
                :teleported="false"
                :predefine="getTextColorPredefines()"
                @change="handleColorChange"
              />
            </div>
            <div class="color-item">
              <label>{{ t('terminal.backgroundColor') }}</label>
              <el-color-picker
                v-model="formData.backgroundColor"
                size="small"
                show-alpha
                :teleported="false"
                :predefine="getBackgroundColorPredefines()"
                @change="handleBackgroundColorChange"
              />
            </div>
          </div>
        </el-form-item>

        <el-form-item :label="t('terminal.textStyle')">
          <el-checkbox-group v-model="textStyles" @change="handleStyleChange">
            <el-checkbox value="bold">{{ t('terminal.boldText') }}</el-checkbox>
            <el-checkbox value="italic">{{ t('terminal.italic') }}</el-checkbox>
            <el-checkbox value="underline">{{ t('terminal.underline') }}</el-checkbox>
          </el-checkbox-group>
        </el-form-item>

        <el-form-item :label="t('terminal.regexExpression')" prop="pattern">
          <el-input
            v-model="patternSource"
            type="textarea"
            :rows="3"
            :placeholder="t('terminal.inputRegexExpression')"
            @input="updatePattern"
          />
        </el-form-item>

        <el-form-item :label="t('terminal.ruleOptions')">
          <el-checkbox v-model="ignoreCase" @change="updatePattern">{{ t('terminal.ignoreCase') }}</el-checkbox>
          <el-checkbox v-model="fullLine">{{ t('terminal.highlightWholeLine') }}</el-checkbox>
        </el-form-item>

        <el-form-item :label="t('terminal.testText')">
          <el-input
            v-model="testInput"
            type="textarea"
            :rows="2"
            :placeholder="t('terminal.inputTestText')"
          />
        </el-form-item>

        <el-form-item :label="t('terminal.matchResult')">
          <div class="test-result">
            <div v-if="testMatches.length" class="matches">
              <el-tag
                v-for="(match, index) in testMatches"
                :key="index"
                size="small"
                type="success"
                class="match-tag"
              >
                {{ match }}
              </el-tag>
            </div>
            <el-text v-else size="small" type="info">
              {{ t('terminal.noMatchResult') }}
            </el-text>
          </div>
        </el-form-item>

        <el-form-item :label="t('terminal.preview')">
          <div class="preview-result" v-html="previewHtml" />
        </el-form-item>

        <el-form-item :label="t('terminal.commonTemplates')">
          <div class="templates">
            <el-button
              v-for="template in getTemplates(ruleName)"
              :key="template.name"
              size="small"
              @click="applyTemplate(template)"
            >
              {{ template.name }}
            </el-button>
          </div>
        </el-form-item>
      </el-form>
    </div>

    <template #footer>
      <div class="dialog-footer">
        <el-button @click="handleCancel">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" @click="handleSave">{{ t('common.save') }}</el-button>
      </div>
    </template>
    </el-dialog>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch, getCurrentInstance, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { HIGHLIGHT_RULES, TerminalHighlighter } from '@/utils/highlighter'

const { proxy: { $message, $messageBox } } = getCurrentInstance()
const { t } = useI18n()

// 全屏时teleport到fullscreenElement，否则teleport到body
const teleportTarget = computed(() => {
  return document.fullscreenElement || 'body'
})

// 检查颜色是否已被使用
const isColorUsed = (color, rules, excludeKey = null) => {
  const usedColors = Object.entries(rules)
    .filter(([key,]) => key !== excludeKey)
    .map(([, rule,]) => rule.displayColor.toLowerCase())
  return usedColors.includes(color.toLowerCase())
}

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  ruleName: {
    type: String,
    default: ''
  },
  ruleData: {
    type: Object,
    default: () => null
  },
  allRules: {
    type: Object,
    default: () => ({})
  }
})

const emit = defineEmits(['update:show', 'save',])

const dialogVisible = computed({
  get: () => props.show,
  set: (val) => emit('update:show', val)
})

const formRef = ref(null)
const patternSource = ref('')
const ignoreCase = ref(true)
const fullLine = ref(false)
const testInput = ref('')
const textStyles = ref([])

// 创建一个用于预览的highlighter实例
const previewHighlighter = new TerminalHighlighter(null, {
  enabled: true,
  debugMode: false
})

// 原始数据，用于检测变化
const originalData = ref({})

const formData = ref({
  title: '',
  pattern: null,
  flags: 'gi',
  fullLine: false,
  displayColor: '',
  backgroundColor: null,
  bold: false,
  italic: false,
  underline: false,
  enabled: true
})

const formRules = {
  title: [
    { max: 10, message: t('terminal.titleMaxLength'), trigger: 'blur' },
  ],
  pattern: [
    {
      required: true,
      validator: (_rule, _value, callback) => {
        if (!patternSource.value || patternSource.value.trim() === '') {
          callback(new Error(t('terminal.inputRegexRequired')))
        } else {
          try {
            new RegExp(patternSource.value, patternFlags.value)
            callback()
          } catch (error) {
            callback(new Error(t('terminal.regexInvalid')))
          }
        }
      },
      trigger: 'blur'
    },
  ]
}

// 计算属性
const patternFlags = computed(() => ignoreCase.value ? 'gi' : 'g')

const testMatches = computed(() => {
  if (!patternSource.value || !testInput.value) return []

  try {
    const regex = new RegExp(patternSource.value, patternFlags.value)
    const matches = testInput.value.match(regex) || []
    return [...new Set(matches),] // 去重
  } catch (error) {
    return []
  }
})

const previewHtml = computed(() => {
  if (!patternSource.value || !testInput.value) {
    return testInput.value || t('terminal.inputPreviewText')
  }

  try {
    // 构造当前编辑的规则对象
    const currentRule = {
      pattern: new RegExp(patternSource.value, patternFlags.value),
      flags: patternFlags.value,
      fullLine: fullLine.value,
      displayColor: formData.value.displayColor,
      backgroundColor: formData.value.backgroundColor,
      bold: formData.value.bold,
      italic: formData.value.italic,
      underline: formData.value.underline,
      enabled: true
    }

    // 使用highlighter的HTML预览方法
    return previewHighlighter.applySingleRuleForHtml(testInput.value, currentRule)
  } catch (error) {
    return t('terminal.regexError', { message: error.message })
  }
})

// 获取文本颜色预定义值
const getTextColorPredefines = () => {
  return [
    // 默认规则的文本颜色
    '#ff4d4f', // rule1 - 错误红色
    '#fadb14', // rule2 - 警告黄色
    '#52c41a', // rule3 - 成功绿色
    '#13c2c2', // rule4 - 信息青色
    '#eb2f96', // rule5 - 网络洋红
    '#1890ff', // rule6 - 链接蓝色
    '#ffffff', // rule7 - 日期时间白色
    '#8b5cf6', // rule8 - 单位数据紫色

    // 基础色
    '#000000', // 黑色
    '#808080', // 灰色
    '#c0c0c0', // 浅灰色
    '#404040', // 深灰色

    // 其他颜色
    '#ef4444', '#f97316', '#f59e0b', '#eab308',
    '#84cc16', '#22c55e', '#10b981', '#14b8a6',
    '#06b6d4', '#0ea5e9', '#3b82f6', '#6366f1',
    '#a855f7', '#d946ef', '#ec4899', '#f43f5e',
  ]
}

// 获取背景颜色预定义值
const getBackgroundColorPredefines = () => {
  return [
    // 基础色
    'transparent',
    '#000000', // 黑色
    '#ffffff', // 白色
    '#404040', // 深灰色
    '#808080', // 中灰色
    '#c0c0c0', // 浅灰色

    // 深色背景
    '#1f2937', // 深蓝灰
    '#374151', // 灰蓝色
    '#4b5563', // 石板灰
    '#6b7280', // 钢灰色
    '#fa541c', // 橙色
    '#dc2626', // 深红色
    '#b91c1c', // 暗红色
    '#7c3aed', // 深紫色

    // 中等饱和度
    '#ef4444', // 红色
    '#f97316', // 橙色
    '#eab308', // 黄色
    '#22c55e', // 绿色
    '#06b6d4', // 青色
    '#3b82f6', // 蓝色
    '#8b5cf6', // 紫色
    '#ec4899', // 粉色

    // 其他颜色
    '#1e40af', '#7c2d12', '#166534', '#0f766e',
    '#0c4a6e', '#581c87', '#9d174d', '#be123c',
  ]
}

// 颜色变化处理
const handleColorChange = (newColor) => {
  if (!newColor) return

  // 检查颜色是否重复
  if (isColorUsed(newColor, props.allRules, props.ruleName)) {
    $message.warning(t('terminal.colorAlreadyUsed'))
    // 阻止更新，强制恢复原颜色
    const originalColor = props.ruleData?.displayColor || HIGHLIGHT_RULES[props.ruleName].displayColor
    // 使用nextTick确保在下一个事件循环中恢复颜色
    nextTick(() => {
      formData.value.displayColor = originalColor
    })
    return
  }

  formData.value.displayColor = newColor
}

// 背景颜色变化处理
const handleBackgroundColorChange = (newColor) => {
  formData.value.backgroundColor = newColor
}

// 文字样式变化处理
const handleStyleChange = (styles) => {
  formData.value.bold = styles.includes('bold')
  formData.value.italic = styles.includes('italic')
  formData.value.underline = styles.includes('underline')
}

// 获取模板列表
const getTemplates = (ruleName) => {
  // 从默认规则中提取模板
  const defaultRule = HIGHLIGHT_RULES[ruleName]

  const templates = [
    // 第一个模板：真实的默认规则
    {
      name: t('terminal.defaultRuleFull'),
      pattern: defaultRule.pattern.source,
      flags: defaultRule.flags.split('')
    },
  ]

  // 根据不同颜色添加特定的常用模板
  const additionalTemplates = getAdditionalTemplates(ruleName)
  templates.push(...additionalTemplates)

  return templates
}

// 获取各颜色的额外模板
const getAdditionalTemplates = (ruleName) => {
  const templateMap = {
    rule1: [
      {
        name: '基础错误关键词',
        pattern: '\\b(error|err|failed?|failure|fatal|critical)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '系统崩溃异常',
        pattern: '\\b(crash(ed)?|exception|panic|abort(ed)?|kill(ed)?|terminate(d)?|dead|died)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '拒绝访问类',
        pattern: '\\b(denied|refused|forbidden|unauthorized|blocked|locked|invalid)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '连接超时',
        pattern: '\\b(timeout|disconnect(ed)?|unreachable|unavailable|missing|not found)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '安全威胁',
        pattern: '\\b(virus|breach|hack(ed)?|attack|exploit|vulnerability|malicious|infected|compromised|hijacked|suspicious|illegal)\\b',
        flags: ['g', 'i',]
      },
    ],
    rule2: [
      {
        name: '基础警告关键词',
        pattern: '\\b(warn(ing)?|deprecated|caution)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '重试延迟状态',
        pattern: '\\b(retry|retrying|retried|delay(ed)?|slow|slower|pending|waiting)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '临时状态',
        pattern: '\\b(temporary|temp|experimental|beta|alpha|preview|unstable)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '安全风险',
        pattern: '\\b(insecure|vulnerable|risky|outdated|obsolete)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '系统维护',
        pattern: '\\b(maintenance|migration|backup|fallback|suspend(ed)?|pause(d)?)\\b',
        flags: ['g', 'i',]
      },
    ],
    rule3: [
      {
        name: '基础成功关键词',
        pattern: '\\b(success(ful)?|successfully|complete(d)?|completed|ok(ay)?|done)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '运行启动状态',
        pattern: '\\b(running|active|online|ready|started|start|begin|launch(ed)?)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '连接可用状态',
        pattern: '\\b(connect(ed)?|available|enabled|online|accessible)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '验证通过状态',
        pattern: '\\b(valid|verified|confirmed|approved|passed|accepted|authenticated|authorized)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '安装部署状态',
        pattern: '\\b(installed|deployed|built|compiled|loaded|mounted|updated|upgraded)\\b',
        flags: ['g', 'i',]
      },
    ],
    rule4: [
      {
        name: '基础信息关键词',
        pattern: '\\b(info|information|notice|message|log)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '调试日志级别',
        pattern: '\\b(debug|trace|verbose|log|report)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '处理连接状态',
        pattern: '\\b(processing|loading|connecting|checking|monitoring)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '配置初始化',
        pattern: '\\b(config|configuration|setting|setup|initializing|preparing)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '构建编译状态',
        pattern: '\\b(building|compiling|parsing|analyzing|scanning)\\b',
        flags: ['g', 'i',]
      },
    ],
    rule5: [
      {
        name: 'IPv4地址',
        pattern: '\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b',
        flags: ['g',]
      },
      {
        name: 'IP:端口组合',
        pattern: '\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}:\\d{1,5}\\b',
        flags: ['g',]
      },
      {
        name: 'IPv6完整格式',
        pattern: '\\b([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\\b',
        flags: ['g',]
      },
      {
        name: 'IPv6简化格式',
        pattern: '\\b([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{0,4}\\b',
        flags: ['g',]
      },
      {
        name: 'MAC地址',
        pattern: '\\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\\b|\\b([0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}\\b',
        flags: ['g',]
      },
      {
        name: '内网IPv4地址',
        pattern: '\\b(10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|172\\.(1[6-9]|2\\d|3[01])\\.\\d{1,3}\\.\\d{1,3}|192\\.168\\.\\d{1,3}\\.\\d{1,3})\\b',
        flags: ['g',]
      },
    ],
    rule6: [
      {
        name: 'HTTP/HTTPS链接',
        pattern: 'https?:\\/\\/[^\\s]+',
        flags: ['g', 'i',]
      },
      {
        name: 'FTP链接',
        pattern: 'ftps?:\\/\\/[^\\s]+',
        flags: ['g', 'i',]
      },
      {
        name: '邮箱地址',
        pattern: '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}',
        flags: ['g', 'i',]
      },
      {
        name: '文件路径（Unix）',
        pattern: '\\/[\\w\\-._\\/]*[\\w\\-._]',
        flags: ['g',]
      },
      {
        name: '文件路径（Windows）',
        pattern: '[A-Z]:\\\\[\\w\\-._\\\\\\s]*[\\w\\-._]',
        flags: ['g', 'i',]
      },
      {
        name: 'www域名',
        pattern: 'www\\.[^\\s]+\\.[a-z]{2,}[^\\s]*',
        flags: ['g', 'i',]
      },
    ],
    rule7: [
      {
        name: 'ISO 8601格式',
        pattern: '\\b\\d{4}-\\d{2}-\\d{2}[Tt]\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,6})?[Zz]?\\b',
        flags: ['g',]
      },
      {
        name: '标准日期格式',
        pattern: '\\b\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}\\b|\\b\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4}\\b',
        flags: ['g',]
      },
      {
        name: '时间格式',
        pattern: '\\b\\d{1,2}:\\d{1,2}(:\\d{1,2})?(\\.\\d{1,6})?\\b',
        flags: ['g',]
      },
      {
        name: '12小时制时间',
        pattern: '\\b\\d{1,2}:\\d{1,2}(:\\d{1,2})?(\\.\\d{1,6})?\\s?[AaPp][Mm]\\b',
        flags: ['g',]
      },
      {
        name: '日志时间戳',
        pattern: '\\[\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,6})?\\]',
        flags: ['g',]
      },
      {
        name: 'Unix时间戳',
        pattern: '\\b\\d{10,13}\\b',
        flags: ['g',]
      },
    ],
    rule8: [
      {
        name: '存储单位',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:TiB|GiB|MiB|KiB|TB|GB|MB|KB|B)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '网络速度',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:Tbps|Gbps|Mbps|Kbps|bps)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '时间单位',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:ns|μs|ms|min|hrs?)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '温度单位',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:°C|°F|K)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '频率单位',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:Hz|KHz|MHz|GHz|THz)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '百分比',
        pattern: '\\b(?:\\d+(?:\\.\\d+)?|100(?:\\.0+)?)\\s*%',
        flags: ['g',]
      },
      {
        name: '性能指标',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s*(?:ops[/]s|req[/]s|qps|tps|rps|iops|IOPS|pps|PPS)\\b',
        flags: ['g', 'i',]
      },
      {
        name: '完整时间描述',
        pattern: '\\b\\d+(?:\\.\\d+)?\\s+(?:milliseconds?|seconds?|minutes?|hours?|days?|weeks?|months?|years?)\\b',
        flags: ['g', 'i',]
      },
    ]
  }

  return templateMap[ruleName] || []
}

// 方法
const updatePattern = () => {
  try {
    formData.value.pattern = new RegExp(patternSource.value, patternFlags.value)
  } catch (error) {
    console.error(t('terminal.invalidRegex'), error)
  }
}

const applyTemplate = (template) => {
  patternSource.value = template.pattern
  ignoreCase.value = template.flags.includes('i')
  updatePattern()
}

const handleSave = async () => {
  if (!formRef.value) return

  try {
    await formRef.value.validate()
    updatePattern()

    if (!formData.value.pattern) {
      throw new Error(t('terminal.invalidRegex'))
    }

    // 最终检查颜色是否重复
    if (isColorUsed(formData.value.displayColor, props.allRules, props.ruleName)) {
      $message.error(t('terminal.colorAlreadyUsedCannotSave'))
      return
    }

    emit('save', props.ruleName, {
      title: formData.value.title,
      pattern: formData.value.pattern,
      flags: patternFlags.value,
      fullLine: fullLine.value,
      displayColor: formData.value.displayColor,
      backgroundColor: formData.value.backgroundColor,
      bold: formData.value.bold,
      italic: formData.value.italic,
      underline: formData.value.underline,
      enabled: formData.value.enabled
    })
  } catch (error) {
    console.error('保存失败:', error)
  }
}

// 检测数据是否发生变化
const hasDataChanged = () => {
  if (!originalData.value || !Object.keys(originalData.value).length) return false

  const current = {
    title: formData.value.title,
    displayColor: formData.value.displayColor,
    backgroundColor: formData.value.backgroundColor,
    bold: formData.value.bold,
    italic: formData.value.italic,
    underline: formData.value.underline,
    enabled: formData.value.enabled,
    patternSource: patternSource.value,
    ignoreCase: ignoreCase.value,
    fullLine: fullLine.value
  }

  return JSON.stringify(current) !== JSON.stringify(originalData.value)
}

// 关闭前确认
const handleBeforeClose = async (done) => {
  if (hasDataChanged()) {
    try {
      await $messageBox.confirm(
        t('terminal.unsavedChangesCloseConfirm'),
        t('terminal.closeConfirmTitle'),
        {
          type: 'warning',
          confirmButtonText: t('terminal.confirmClose'),
          cancelButtonText: t('terminal.continueEditing')
        }
      )
      done()
    } catch {
      // 用户取消，不关闭
    }
  } else {
    done()
  }
}

const handleCancel = async () => {
  await handleBeforeClose(() => {
    dialogVisible.value = false
  })
}

// 监听
watch(() => props.show, (show) => {
  if (show && props.ruleData) {
    // 获取默认规则作为基础
    const defaultRule = HIGHLIGHT_RULES[props.ruleName]

    // 使用 ?? 空值合并运算符，只有 null/undefined 时才使用默认值
    formData.value = {
      title: props.ruleData.title ?? defaultRule.title,
      displayColor: props.ruleData.displayColor ?? defaultRule.displayColor,
      backgroundColor: props.ruleData.backgroundColor ?? defaultRule.backgroundColor,
      bold: props.ruleData.bold ?? defaultRule.bold,
      italic: props.ruleData.italic ?? defaultRule.italic,
      underline: props.ruleData.underline ?? defaultRule.underline,
      enabled: props.ruleData.enabled !== false
    }

    // 标准RegExp对象处理
    const patternData = props.ruleData.pattern ?? defaultRule.pattern
    if (patternData && patternData.source) {
      patternSource.value = patternData.source
      ignoreCase.value = (props.ruleData.flags ?? defaultRule.flags ?? 'gi').includes('i')
    } else {
      patternSource.value = ''
      ignoreCase.value = true
      console.warn('规则数据中的pattern格式不正确:', props.ruleData.pattern)
    }

    // 初始化 fullLine 状态
    fullLine.value = props.ruleData.fullLine ?? defaultRule.fullLine

    // 初始化样式复选框状态
    const styles = []
    if (formData.value.bold) styles.push('bold')
    if (formData.value.italic) styles.push('italic')
    if (formData.value.underline) styles.push('underline')
    textStyles.value = styles

    // 保存原始数据用于变化检测
    originalData.value = {
      title: formData.value.title,
      displayColor: formData.value.displayColor,
      backgroundColor: formData.value.backgroundColor,
      bold: formData.value.bold,
      italic: formData.value.italic,
      underline: formData.value.underline,
      enabled: formData.value.enabled,
      patternSource: patternSource.value,
      ignoreCase: ignoreCase.value,
      fullLine: fullLine.value
    }

    // 默认的规则测试文本
    if (!testInput.value) {
      testInput.value = `🔴 ERRORS: fatal error! system crashed, expires certificate, virus attack, unauthorized blocked
🟡 WARNINGS: deprecated warning! experimental feature, vulnerable system, maintenance mode
🟢 SUCCESS: login successful established! task completed, system healthy, verified passed
🔵 INFO: loading configuration, debugging trace, sleeping zombie processes, stopped
🌐 NETWORK: 192.168.1.100:8080, 2001:db8::1, aa:bb:cc:dd:ee:ff
🔗 URLS: https://api.example.com/v1, mailto:admin@domain.com, /usr/local/bin
📅 DATETIME: 2024-01-15T10:30:45Z, 3:45 PM, 01/15/2024
💾 UNITS: CPU 3.2GHz 68°C, RAM 16GB 85%, Network 1Gbps, Process 2 hours 30 minutes`
    }
  }
})
</script>

<style lang="scss" scoped>
.rule-edit {
  .rule-options {
    display: flex;
    gap: 30px;
    align-items: center;

    .option-item {
      display: flex;
      align-items: center;
      gap: 12px;

      label {
        font-size: 14px;
        color: var(--el-text-color-regular);
        min-width: 80px;
        white-space: nowrap;
      }
    }
  }

  .color-row {
    display: flex;
    gap: 20px;
    align-items: center;

    .color-item {
      display: flex;
      align-items: center;
      gap: 8px;

      label {
        font-size: 14px;
        color: var(--el-text-color-regular);
        min-width: 60px;
        white-space: nowrap;
      }
    }
  }

  .color-info {
    display: flex;
    align-items: center;

    .color-selector {
      margin-left: auto;
    }
  }

  .test-result {
    .matches {
      .match-tag {
        margin-right: 8px;
        margin-bottom: 4px;
      }
    }
  }

  .preview-result {
    padding: 12px;
    background-color: #1e1e1e;
    color: #ffffff;
    border-radius: 4px;
    font-family: Cascadia Code, Menlo, monospace;
    font-weight: normal;
    font-style: normal;
    min-height: 60px;
    line-height: 1.5;
  }

  .templates {
    .el-button {
      margin-right: 8px;
      margin-bottom: 8px;
    }
  }
}

.dialog-footer {
  text-align: right;
}
</style>