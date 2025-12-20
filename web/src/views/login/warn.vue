<template>
  <el-dialog
    v-model="visible"
    title="安全使用须知"
    width="550px"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    @closed="handleClosed"
  >
    <div class="warn-content">
      <ol>
        <li>
          1. 如果你的服务器有<span class="highlight">非常重要的数据</span>，请谨慎在公网暴露此面板。
        </li>
        <li>
          2. 善用面板提供的<span class="highlight">双重认证</span>与<span class="highlight">IP白名单</span>功能，提升面板安全性。
        </li>
        <li>
          3. <span class="highlight">不要安装来源不明的浏览器插件或者油猴脚本</span>，以防止鉴权Token泄露。
        </li>
        <li>
          4. 在公网<span class="highlight">不套用https使用此面板</span>可能会导致你的鉴权token泄露。
        </li>
        <li>
          5. <span class="highlight">及时更新面板</span>，以防止底层依赖的组件具有安全漏洞或者面板自身服务漏洞。
        </li>
        <li>
          6. 功能更新或安全信息及时通知请订阅TG频道: <span class="point" @click="subTg">点击订阅</span>。
        </li>
      </ol>
    </div>
    <template #footer>
      <el-button type="primary" @click="handleConfirm">
        我已知晓
      </el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, onMounted } from 'vue'

const WARN_STORAGE_KEY = 'easynode_warn_shown'

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