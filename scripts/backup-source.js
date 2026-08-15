const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const projectRoot = path.resolve(__dirname, '..')
const projectName = path.basename(projectRoot)
const projectParent = path.dirname(projectRoot)
const backupDir = projectParent

// Only downloaded dependencies, generated build content and caches are
// excluded. This intentionally does not read .gitignore, so the complete .git
// repository, local scripts, ignored Plus source, databases, environment files
// and signing files are all included in the backup.
const excludedDirectoryNames = new Set([
  '.agents',
  '.cache',
  '.cxx',
  '.dart_tool',
  '.gradle',
  '.hvigor',
  '.idea',
  '.next',
  '.nuxt',
  '.output',
  '.parcel-cache',
  '.pub',
  '.pub-cache',
  '.swiftpm',
  '.vite',
  'Pods',
  'DerivedData',
  'backups',
  'build',
  'coverage',
  'dist',
  'dist-ssr',
  'node_modules',
  'oh_modules'
])

const excludedDirectoryPaths = new Set([
  'native/ios/.symlinks',
  'native/linux/flutter/ephemeral',
  'native/macos/Flutter/ephemeral',
  'native/ohos/entry/libs',
  'native/ohos/entry/src/main/resources/rawfile/flutter_assets',
  'native/windows/flutter/ephemeral',
  'server/app/socket/sftp-cache',
  'server/app/static'
])

const excludedFilePaths = new Set([
  'easynode-server.zip',
  'native/.flutter-plugins-dependencies',
  'native/android/gradle/wrapper/gradle-wrapper.jar',
  'native/ios/Flutter/Flutter.podspec',
  'native/ios/Flutter/Generated.xcconfig',
  'native/ios/Flutter/flutter_export_environment.sh'
])

function toArchivePath(relativePath) {
  return `${projectName}/${relativePath.split(path.sep).join('/')}`
}

function isExcludedDirectory(relativePath, name) {
  const normalizedPath = relativePath.split(path.sep).join('/')
  return excludedDirectoryNames.has(name) || excludedDirectoryPaths.has(normalizedPath)
}

function isExcludedFile(relativePath, name) {
  const normalizedPath = relativePath.split(path.sep).join('/')

  if (excludedFilePaths.has(normalizedPath)) return true
  if (name === '.DS_Store' || name.endsWith('.iml')) return true
  if (/^GeneratedPluginRegistrant\./.test(name)) return true

  return false
}

function collectFiles(directory, relativeDirectory = '') {
  const files = []

  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const relativePath = path.join(relativeDirectory, entry.name)
    const absolutePath = path.join(directory, entry.name)

    if (entry.isDirectory()) {
      if (!isExcludedDirectory(relativePath, entry.name)) {
        files.push(...collectFiles(absolutePath, relativePath))
      }
      continue
    }

    if (!isExcludedFile(relativePath, entry.name)) {
      files.push(toArchivePath(relativePath))
    }
  }

  return files
}

function collectTrackedFiles() {
  const result = spawnSync('git', ['ls-files', '-z'], {
    cwd: projectRoot,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024
  })

  if (result.error) throw result.error
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || '无法读取 Git 已跟踪文件列表')
  }

  return result.stdout
    .split('\0')
    .filter(Boolean)
    .filter((relativePath) => {
      try {
        fs.lstatSync(path.join(projectRoot, relativePath))
        return true
      } catch (error) {
        if (error.code === 'ENOENT') return false
        throw error
      }
    })
    .map(toArchivePath)
}

function formatTimestamp(date) {
  const part = (value) => String(value).padStart(2, '0')
  return [
    date.getFullYear(),
    part(date.getMonth() + 1),
    part(date.getDate()),
    '_',
    part(date.getHours()),
    part(date.getMinutes()),
    part(date.getSeconds())
  ].join('')
}

function main() {
  // A tracked file always wins over an exclusion rule. This keeps the extracted
  // worktree complete even when a framework tracks a generated-looking file.
  const files = [...new Set([
    ...collectFiles(projectRoot),
    ...collectTrackedFiles()
  ])].sort()

  if (files.length === 0) {
    throw new Error('没有找到需要备份的文件')
  }

  const invalidPath = files.find((file) => file.includes('\n'))
  if (invalidPath) {
    throw new Error(`文件名包含换行符，无法安全打包：${invalidPath}`)
  }

  fs.mkdirSync(backupDir, { recursive: true })

  const timestamp = formatTimestamp(new Date())
  let archivePath = path.join(backupDir, `easynode_${timestamp}.zip`)
  let suffix = 2

  while (fs.existsSync(archivePath)) {
    archivePath = path.join(backupDir, `easynode_${timestamp}_${suffix}.zip`)
    suffix += 1
  }

  const result = spawnSync('zip', ['-q', '-9', '-y', archivePath, '-@'], {
    cwd: projectParent,
    encoding: 'utf8',
    input: `${files.join('\n')}\n`,
    maxBuffer: 10 * 1024 * 1024
  })

  if (result.error && result.error.code === 'ENOENT') {
    throw new Error('未找到 zip 命令，请先安装 zip')
  }

  if (result.error) throw result.error
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `zip 执行失败，退出码：${result.status}`)
  }

  const size = fs.statSync(archivePath).size
  const sizeInMb = (size / 1024 / 1024).toFixed(2)

  console.log(`备份完成：${archivePath}`)
  console.log(`文件数量：${files.length}，压缩包大小：${sizeInMb} MB`)
}

try {
  main()
} catch (error) {
  console.error(`备份失败：${error.message}`)
  process.exitCode = 1
}
