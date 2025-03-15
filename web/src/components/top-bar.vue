<template>
  <div class="top_bar_container">
    <div class="bar_wrap">
      <div class="mobile_menu_btn">
        <el-icon @click="handleCollapse">
          <Fold />
        </el-icon>
      </div>
      <h2>{{ title }}</h2>
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
        版本更新 <span class="new_version">{{ isNew ? `(新版本可用)` : '' }}</span>
      </el-button>
      <el-dropdown trigger="click">
        <span class="username_wrap">
          <el-icon>
            <User />
          </el-icon>
          <span class="username">{{ user }}</span>
        </span>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="handleLogout">
              退出登录
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <div class="plus_icon_wrapper" @click="gotoPlusPage">
        <img
          class="plus_icon"
          src="@/assets/plus.png"
          alt="PLUS"
          :style="{ filter: isPlusActive ? 'grayscale(0%)' : 'grayscale(100%)' }"
        >
        <img
          v-if="!isPlusActive && discount"
          class="discount_badge"
          src="@/assets/discount.png"
          alt="Discount"
        >
      </div>
    </div>

    <el-dialog
      v-model="visible"
      title="版本更新"
      top="20vh"
      width="30%"
      :append-to-body="false"
      :close-on-click-modal="false"
    >
      <div class="about_content">
        <!-- <h1>EasyNode</h1> -->
        <p>当前版本: {{ currentVersion }} <span v-show="!isNew">(最新)</span> </p>
        <p v-if="checkVersionErr" class="conspicuous">Error：版本更新检测失败(版本检测API需要外网环境),请手动访问GitHub查看</p>
        <p v-if="isNew" class="conspicuous">
          新版本可用: {{ latestVersion }} -> <a
            class="link"
            href="https://github.com/chaos-zhu/easynode?tab=readme-ov-file#%E9%A1%B9%E7%9B%AE%E9%83%A8%E7%BD%B2"
            target="_blank"
          >https://github.com/chaos-zhu/easynode</a>
        </p>
        <template v-if="features.length > 0 && isNew">
          <div class="version_features_title">
            <el-icon><Document /></el-icon>
            新版本更新了以下内容:
          </div>
          <ul class="conspicuous feature_list">
            <li v-for="feature in features" :key="feature">
              {{ feature }}
            </li>
          </ul>
        </template>
        <p>
          TG更新通知频道：<a class="link" href="https://t.me/easynode_notify" target="_blank">https://t.me/easynode_notify</a>
        </p>
        <p>
          项目地址：<a
            class="link"
            href="https://github.com/chaos-zhu/easynode"
            target="_blank"
          >https://github.com/chaos-zhu/easynode</a>
        </p>
        <div class="about_footer">
          <el-button type="info" @click="visible = false">关闭</el-button>
        </div>
      </div>
    </el-dialog>

    <el-drawer
      v-model="menuCollapse"
      :with-header="false"
      direction="ltr"
      class="mobile_menu_drawer"
    >
      <div class="mobile_logo_wrap">
        <img src="@/assets/logo.png" alt="logo">
        <h1>EasyNode</h1>
      </div>
      <MenuList @select="() => menuCollapse = false" />
    </el-drawer>
  </div>
</template>

<script setup>
import { ref, getCurrentInstance, computed, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { User, Sunny, Moon, Fold, Document } from '@element-plus/icons-vue'
import packageJson from '../../package.json'
import MenuList from './menuList.vue'

const { proxy: { $router, $store, $api, $message } } = getCurrentInstance()
const router = useRouter()
const visible = ref(false)
const checkVersionErr = ref(false)
const currentVersion = ref(`v${ packageJson.version }`)
const latestVersion = ref(null)
const features = ref([])
const menuCollapse = ref(false)
const discount = ref(false)

const isNew = computed(() => latestVersion.value && latestVersion.value !== currentVersion.value)
const user = computed(() => $store.user)
const title = computed(() => $store.title)
const isPlusActive = computed(() => $store.isPlusActive)

const isDark = computed({
  get: () => $store.isDark,
  set: (isDark) => {
    $store.setTheme(isDark)
  }
})

const handleCollapse = () => {
  menuCollapse.value = !menuCollapse.value
}

const handleLogout = () => {
  $store.removeJwtToken()
  $message({ type: 'success', message: '已安全退出', center: true })
  $router.push('/login')
}

const gotoPlusPage = () => {
  router.push('/setting?tabKey=plus')
}

async function checkLatestVersionByGitRelease() {
  const timeout = 5000
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

async function checkLatestVersionByJson() {
  const timeout = 5000
  try {
    let date = new Date()
    let lastGetVersionTime = localStorage.getItem('lastGetVersionTime')
    // 10分钟内不重复请求
    if (lastGetVersionTime && (date.getTime() - Number(lastGetVersionTime) < 1000 * 60 * 10)) {
      let latestVersionFromLocal = localStorage.getItem('latestVersion')
      let featuresFromLocal = localStorage.getItem('features')
      if (latestVersionFromLocal && featuresFromLocal) {
        latestVersion.value = latestVersionFromLocal
        features.value = JSON.parse(featuresFromLocal)
        return
      }
    }

    const timeoutPromise = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('请求超时')), timeout)
    )
    const url = `https://git.221022.xyz/https://raw.githubusercontent.com/chaos-zhu/easynode/refs/heads/main/server/version.json?ts=${ new Date().getTime() }`
    const fetchPromise = fetch(url)
    const response = await Promise.race([fetchPromise, timeoutPromise,])
    if (!response.ok) {
      throw new Error('版本信息请求失败: ' + response.statusText)
    }
    const releases = await response.json()
    // console.log('releases:', releases)
    if (Array.isArray(releases) && releases.length > 0) {
      latestVersion.value = releases[0].version
      features.value = releases[0].features
      localStorage.setItem('lastGetVersionTime', date.getTime())
      localStorage.setItem('latestVersion', latestVersion.value)
      localStorage.setItem('features', JSON.stringify(features.value))
    }
  } catch (error) {
    checkVersionErr.value = true
    console.error('版本信息请求失败:', error.message)
    checkLatestVersionByGitRelease()
  }
}

checkLatestVersionByJson()

let timer = null
const checkFirstVisit = () => {
  timer = setTimeout(() => {
    const visitedVersion = localStorage.getItem('visitedVersion')
    if (!visitedVersion || visitedVersion !== currentVersion.value) {
      visible.value = true
      localStorage.setItem('visitedVersion', currentVersion.value)
    }
  }, 1500)
}

const getPlusDiscount = async () => {
  const { data } = await $api.getPlusDiscount()
  if (data?.discount) {
    discount.value = data.discount
  }
}

onMounted(() => {
  checkFirstVisit()
  getPlusDiscount()
})

onBeforeUnmount(() => {
  clearTimeout(timer)
})
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
        text-decoration: underline;
      }
    }

    .username_wrap {
      display: flex;
      align-items: center;

      .username {
        cursor: pointer;
        margin-left: 5px;
      }
    }

    .plus_icon_wrapper {
      margin-left: 15px;
      display: flex;
      align-items: center;
      cursor: pointer;

      .plus_icon {
        width: 35px;
        margin-right: 5px;
      }

      .discount_badge {
        width: 22px;
        color: white;
        font-size: 12px;
        transform: rotate(25deg);
        border-radius: 4px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        animation: pulse 2s infinite;
      }
    }
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
    .feature_list {
      li {
        list-style: none;
        margin-left: 20px;
        padding: 6px 0;
        line-height: 1.5;
        position: relative;
        counter-increment: feature-counter;

        &::before {
          content: counter(feature-counter);
          position: absolute;
          left: -25px;
          top: 50%;
          transform: translateY(-50%);
          width: 18px;
          height: 18px;
          background: #F56C6C;
          color: white;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 12px;
        }

        &:not(:last-child) {
          border-bottom: 1px dashed rgba(245, 108, 108, 0.2);
        }
      }
    }

    .version_features_title {
      display: flex;
      align-items: center;
      color: #F56C6C;
      font-weight: 500;
      margin: 15px 0 10px;
      padding-bottom: 10px;
      border-bottom: 2px solid rgba(245, 108, 108, 0.2);

      .el-icon {
        margin-right: 6px;
        font-size: 16px;
      }
    }
  }

  .about_footer {
    margin-top: 20px;
    text-align: center;
  }
}

@keyframes pulse {
  0% {
    transform: rotate(25deg) scale(1);
  }
  50% {
    transform: rotate(25deg) scale(1.1);
  }
  100% {
    transform: rotate(25deg) scale(1);
  }
}
</style>

<style lang="scss">
.plus_content_wrap {
  .plus_status {
    margin-bottom: 15px;
    padding-bottom: 15px;
    border-bottom: 1px solid #eee;

    .status_header {
      display: flex;
      align-items: center;
      color: #67c23a;
      margin-bottom: 10px;

      .el-icon {
        margin-right: 5px;
      }
    }

    .status_info {
      .info_item {
        display: flex;
        margin: 5px 0;
        font-size: 13px;

        .label {
          color: #909399;
          width: 80px;
        }

        .holder {
          color: #EED183;
        }

        &.ip_list {
          flex-direction: column;

          .ip_tags {
            margin-top: 5px;

            .ip_tag {
              margin: 2px;
            }
          }
        }
      }
    }
  }

  .plus_benefits {
    position: relative;

    .support_btn {
      position: absolute;
      right: 0;
      top: 0;
      padding: 4px 12px;
      background-color: #409eff;
      color: white;
      border-radius: 4px;
      font-size: 12px;
      cursor: pointer;
      transition: all 0.3s;

      &:hover {
        background-color: #66b1ff;
      }
    }

    .benefits_header {
      display: flex;
      align-items: center;
      font-weight: bold;
      margin-bottom: 10px;

      .el-icon {
        color: #e6a23c;
        margin-right: 5px;
      }
    }

    .current_benefits {
      margin-bottom: 15px;

      .benefit_item {
        display: flex;
        align-items: center;
        margin: 8px 0;
        font-size: 13px;

        .el-icon {
          margin-right: 5px;
          color: #409eff;
        }
      }
    }

    .coming_soon {
      .soon_header {
        font-size: 13px;
        color: #909399;
        margin-bottom: 8px;
      }
    }
  }

  .discount_content {
    margin: 8px 0;

    .el-tag {
      display: flex;
      align-items: center;
      padding: 6px 12px;

      .el-icon {
        margin-right: 4px;
      }
    }
  }
}
</style>