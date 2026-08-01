import { computed, ref } from 'vue'
import packageJson from '../../package.json'

const CACHE_DURATION = 1000 * 60 * 10
const REQUEST_TIMEOUT = 5000
const AUTO_SHOWN_KEY = 'versionUpdateAutoShown'

function parseVersion(version) {
  const matched = String(version || '').trim().match(/^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/)
  return matched ? matched.slice(1).map(Number) : null
}

export function isVersionNewer(latestVersion, currentVersion) {
  const latest = parseVersion(latestVersion)
  const current = parseVersion(currentVersion)
  if (!latest || !current) return false

  for (let index = 0; index < latest.length; index += 1) {
    if (latest[index] !== current[index]) return latest[index] > current[index]
  }
  return false
}

async function fetchJson(url, headers = {}) {
  const controller = new AbortController()
  const timer = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT)
  try {
    const response = await fetch(url, { headers, signal: controller.signal })
    if (!response.ok) throw new Error(`版本信息请求失败: ${ response.statusText }`)
    return await response.json()
  } finally {
    window.clearTimeout(timer)
  }
}

export default function useVersionUpdate() {
  const visible = ref(false)
  const checking = ref(false)
  const checkVersionErr = ref(false)
  const currentVersion = ref(`v${ packageJson.version }`)
  const latestVersion = ref('')
  const features = ref([])

  const isNew = computed(() => isVersionNewer(latestVersion.value, currentVersion.value))

  function applyVersion(version, nextFeatures = []) {
    latestVersion.value = version || ''
    features.value = Array.isArray(nextFeatures) ? nextFeatures : []
  }

  function readCache() {
    const lastCheckedAt = Number(localStorage.getItem('lastGetVersionTime'))
    if (!lastCheckedAt || Date.now() - lastCheckedAt >= CACHE_DURATION) return false

    const cachedVersion = localStorage.getItem('latestVersion')
    if (!cachedVersion) return false

    let cachedFeatures = []
    try {
      cachedFeatures = JSON.parse(localStorage.getItem('features') || '[]')
    } catch (error) {
      console.warn('读取版本更新缓存失败:', error.message)
    }
    applyVersion(cachedVersion, cachedFeatures)
    return true
  }

  function writeCache() {
    localStorage.setItem('lastGetVersionTime', String(Date.now()))
    localStorage.setItem('latestVersion', latestVersion.value)
    localStorage.setItem('features', JSON.stringify(features.value))
  }

  async function checkByVersionJson() {
    const url = `https://easynode-version.chaoszhu.com/chaos-zhu/easynode/refs/heads/main/server/version.json?ts=${ Date.now() }`
    const releases = await fetchJson(url)
    const latestWebRelease = Array.isArray(releases)
      ? releases.find(release => {
        const version = release?.version || ''
        return version.startsWith('v') && !version.startsWith('native-v') && !version.startsWith('client')
      })
      : null

    if (!latestWebRelease) throw new Error('未找到可用的 Web 版本信息')
    applyVersion(latestWebRelease.version, latestWebRelease.features)
  }

  async function checkByGitRelease() {
    const url = `https://api.github.com/repos/chaos-zhu/easynode/releases?ts=${ Date.now() }`
    const releases = await fetchJson(url, { Accept: 'application/vnd.github.v3+json' })
    const latestWebRelease = Array.isArray(releases)
      ? releases.find(release => {
        const tagName = release?.tag_name || ''
        return tagName.startsWith('v') && !tagName.startsWith('native-v') && !tagName.startsWith('client')
      })
      : null

    if (!latestWebRelease) throw new Error('GitHub Releases 中未找到可用的 Web 版本')
    applyVersion(latestWebRelease.tag_name)
  }

  function showNewVersionOnce() {
    if (!isNew.value || localStorage.getItem(AUTO_SHOWN_KEY) === latestVersion.value) return
    visible.value = true
    localStorage.setItem(AUTO_SHOWN_KEY, latestVersion.value)
  }

  async function checkLatestVersion() {
    if (checking.value) return
    checking.value = true
    checkVersionErr.value = false
    try {
      if (!readCache()) {
        try {
          await checkByVersionJson()
        } catch (primaryError) {
          console.warn('版本信息主接口请求失败:', primaryError.message)
          await checkByGitRelease()
        }
        writeCache()
      }
      showNewVersionOnce()
    } catch (error) {
      checkVersionErr.value = true
      console.error('版本信息请求失败:', error.message)
    } finally {
      checking.value = false
    }
  }

  return {
    visible,
    checking,
    checkVersionErr,
    currentVersion,
    latestVersion,
    features,
    isNew,
    checkLatestVersion
  }
}
