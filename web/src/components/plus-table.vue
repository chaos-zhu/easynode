<template>
  <div class="comparison-container">
    <!-- 基础版卡片 -->
    <el-card class="comparison-card basic-card">
      <template #header>
        <div class="card-header">
          <span class="title">基础功能(免费)</span>
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

    <!-- Plus版卡片 -->
    <el-card class="comparison-card plus-card">
      <template #header>
        <div class="card-header">
          <div>
            <span class="title">Plus专属功能</span>
            <span class="link" style="margin-right: 15px;" @click="() => plusTipsShow = true">Plus说明</span>
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
      title="Plus说明"
      top="20vh"
      width="30%"
      :append-to-body="false"
      :close-on-click-modal="false"
    >
      <div class="about_content">
        <p style="line-height: 2;letter-spacing: 1px;">
          <!-- <strong style="color: #F56C6C;font-weight: 600;">PLUS说明:</strong><br> -->
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<strong>EasyNode</strong>最初是一个简单的Web终端工具，随着用户群的不断扩大，功能需求也日益增长，为了实现大家的功能需求，我投入了大量的业余时间进行开发和维护。
          一直在为爱发电，渐渐的也没了开发的动力。
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;为了项目的可持续发展，<strong>后续</strong>版本开始推出<strong>PLUS</strong>版本，后续特性功能开发也会优先在<strong>PLUS</strong>版本中实现，但即使不升级到<strong>PLUS</strong>，也不会影响到<strong>EasyNode</strong>的基础功能使用【注意:
          暂不支持纯内网用户激活PLUS功能】。
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="text-decoration: underline;">
            为了感谢前期赞赏过的用户, 在<strong>PLUS</strong>功能正式发布前，所有进行过赞赏的用户，无论金额大小，均可联系作者TG: <a
class="link"
              href="https://t.me/chaoszhu"
target="_blank"
>@chaoszhu</a> 凭打赏记录免费获取永久<strong>PLUS</strong>授权码。
          </span>
        </p>
        <div class="about_footer">
          <el-button type="info" @click="plusTipsShow = false">关闭</el-button>
          <el-button type="primary" @click="handlePlusSupport">购买Plus Key</el-button>
        </div>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { Check } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'

const plusTipsShow = ref(false)

// 基础版功能列表
const basicFeatures = [
  '服务器管理',
  '服务器导入导出',
  '服务器分组',
  '凭据管理',
  '脚本库',
  '批量连接',
  '批量指令',
  '通知方式(有限制)',
]

// Plus版专属功能列表
const plusFeatures = [
  '包含基础版全部功能',
  '服务器跳板机功能,支持任意数量服务器的连续跳板',
  '批量修改实例配置(优化版)',
  '脚本库批量导出导入',
  '凭据管理支持解密带密码保护的密钥',
  '通知方式无限制',
  '本地socket断开自动重连',
  '功能需求更高开发优先级',
]
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
