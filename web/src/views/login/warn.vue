<template>
  <el-dialog
    v-model="visible"
    :title="t('login.warningsTitle')"
    width="550px"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    @closed="handleClosed"
  >
    <div class="warn-content">
      <ol>
        <li>
          {{ t('login.warnings.importantData').split('非常重要的数据')[0] }}<span class="highlight">非常重要的数据</span>{{ t('login.warnings.importantData').split('非常重要的数据')[1] }}
        </li>
        <li>
          {{ t('login.warnings.authAndWhitelist').split('双重认证')[0] }}<span class="highlight">双重认证</span>{{ t('login.warnings.authAndWhitelist').split('双重认证')[1].split('IP白名单')[0] }}<span class="highlight">IP白名单</span>{{ t('login.warnings.authAndWhitelist').split('IP白名单')[1] }}
        </li>
        <li>
          3. <span class="highlight">{{ t('login.warnings.noUnknownPlugins').replace('3. ', '').replace('，以防止鉴权Token泄露。', '') }}</span>，以防止鉴权Token泄露。
        </li>
        <li>
          4. 在公网<span class="highlight">{{ t('login.warnings.useHttps').replace('4. 在公网', '').replace('可能会导致你的鉴权token泄露。', '') }}</span>可能会导致你的鉴权token泄露。
        </li>
        <li>
          5. <span class="highlight">{{ t('login.warnings.updatePanel').replace('5. ', '').replace('，以防止底层依赖的组件具有安全漏洞或者面板自身服务漏洞。', '') }}</span>，以防止底层依赖的组件具有安全漏洞或者面板自身服务漏洞。
        </li>
        <li>
          {{ t('login.warnings.subscribeTg') }}<span class="point" @click="subTg">{{ t('login.warnings.subscribeClick') }}</span>。
        </li>
      </ol>
    </div>
    <template #footer>
      <el-button type="primary" @click="handleConfirm">
        {{ t('login.warningAcknowledged') }}
      </el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'

const WARN_STORAGE_KEY = 'easynode_warn_shown'
const { t } = useI18n()

const visible = ref(false)

const handleConfirm = () => {
  localStorage.setItem(WARN_STORAGE_KEY, 'true')
  visible.value = false
}

const subTg = () => {
  window.open('https://t.me/easynode_notify', '_blank')
}

const handleClosed = () => {
  // 弹窗关闭后的回调
}

onMounted(() => {
  const hasShown = localStorage.getItem(WARN_STORAGE_KEY)
  if (!hasShown) {
    visible.value = true
  }
})
</script>

<style lang="scss" scoped>
.warn-content {
  ol {
    padding-left: 20px;
    margin: 0;

    li {
      line-height: 2;
      margin-bottom: 8px;
      color: #606266;

      .highlight {
        color: #e6a23c;
        font-weight: 600;
      }
      .point {
        color: #409eff;
        cursor: pointer;
        text-decoration: underline;
      }
    }
  }
}

:deep(.el-dialog__header) {
  .el-dialog__title {
    color: #e6a23c;
    font-weight: 600;
  }
}
</style>