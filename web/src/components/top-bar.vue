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
        关于 <span class="new_version">{{ isNew ? `(新版本可用)` : '' }}</span>
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

      <el-popover placement="left" :width="320" trigger="hover">
        <template #reference>
          <img
            class="plus_icon"
            src="@/assets/plus.png"
            alt="PLUS"
            :style="{ filter: isPlusActive ? 'grayscale(0%)' : 'grayscale(100%)' }"
          >
        </template>
        <template #default>
          <div class="plus_content_wrap">
            <!-- Plus 激活状态信息 -->
            <div v-if="isPlusActive" class="plus_status">
              <div class="status_header">
                <el-icon>
                  <CircleCheckFilled />
                </el-icon>
                <span>Plus专属功能已激活</span>
              </div>
              <div class="status_info">
                <div class="info_item">
                  <span class="label">到期时间:</span>
                  <span class="value holder">{{ plusInfo.expiryDate }}</span>
                </div>
                <div class="info_item">
                  <span class="label">授权IP数:</span>
                  <span class="value">{{ plusInfo.maxIPs }}</span>
                </div>
                <div class="info_item">
                  <span class="label">已授权IP数:</span>
                  <span class="value">{{ plusInfo.usedIPCount }}</span>
                </div>
                <div class="info_item ip_list">
                  <span class="label">已授权IP:</span>
                  <div class="ip_tags">
                    <el-tag
                      v-for="ip in plusInfo.usedIPs"
                      :key="ip"
                      size="small"
                      class="ip_tag"
                    >
                      {{ ip }}
                    </el-tag>
                  </div>
                </div>
              </div>
            </div>

            <div class="plus_benefits" :class="{ active: isPlusActive }" @click="handlePlus">
              <span v-if="!isPlusActive" class="support_btn" @click="handlePlusSupport">去支持</span>
              <div class="benefits_header">
                <el-icon>
                  <el-icon><StarFilled /></el-icon>
                </el-icon>
                <span>Plus功能介绍</span>
              </div>
              <div class="current_benefits">
                <div v-for="plusFeature in plusFeatures" :key="plusFeature" class="benefit_item">
                  <el-icon>
                    <Star />
                  </el-icon>
                  <span>{{ plusFeature }}</span>
                </div>
              </div>

              <div class="coming_soon">
                <div class="soon_header">开发中的PLUS功能</div>
                <div class="current_benefits">
                  <div v-for="soonFeature in soonFeatures" :key="soonFeature" class="benefit_item">
                    <el-icon>
                      <Star />
                    </el-icon>
                    <span>{{ soonFeature }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </template>
      </el-popover>
    </div>

    <el-dialog
      v-model="visible"
      title="关于"
      top="10vh"
      width="30%"
      :append-to-body="false"
    >
      <div class="about_content">
        <h1>EasyNode</h1>
        <p>当前版本: {{ currentVersion }} <span v-show="!isNew">(最新)</span> </p>
        <p v-if="checkVersionErr" class="conspicuous">Error：版本更新检测失败(版本检测API需要外网环境)</p>
        <p v-if="isNew" class="conspicuous">
          新版本可用: {{ latestVersion }} -> <a
            class="link"
            href="https://github.com/chaos-zhu/easynode/releases"
            target="_blank"
          >https://github.com/chaos-zhu/easynode/releases</a>
        </p>
        <p>
          更新日志：<a
            class="link"
            href="https://github.com/chaos-zhu/easynode/blob/main/CHANGELOG.md"
            target="_blank"
          >https://github.com/chaos-zhu/easynode/blob/main/CHANGELOG.md</a>
        </p>
        <p>
          tg更新通知：<a class="link" href="https://t.me/easynode_notify" target="_blank">https://t.me/easynode_notify</a>
        </p>
        <p style="line-height: 2;letter-spacing: 1px;">
          <strong style="color: #F56C6C;font-weight: 600;">PLUS说明:</strong><br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<strong>EasyNode</strong>最初是一个简单的Web终端工具，随着用户群的不断扩大，功能需求也日益增长，为了实现大家的功能需求，我投入了大量的业余时间进行开发和维护。
          一直在为爱发电，渐渐的也没了开发的动力。
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;为了项目的可持续发展，从<strong>3.0.0</strong>版本开始推出了<strong>PLUS</strong>版本，具体特性鼠标悬浮右上角PLUS图标查看，后续特性功能开发也会优先在<strong>PLUS</strong>版本中实现，但即使不升级到<strong>PLUS</strong>，也不会影响到<strong>EasyNode</strong>的基础功能使用【注意: 暂不支持纯内网用户激活PLUS功能】。
          <br>
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="text-decoration: underline;">
            为了感谢前期赞赏过的用户, 在<strong>PLUS</strong>功能正式发布前，所有进行过赞赏的用户，无论金额大小，均可联系作者TG: <a class="link" href="https://t.me/chaoszhu" target="_blank">@chaoszhu</a> 凭打赏记录获取永久<strong>PLUS</strong>授权码。
          </span>
        </p>
        <div v-if="!isPlusActive" class="about_footer">
          <el-button type="primary" @click="handlePlusSupport">去支持</el-button>
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
import { ref, getCurrentInstance, computed } from 'vue'
import { User, Sunny, Moon, Fold, CircleCheckFilled, Star, StarFilled } from '@element-plus/icons-vue'
import packageJson from '../../package.json'
import MenuList from './menuList.vue'

const { proxy: { $router, $store, $message } } = getCurrentInstance()

const visible = ref(false)
const checkVersionErr = ref(false)
const currentVersion = ref(`v${ packageJson.version }`)
const latestVersion = ref(null)
const menuCollapse = ref(false)

const plusFeatures = [
  '跳板机功能,拯救被墙实例与龟速终端输入',
  '本地socket断开自动重连,无需手动重新连接',
  '脚本库批量导出导入',
  '凭据管理支持解密带密码保护的密钥',
  '提出的功能需求享有更高的开发优先级',
]
const soonFeatures = [
  '终端脚本变量及终端脚本输入优化',
  '终端分屏功能',
  '系统操作日志审计',
]

const isNew = computed(() => latestVersion.value && latestVersion.value !== currentVersion.value)
const user = computed(() => $store.user)
const title = computed(() => $store.title)
const plusInfo = computed(() => $store.plusInfo)
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

const handlePlusSupport = () => {
  window.open('https://en.221022.xyz/buy-plus', '_blank')
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

    .username_wrap {
      display: flex;
      align-items: center;

      .username {
        cursor: pointer;
        margin-left: 5px;
      }
    }

    .plus_icon {
      margin-left: 15px;
      width: 35px;
      cursor: pointer;
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
  }

  .about_footer {
    margin-top: 20px;
    text-align: center;
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
}
</style>