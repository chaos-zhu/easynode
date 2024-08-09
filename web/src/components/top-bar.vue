<template>
  <div class="top_bar_container">
    <div class="bar_wrap">
      <h2>{{ title }}</h2>
      <!-- <el-icon><UserFilled /></el-icon> -->
      <el-button
        type="info"
        class="about_btn top_text"
        link
        @click="visible = true"
      >
        关于 <span class="link">{{ isNew ? `(新版本可用)` : '' }}</span>
      </el-button>
      <el-dropdown trigger="click">
        <span class="username top_text"><el-icon><User /></el-icon> {{ user }}</span>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="handleLogout">
              退出登录
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>

    <el-dialog
      v-model="visible"
      title="关于"
      width="30%"
      :append-to-body="false"
    >
      <div class="about_content">
        <h1>EasyNode</h1>
        <p>当前版本: {{ currentVersion }}</p>
        <p v-if="checkVersionErr" class="conspicuous">Error：版本更新检测失败(版本检测API需要外网环境)</p>
        <p v-if="isNew" class="conspicuous">
          有新版本可用: {{ latestVersion }} -> <a class="link" href="https://github.com/chaos-zhu/easynode/releases" target="_blank">https://github.com/chaos-zhu/easynode/releases</a>
        </p>
        <p>作者: <a class="link" href="https://github.com/chaos-zhu" target="_blank">ChaosZhu</a></p>
        <p>开源仓库: <a class="link" href="https://github.com/chaos-zhu/easynode" target="_blank">https://github.com/chaos-zhu/easynode</a></p>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, getCurrentInstance, computed } from 'vue'
import { User } from '@element-plus/icons-vue'
import packageJson from '../../package.json'

const { proxy: { $router, $store, $message } } = getCurrentInstance()

let visible = ref(false)
let checkVersionErr = ref(false)
let currentVersion = ref(`v${ packageJson.version }`)
let latestVersion = ref(null)

let isNew = computed(() => {
  return latestVersion.value && latestVersion.value !== currentVersion.value
})

async function checkLatestVersion() {
  const timeout = 3000
  try {
    const timeoutPromise = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('请求超时')), timeout)
    )
    const fetchPromise = fetch('https://production.get-easynode-latest-version.chaoszhu.workers.dev/version')

    const response = await Promise.race([fetchPromise, timeoutPromise,])
    if (!response.ok) {
      throw new Error('版本信息请求失败: ' + response.statusText)
    }
    const data = await response.json()
    latestVersion.value = data.tag_name
  } catch (error) {
    checkVersionErr.value = true
    console.error('版本信息请求失败:', error.message)
  }
}

checkLatestVersion()

let user = computed(() => {
  return $store.user
})

let title = computed(() => {
  return $store.title
})

const handleLogout = () => {
  $store.clearJwtToken()
  $message({ type: 'success', message: '已安全退出', center: true })
  $router.push('/login')
}
</script>

<style lang="scss" scoped>
.top_bar_container {
  height: 60px;
  background-color: #fff;
  box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1);
  position: sticky;
  top: 0;
  z-index: 999;
  .bar_wrap {
    height: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 20px;
    h2 {
      font-size: 18px;
      margin-right: auto;
    }
    .username {
      margin-left: 10px;
      cursor: pointer;
    }
    .top_text {
      color: var(--el-menu-text-color);
      font-size: 14px;
    }
  }
  .about_content {
    h1 {
      font-size: 18px;
      font-weight: 600;
      margin: 15px 0;
    }
    p {
      line-height: 35px;
    }
    .conspicuous {
      color: red;
    }
  }
}
</style>