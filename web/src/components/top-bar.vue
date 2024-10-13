<template>
  <div class="top_bar_container">
    <div class="bar_wrap">
      <h2>{{ title }}</h2>
      <!-- <el-icon><UserFilled /></el-icon> -->
      <el-switch
        v-model="isDark"
        inline-prompt
        :active-icon="Moon"
        :inactive-icon="Sunny"
        class="dark_switch"
      />
      <el-button
        type="info"
        class="about_btn"
        link
        @click="visible = true"
      >
        关于 <span class="new_version">{{ isNew ? `(新版本可用)` : '' }}</span>
      </el-button>
      <el-dropdown trigger="click">
        <span class="username"><el-icon><User /></el-icon> {{ user }}</span>
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
        <p>当前版本: {{ currentVersion }} <span v-show="!isNew">(最新)</span> </p>
        <p v-if="checkVersionErr" class="conspicuous">Error：版本更新检测失败(版本检测API需要外网环境)</p>
        <p v-if="isNew" class="conspicuous">
          新版本可用: {{ latestVersion }} -> <a class="link" href="https://github.com/chaos-zhu/easynode/releases" target="_blank">https://github.com/chaos-zhu/easynode/releases</a>
        </p>
        <p>更新日志：<a class="link" href="https://github.com/chaos-zhu/easynode/blob/main/CHANGELOG.md" target="_blank">https://github.com/chaos-zhu/easynode/blob/main/CHANGELOG.md</a></p>
        <p>开源仓库: <a class="link" href="https://github.com/chaos-zhu/easynode" target="_blank">https://github.com/chaos-zhu/easynode</a></p>
        <p>作者: <a class="link" href="https://github.com/chaos-zhu" target="_blank">chaoszhu</a></p>
        <p>tg更新通知：<a class="link" href="https://t.me/easynode_notify" target="_blank">https://t.me/easynode_notify</a></p>
        <p>
          打赏: EasyNode开源且无任何收费，如果您认为此项目帮到了您, 您可以请我喝杯阔乐(记得留个备注)~
        </p>
        <p class="qrcode">
          <img src="@/assets/wx.jpg" alt="">
        </p>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, getCurrentInstance, computed } from 'vue'
import { User, Sunny, Moon } from '@element-plus/icons-vue'
import packageJson from '../../package.json'

const { proxy: { $router, $store, $message } } = getCurrentInstance()

let visible = ref(false)
let checkVersionErr = ref(false)
let currentVersion = ref(`v${ packageJson.version }`)
let latestVersion = ref(null)

let isNew = computed(() => latestVersion.value && latestVersion.value !== currentVersion.value)
let user = computed(() => $store.user)
let title = computed(() => $store.title)
let isDark = computed({
  get: () => $store.isDark,
  set: (isDark) => {
    $store.setTheme(isDark)
  }
})

const handleLogout = () => {
  $store.clearJwtToken()
  $message({ type: 'success', message: '已安全退出', center: true })
  $router.push('/login')
}

async function checkLatestVersion() {
  const timeout = 3000
  try {
    const timeoutPromise = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('请求超时')), timeout)
    )

    const url = `https://api.github.com/repos/chaos-zhu/easynode/releases?ts=${ new Date().getTime() }`
    const fetchPromise = fetch(url, {
      headers: {
        'Accept': 'application/vnd.github.v3+json'
      }
    })

    const response = await Promise.race([fetchPromise, timeoutPromise,])
    if (!response.ok) {
      throw new Error('版本信息请求失败: ' + response.statusText)
    }

    const releases = await response.json()
    // console.log('releases:', releases)
    const filteredReleases = releases.filter(release => !release.tag_name.startsWith('client'))
    if (filteredReleases.length > 0) {
      latestVersion.value = filteredReleases[0].tag_name
    }
  } catch (error) {
    checkVersionErr.value = true
    console.error('版本信息请求失败:', error.message)
  }
}

checkLatestVersion()

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
    .dark_switch {
      margin-right: 15px;
    }
    .about_btn {
      margin-right: 15px;
      font-size: 14px;
      .new_version {
        color: red;
      }
    }
    .username {
      cursor: pointer;
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
    .qrcode {
      text-align: center;
      img {
        width: 250px;
      }
    }
    .conspicuous {
      color: red;
    }
  }
}
</style>