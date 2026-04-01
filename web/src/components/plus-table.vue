<template>
  <div class="comparison-container">
    <el-card class="comparison-card basic-card">
      <template #header>
        <div class="card-header">
          <span class="title">{{ t('plusTable.basicTitle') }}</span>
          <el-tag size="small">Basic</el-tag>
        </div>
      </template>
      <div class="feature-list">
        <div v-for="(feature, index) in basicFeatures" :key="index" class="feature-item">
          <el-icon>
            <Check />
          </el-icon>
          <span>{{ feature }}</span>
        </div>
      </div>
    </el-card>

    <el-card class="comparison-card plus-card">
      <template #header>
        <div class="card-header">
          <div>
            <span class="title">{{ t('plusTable.plusTitle') }}</span>
            <span class="link" style="margin-right: 15px;" @click="() => plusTipsShow = true">{{ t('plusTable.plusDescription') }}</span>
          </div>
          <el-tag type="success" size="small">PLUS</el-tag>
        </div>
      </template>
      <div class="feature-list">
        <div v-for="(feature, index) in plusFeatures" :key="index" class="feature-item plus">
          <el-icon color="#67c23a">
            <Check />
          </el-icon>
          <span>{{ feature }}</span>
        </div>
      </div>
    </el-card>
    <el-dialog
      v-model="plusTipsShow"
      :title="t('plusTable.plusDescription')"
      top="20vh"
      width="30%"
      :append-to-body="false"
      :close-on-click-modal="false"
    >
      <div class="about_content">
        <p style="line-height: 2;letter-spacing: 1px;">
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<strong>EasyNode</strong>{{ t('plusTable.intro1') }}
          {{ t('plusTable.intro2') }}
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{{ t('plusTable.intro3') }}
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
          {{ t('plusTable.intro4') }}
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
          <span style="text-decoration: underline;">
            {{ t('plusTable.intro5Prefix') }}<a
              class="link"
              href="https://t.me/chaoszhu"
              target="_blank"
            >@chaoszhu</a>{{ t('plusTable.intro5Suffix') }}
          </span>
        </p>
        <div class="about_footer">
          <el-button type="info" @click="plusTipsShow = false">{{ t('plusTable.close') }}</el-button>
          <el-button type="primary" @click="handlePlusSupport">{{ t('plusTable.getPlusKey') }}</el-button>
        </div>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { Check } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'

const plusTipsShow = ref(false)
const { t } = useI18n()

const basicFeatures = computed(() => [
  t('plusTable.basicFeatures.serverManagement'),
  t('plusTable.basicFeatures.serverImportExport'),
  t('plusTable.basicFeatures.serverGrouping'),
  t('plusTable.basicFeatures.credentials'),
  t('plusTable.basicFeatures.scriptLibrary'),
  t('plusTable.basicFeatures.batchConnect'),
  t('plusTable.basicFeatures.batchCommand'),
  t('plusTable.basicFeatures.notificationsLimited'),
])

const plusFeatures = computed(() => [
  t('plusTable.plusFeatures.aiChat'),
  t('plusTable.plusFeatures.proxyAndJumpHost'),
  t('plusTable.plusFeatures.rdp'),
  t('plusTable.plusFeatures.fileTransfer'),
  t('plusTable.plusFeatures.singleWindow'),
  t('plusTable.plusFeatures.batchModify'),
  t('plusTable.plusFeatures.scriptImportExport'),
  t('plusTable.plusFeatures.scriptGroupSupport'),
  t('plusTable.plusFeatures.dockerManager'),
  t('plusTable.plusFeatures.encryptedKey'),
  t('plusTable.plusFeatures.sessionSuspend'),
])
</script>

<style scoped lang="scss">
.comparison-container {
  display: flex;
  gap: 20px;
  padding-bottom: 20px;
  max-width: 1200px;
}

.comparison-card {
  flex: 1;
  min-width: 300px;
}

.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.title {
  font-size: 18px;
  font-weight: bold;
  margin-right: 10px;
}

.link {
  text-decoration: underline;
}

.feature-list {
  // padding: 10px 0;
  line-height: 1.3;
}

.feature-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 0;
  /* border-bottom: 1px solid #eee; */
  border-bottom: 1px solid var(--el-border-color);
}

.feature-item:last-child {
  border-bottom: none;
}

.feature-item .el-icon {
  color: #409EFF;
}

.plus-card .feature-item.plus {
  color: #67c23a;
}

.about_content {
  h1 {
    font-size: 24px;
    font-weight: 600;
    margin: 20px 0;
  }

  p {
    line-height: 1.8;
    margin: 12px 0;
    font-size: 14px;
  }

  .link {
    color: #409EFF;
    text-decoration: none;

    &:hover {
      text-decoration: underline;
    }
  }

  .conspicuous {
    color: #F56C6C;
    font-weight: 500;
  }

  .about_footer {
    display: flex;
    justify-content: center;
    margin-top: 20px;
  }
}

/* 响应式设计 */
@media (max-width: 768px) {
  .comparison-container {
    flex-direction: column;
  }

  .comparison-card {
    width: 100%;
  }
}
</style>
