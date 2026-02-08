<template>
  <el-drawer
    v-model="dialogVisible"
    title="高亮设置"
    :direction="isMobileScreen ? 'ttb' : 'ltr'"
    :close-on-click-modal="true"
    :close-on-press-escape="true"
    :modal="true"
    modal-class="local_setting_drawer"
    :size="isMobileScreen ? '80%' : '35%'"
  >
    <el-form
      ref="formRef"
      label-suffix="："
      label-width="130px"
      :show-message="false"
    >
      <el-form-item label="关键词高亮">
        <el-switch
          v-model="highlightConfig.enabled"
          class="switch"
          inline-prompt
          style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
          active-text="开启"
          inactive-text="关闭"
          @change="handleConfigChange"
        />
      </el-form-item>

      <el-form-item v-if="highlightConfig.enabled" label="调试模式">
        <el-switch
          v-model="highlightConfig.debugMode"
          class="switch"
          inline-prompt
          style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
          active-text="开启"
          inactive-text="关闭"
          @change="handleConfigChange"
        />
        <el-text class="debug-tip" size="small" type="info">
          开启后会在控制台显示详细的高亮处理信息
        </el-text>
      </el-form-item>

      <!-- 规则管理按钮 -->
      <el-form-item v-if="highlightConfig.enabled" label="规则管理">
        <div class="rule-actions">
          <el-button type="warning" size="small" @click="handleRestoreDefaults">
            恢复默认
          </el-button>
          <el-button type="primary" size="small" @click="handleExportRules">
            导出规则
          </el-button>
          <el-button type="success" size="small" @click="handleImportRules">
            导入规则
          </el-button>
        </div>
      </el-form-item>

      <!-- 高亮规则列表 -->
      <div v-if="highlightConfig.enabled" class="rules-section">
        <div
          v-for="(rule, ruleName) in highlightRules"
          :key="ruleName"
          class="rule-item"
        >
          <el-form-item :label="getRuleTitle(ruleName)">
            <div class="rule-content">
              <div class="rule-header">
                <!-- 启用切换开关 -->
                <div class="rule-enable">
                  <el-switch
                    v-model="rule.enabled"
                    size="small"
                    inline-prompt
                    style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
                    active-text="启用"
                    inactive-text="禁用"
                    @change="handleRuleEnabledChange(ruleName, rule.enabled)"
                  />
                </div>

                <div class="color-info">
                  <!-- 文本颜色预览 -->
                  <div class="color-display">
                    <span class="color-label">文本</span>
                    <span
                      class="color-preview"
                      :style="{ backgroundColor: getColorDisplay(rule) }"
                      :title="`文本颜色: ${getColorDisplay(rule)}`"
                    />
                  </div>

                  <!-- 背景色预览 -->
                  <div v-if="rule.backgroundColor" class="color-display">
                    <span class="color-label">背景</span>
                    <span
                      class="background-preview"
                      :style="{ backgroundColor: rule.backgroundColor }"
                      :title="`背景色: ${rule.backgroundColor}`"
                    />
                  </div>

                  <!-- 样式标签 -->
                  <div class="style-tags">
                    <el-tag
                      v-if="rule.bold"
                      size="small"
                      type="danger"
                      effect="dark"
                    >
                      粗体
                    </el-tag>
                    <el-tag
                      v-if="rule.italic"
                      size="small"
                      type="warning"
                      effect="dark"
                    >
                      斜体
                    </el-tag>
                    <el-tag
                      v-if="rule.underline"
                      size="small"
                      type="info"
                      effect="dark"
                    >
                      下划线
                    </el-tag>
                  </div>
                </div>

                <div class="rule-buttons">
                  <el-button
                    type="primary"
                    size="small"
                    link
                    :disabled="!rule.enabled"
                    @click="editRule(ruleName)"
                  >
                    编辑
                  </el-button>
                </div>
              </div>
            </div>
          </el-form-item>
        </div>
      </div>

      <!-- 预览效果 -->
      <el-form-item v-if="highlightConfig.enabled" label="预览效果">
        <div class="test-panel">
          <el-input
            v-model="testText"
            type="textarea"
            :rows="2"
            placeholder="输入测试文本，查看高亮效果"
            class="test-input"
          />
        </div>
      </el-form-item>

      <!-- 预览输出 -->
      <div
        v-if="highlightConfig.enabled"
        class="test-output"
        :style="testOutputStyle"
        v-html="highlightedTestText"
      />
    </el-form>

    <template #footer>
      <span class="dialog_footer">
        <el-button @click="handleCancel">关闭</el-button>
      </span>
    </template>

    <!-- 规则编辑对话框 -->
    <RuleEditDialog
      v-model:show="showRuleEdit"
      :rule-name="editingRuleName"
      :rule-data="editingRule"
      :all-rules="highlightRules"
      @save="handleRuleSave"
    />

    <!-- 导入对话框 -->
    <el-dialog
      v-model="showImportDialog"
      title="导入高亮规则"
      width="600px"
    >
      <el-input
        v-model="importRulesText"
        type="textarea"
        :rows="10"
        placeholder="请粘贴规则JSON内容"
      />
      <template #footer>
        <el-button @click="showImportDialog = false">取消</el-button>
        <el-button type="primary" @click="confirmImportRules">确认导入</el-button>
      </template>
    </el-dialog>
  </el-drawer>
</template>

<script setup>
import { ref, computed, watch, getCurrentInstance } from 'vue'
import { HIGHLIGHT_RULES } from '@/utils/highlighter'
import useMobileWidth from '@/composables/useMobileWidth'
import RuleEditDialog from './rule-edit-dialog.vue'
import themeList from 'xterm-theme'

const { proxy: { $store, $message, $messageBox } } = getCurrentInstance()
const { isMobileScreen } = useMobileWidth()

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:show',])

const dialogVisible = computed({
  get: () => props.show,
  set: (val) => emit('update:show', val)
})

// 高亮配置
const highlightConfig = ref({
  enabled: true,
  debugMode: false
})

// 高亮规则
const highlightRules = ref({ ...HIGHLIGHT_RULES })

// 预览测试
const testText = ref('ERRORS: fatal error! system crashed!\nWARNINGS: deprecated warning! Retrying!\nSUCCESS: login successful established\nINFO: loading configuration, sleeping processes\nNETWORK: 192.168.1.100:8080,2001:db8::1\nURLS: https://api.example.com/v1, git@github.com\nDATETIME: 2024-01-15T10:30:45Z, 3:45 PM\nUNITS: CPU 3.2GHz, RAM 16GB, Network 1Gbps')
const showRuleEdit = ref(false)
const editingRuleName = ref('')
const editingRule = ref(null)
const showImportDialog = ref(false)
const importRulesText = ref('')

// 将RegExp转换为可JSON化的对象
const serializeRules = (rules) => {
  const serialized = {}
  for (const [key, rule,] of Object.entries(rules)) {
    serialized[key] = {
      ...rule,
      pattern: rule.pattern instanceof RegExp ? {
        source: rule.pattern.source,
        flags: rule.flags
      } : rule.pattern
    }
  }
  return serialized
}

// 创建默认规则
const createDefaultRules = () => {
  const defaults = {}
  for (const [key, rule,] of Object.entries(HIGHLIGHT_RULES)) {
    defaults[key] = {
      title: rule.title,
      pattern: rule.pattern,
      flags: rule.flags,
      displayColor: rule.displayColor,
      backgroundColor: rule.backgroundColor,
      bold: rule.bold,
      italic: rule.italic,
      underline: rule.underline,
      fullLine: rule.fullLine,
      enabled: rule.enabled !== false
    }
  }
  return defaults
}

const getRuleTitle = (ruleName) => {
  const rule = highlightRules.value[ruleName]
  return rule.title || ruleName
}

const getColorDisplay = (rule) => {
  return rule.displayColor
}

// 获取用户终端配置
const userFontFamily = computed(() => {
  return $store.terminalConfig?.fontFamily || 'monospace'
})

const userBackground = computed(() => {
  return $store.terminalConfig?.background || ''
})

const userTheme = computed(() => {
  const themeName = $store.terminalConfig?.themeName || 'Afterglow'
  return themeList[themeName] || themeList['Afterglow']
})

const userFontColor = computed(() => {
  return $store.terminalConfig?.fontColor || ''
})

// 预览输出样式
const testOutputStyle = computed(() => {
  const style = {
    fontFamily: userFontFamily.value,
    fontSize: '14px'
  }

  // 如果有自定义背景
  if (userBackground.value) {
    // 判断背景类型
    if (userBackground.value.startsWith('http')) {
      // 图片URL：透明背景 + 背景图
      style.backgroundColor = 'transparent'
      style.backgroundImage = `url(${ userBackground.value })`
      style.backgroundSize = 'cover'
      style.backgroundPosition = 'center'
      style.backgroundRepeat = 'no-repeat'
    } else {
      // 渐变色或纯色：直接使用该值作为背景
      style.backgroundColor = 'transparent'
      style.backgroundImage = userBackground.value
      style.backgroundSize = '100% 100%'
      style.backgroundRepeat = 'no-repeat'
    }
  } else {
    // 使用主题背景色
    style.backgroundColor = userTheme.value.background || '#1e1e1e'
  }

  // 如果有自定义字体颜色
  if (userFontColor.value) {
    style.color = userFontColor.value
  } else {
    // 使用主题字体颜色
    style.color = userTheme.value.foreground || '#ffffff'
  }

  return style
})

// 高亮预览效果中的测试文本，专门兼容html的标签问题
const highlightedTestText = computed(() => {
  if (!testText.value || !highlightConfig.value.enabled) {
    return testText.value
  }

  try {
    const source = testText.value + '' // 强制创建新字符串
    let output = source

    // 处理所有规则
    const activeRules = Object.entries(highlightRules.value)
      .filter(([, rule,]) => rule.enabled && rule.pattern)

    for (const [ruleName, rule,] of activeRules) {
      // 创建新的正则表达式实例，避免全局状态问题
      const regex = new RegExp(rule.pattern.source, rule.flags)

      // 先找到所有匹配位置，检查是否在HTML标签内
      const matches = []
      let match
      regex.lastIndex = 0
      while ((match = regex.exec(output)) !== null) {
        matches.push({
          index: match.index,
          text: match[0]
        })
      }

      // 从后往前替换，避免索引偏移问题
      for (let i = matches.length - 1; i >= 0; i--) {
        const { index, text } = matches[i]

        // 检查匹配位置是否在HTML标签内部
        const before = output.substring(0, index)
        const lastOpenTag = before.lastIndexOf('<')
        const lastCloseTag = before.lastIndexOf('>')

        // 如果最近的 < 比 > 更近，说明在标签内部，跳过
        if (lastOpenTag > lastCloseTag) {
          continue
        }

        // 构建样式字符串
        let styles = ''

        // 字体
        styles += 'font-family:' + userFontFamily.value + ' !important;'
        styles += 'font-size:14px !important;'
        styles += 'font-weight:' + (rule.bold ? 'bold' : 'normal') + ' !important;'
        styles += 'font-style:' + (rule.italic ? 'italic' : 'normal') + ' !important;'

        // 颜色
        styles += 'color:' + rule.displayColor + ' !important;'

        // 添加背景色
        if (rule.backgroundColor) {
          styles += 'background-color:' + rule.backgroundColor + ' !important;'
        }

        if (rule.underline) {
          styles += 'text-decoration:underline !important;'
        }

        // 添加padding，效果更明显
        if (rule.backgroundColor) {
          styles += 'padding:2px 4px !important;border-radius:3px !important;'
        }

        const replacement = '<span style="' + styles + '">' + text + '</span>'

        // 替换
        output = output.substring(0, index) + replacement + output.substring(index + text.length)
      }
    }

    const finalOutput = output.replace(/\n/g, '<br>')

    return finalOutput
  } catch (error) {
    console.error('预览错误:', error)
    return testText.value.replace(/\n/g, '<br>')
  }
})

// 加载当前配置
const loadConfig = () => {
  const terminalConfig = $store.terminalConfig
  highlightConfig.value = {
    enabled: terminalConfig.keywordHighlight !== false,
    debugMode: terminalConfig.highlightDebugMode || false
  }

  // 如果有自定义规则，尝试使用自定义规则；如果无有效规则则使用默认规则
  let useDefaultRules = true

  if (terminalConfig.customHighlightRules) {
    // 标准化自定义规则，确保pattern是RegExp对象
    const customRules = {}
    for (const [key, rule,] of Object.entries(terminalConfig.customHighlightRules)) {
      // 跳过无效的规则
      if (!rule.pattern || (typeof rule.pattern === 'object' && !rule.pattern.source)) {
        console.warn(`跳过无效的自定义规则 ${ key }:`, rule.pattern)
        continue
      }

      let validPattern
      if (rule.pattern instanceof RegExp) {
        validPattern = rule.pattern
      } else if (rule.pattern.source) {
        validPattern = new RegExp(rule.pattern.source, rule.flags || 'gi')
      } else {
        console.warn(`跳过无法解析的规则 ${ key }:`, rule.pattern)
        continue
      }

      customRules[key] = {
        ...rule,
        title: rule.title || '',
        pattern: validPattern,
        flags: rule.flags || 'gi',
        backgroundColor: rule.backgroundColor || null,
        bold: rule.bold || false,
        italic: rule.italic || false,
        underline: rule.underline || false
      }
    }

    // 如果有有效的自定义规则，使用它们，否则使用默认规则
    if (Object.keys(customRules).length > 0) {
      highlightRules.value = customRules
      useDefaultRules = false
    }
  }

  if (useDefaultRules) {
    highlightRules.value = createDefaultRules()
  }
}

// 编辑规则
const editRule = (ruleName) => {
  editingRuleName.value = ruleName
  editingRule.value = { ...highlightRules.value[ruleName] }
  showRuleEdit.value = true
}

// 处理规则启用状态变化
const handleRuleEnabledChange = async (ruleName, enabled) => {
  try {
    highlightRules.value[ruleName].enabled = enabled

    // 保存到服务器
    const config = {
      customHighlightRules: serializeRules(highlightRules.value)
    }

    await $store.setTerminalSetting(config)
    $message.success(`${ getRuleTitle(ruleName) }${ enabled ? '已启用' : '已禁用' }`)
  } catch (error) {
    $message.error('保存设置失败')
    // 回滚状态
    highlightRules.value[ruleName].enabled = !enabled
  }
}

// 保存规则编辑
const handleRuleSave = async (ruleName, ruleData) => {
  try {
    highlightRules.value[ruleName] = { ...ruleData }
    showRuleEdit.value = false

    // 立即保存自定义规则到服务器
    const config = {
      customHighlightRules: serializeRules(highlightRules.value)
    }

    await $store.setTerminalSetting(config)
    $message.success('规则保存成功')
  } catch (error) {
    $message.error('保存规则失败')
  }
}

// 恢复默认规则
const handleRestoreDefaults = async () => {
  try {
    await $messageBox.confirm('确认恢复为默认高亮规则？此操作将覆盖所有自定义规则和颜色。', '确认', {
      type: 'warning'
    })

    // 拷贝默认规则，确保包含所有新属性
    highlightRules.value = createDefaultRules()

    // 立即保存到服务器，清除自定义规则
    const config = {
      customHighlightRules: null
    }

    await $store.setTerminalSetting(config)
    $message.success('已恢复默认规则和颜色')
  } catch (error) {
    if (error !== 'cancel') {
      $message.error('恢复默认规则失败')
    }
  }
}

// 导出规则
const handleExportRules = () => {
  const rulesData = {
    highlightConfig: highlightConfig.value,
    highlightRules: serializeRules(highlightRules.value),
    exportTime: new Date().toISOString()
  }

  const blob = new Blob([JSON.stringify(rulesData, null, 2),], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `terminal-highlight-rules-${ new Date().toISOString().slice(0, 10) }.json`
  a.click()
  URL.revokeObjectURL(url)

  $message.success('规则导出成功')
}

// 导入规则
const handleImportRules = () => {
  showImportDialog.value = true
  importRulesText.value = ''
}

const confirmImportRules = async () => {
  try {
    const importData = JSON.parse(importRulesText.value)

    if (importData.highlightConfig) {
      highlightConfig.value = { ...importData.highlightConfig }
    }

    if (importData.highlightRules) {
      // 转换导入的规则，将序列化的pattern重新转换为RegExp对象
      const convertedRules = {}
      for (const [key, rule,] of Object.entries(importData.highlightRules)) {
        convertedRules[key] = {
          ...rule,
          // 将序列化的pattern转换回RegExp对象
          pattern: rule.pattern && rule.pattern.source
            ? new RegExp(rule.pattern.source, rule.flags || 'gi')
            : rule.pattern
        }
      }
      highlightRules.value = convertedRules
    }

    // 保存到服务器时序列化RegExp
    const config = {
      keywordHighlight: highlightConfig.value.enabled,
      highlightDebugMode: highlightConfig.value.debugMode,
      customHighlightRules: serializeRules(highlightRules.value)
    }

    await $store.setTerminalSetting(config)
    showImportDialog.value = false
    $message.success('规则导入并保存成功')
  } catch (error) {
    $message.error('导入失败，请检查JSON格式')
  }
}

// 实时保存配置
const handleConfigChange = async () => {
  try {
    // 立即更新到store
    $store.terminalConfig.keywordHighlight = highlightConfig.value.enabled
    $store.terminalConfig.highlightDebugMode = highlightConfig.value.debugMode

    // 保存到服务器
    const config = {
      keywordHighlight: highlightConfig.value.enabled,
      highlightDebugMode: highlightConfig.value.debugMode
    }

    await $store.setTerminalSetting(config)
  } catch (error) {
    $message.error('保存配置失败')
  }
}

// 关闭对话框
const handleCancel = () => {
  dialogVisible.value = false
}

// 监听对话框显示
watch(() => props.show, (show) => {
  if (show) {
    loadConfig()
  }
})
</script>

<style lang="scss" scoped>
.debug-tip {
  margin-left: 12px;
  display: block;
  margin-top: 4px;
}

.rule-actions {
  display: flex;
  gap: 8px;

  .el-button {
    margin-right: 0;
  }
}

.rules-section {
  margin-top: 20px;

  .rule-item {
    margin-bottom: 16px;

    .rule-content {
      .rule-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 8px;
        gap: 12px;

        .rule-enable {
          flex-shrink: 0;
        }

        .color-info {
          display: flex;
          align-items: center;
          gap: 12px;
          flex-wrap: wrap;
          flex: 1;
        }

        .color-display {
          display: flex;
          align-items: center;
          gap: 6px;

          .color-label {
            font-size: 12px;
            color: var(--el-text-color-regular);
            min-width: 24px;
          }
        }

        .color-preview {
          width: 16px;
          height: 16px;
          border-radius: 2px;
          display: inline-block;
          border: 1px solid var(--el-border-color);
        }

        .background-preview {
          width: 16px;
          height: 16px;
          border-radius: 2px;
          display: inline-block;
          border: 1px solid var(--el-border-color);
        }

        .style-tags {
          display: flex;
          gap: 4px;
          flex-wrap: wrap;
        }

        .rule-buttons {
          display: flex;
          gap: 8px;
        }
      }
    }
  }
}

.test-panel {
  width: calc(100% + 130px);
  margin-left: -130px;
  padding-left: 130px;

  .test-input {
    margin-bottom: 12px;
    width: 100%;
  }

  :deep(.el-textarea__inner) {
    width: 100%;
  }
}

.test-output {
  padding: 12px;
  border-radius: 4px;
  font-weight: normal;
  font-style: normal;
  min-height: 120px;
  line-height: 1.5;
  width: 100%;
  overflow-wrap: break-word;
  margin-top: 0;
}

.dialog_footer {
  display: flex;
  justify-content: center;
  gap: 12px;
}
</style>

<style lang="scss">
.local_setting_drawer {
  .el-drawer__header {
    margin-bottom: 0 !important;
  }
}
</style>