<template>
  <el-dialog
    v-model="visible"
    title="版本更新"
    top="16vh"
    :width="isMobileScreen ? '94%' : '520px'"
    append-to-body
    :close-on-click-modal="false"
  >
    <div class="version_content">
      <p>
        当前版本：{{ currentVersion }}
        <span v-if="latestVersion && !isNew && !checkVersionErr">（最新）</span>
      </p>
      <p v-if="checkVersionErr" class="error_text">
        版本更新检测失败（版本检测 API 需要外网环境），请手动访问 GitHub 查看。
      </p>
      <p v-if="isNew" class="update_text">
        新版本可用：{{ latestVersion }}
        <a
          class="link"
          href="https://github.com/chaos-zhu/easynode?tab=readme-ov-file#%E9%A1%B9%E7%9B%AE%E9%83%A8%E7%BD%B2"
          target="_blank"
        >查看部署说明</a>
      </p>

      <template v-if="features.length && isNew">
        <div class="features_title">
          <el-icon><Document /></el-icon>
          <span>最新版本更新内容（<a href="https://github.com/chaos-zhu/easynode/blob/main/CHANGELOG.md" target="_blank">更新日志</a>）</span>
        </div>
        <ol class="feature_list">
          <li v-for="feature in features" :key="feature">{{ feature }}</li>
        </ol>
      </template>

      <p>更新通知频道：<a class="link" href="https://t.me/easynode_notify" target="_blank">Telegram</a></p>
      <p>项目地址：<a class="link" href="https://github.com/chaos-zhu/easynode" target="_blank">GitHub</a></p>
    </div>

    <template #footer>
      <el-button @click="visible = false">关闭</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { Document } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'

defineProps({
  currentVersion: { type: String, required: true },
  latestVersion: { type: String, default: '' },
  features: { type: Array, default: () => [] },
  isNew: { type: Boolean, default: false },
  checkVersionErr: { type: Boolean, default: false }
})

const visible = defineModel({ type: Boolean, default: false })
const { isMobileScreen } = useMobileWidth()
</script>

<style lang="scss" scoped>
.version_content {
  p {
    margin: 10px 0;
    line-height: 1.7;
  }

  .link,
  a {
    color: var(--el-color-primary);
    text-decoration: none;
  }

  .update_text {
    color: var(--el-color-success);
    font-weight: 500;
  }

  .error_text {
    color: var(--el-color-danger);
  }

  .features_title {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 16px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--el-border-color);
    color: var(--el-color-success);
    font-weight: 500;
  }

  .feature_list {
    margin: 10px 0 16px;
    padding-left: 24px;

    li {
      padding: 4px 0;
      line-height: 1.5;
    }
  }
}
</style>
