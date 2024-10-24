<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="225px"
    modal-class="import_form_dialog"
    append-to-body
    title="导入脚本配置"
    :close-on-click-modal="false"
  >
    <h2>选择要导入的文件类型</h2>
    <ul class="type_list">
      <li @click="handleFromJson">
        <svg-icon name="icon-json" class="icon" />
        <span class="from">JSON</span>
        <input
          ref="jsonInputRef"
          type="file"
          accept=".json"
          multiple
          name="jsonInput"
          style="display: none;"
          @change="handleJsonFile"
        >
      </li>
      <li @click="manualInputVisible = true">
        <svg-icon name="icon-bianji1" class="icon" />
        <span class="from">手动输入</span>
      </li>
    </ul>
  </el-dialog>

  <el-dialog
    v-model="manualInputVisible"
    width="600px"
    top="150px"
    title="手动输入"
    :close-on-click-modal="false"
    append-to-body
  >
    <el-input
      v-model="manualInput"
      type="textarea"
      :autosize="{ minRows: 15 }"
      placeholder="请输入脚本内容，每行一条脚本"
    />
    <template #footer>
      <div class="manual-input-footer">
        <el-button @click="manualInputVisible = false">取消</el-button>
        <el-button type="primary" @click="handleManualImport">导入</el-button>
      </div>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show', 'update-list',])

const jsonInputRef = ref(null)
const manualInputVisible = ref(false)
const manualInput = ref('')

let visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

let scriptList = computed(() => $store.scriptList)

function handleFromJson() {
  jsonInputRef.value.click()
}

const handleJsonFile = (event) => {
  let files = event.target.files
  let jsonFiles = Array.from(files).filter(file => file.name.endsWith('.json'))
  if (jsonFiles.length === 0) return $message.warning('未选择有效的JSON文件')

  let readerPromises = jsonFiles.map(file => {
    return new Promise((resolve, reject) => {
      let reader = new FileReader()
      reader.onload = (e) => {
        try {
          let jsonContent = JSON.parse(e.target.result)
          resolve(jsonContent)
        } catch (error) {
          reject(new Error(`Failed to parse JSON file: ${ file.name }`))
        }
      }
      reader.onerror = () => {
        reject(new Error(`Failed to read file: ${ file.name }`))
      }
      reader.readAsText(file)
    })
  })

  Promise.all(readerPromises)
    .then(async jsonContents => {
      let formatJson = jsonContents.flat(Infinity)
      let existCommand = scriptList.value.map(item => item.command)
      let existId = scriptList.value.map(item => item.id)
      formatJson = formatJson.filter(({ _id, command }) => {
        return !existCommand.includes(command) && !existId.includes(_id)
      })
      if (formatJson.length === 0) return $message.warning('导入的脚本已存在')
      try {
        let { data: { len } } = await $api.importScript({ scripts: formatJson })
        $message({ type: 'success', center: true, message: `成功导入脚本: ${ len }条` })
        emit('update-list')
        visible.value = false
      } catch (error) {
        $message.error('导入失败: ' + error.message)
      }
    })
    .catch(error => {
      $message.error('导入失败: ' + error.message)
      console.error('导入失败: ', error)
    })
    .finally(() => {
      event.target.value = null
    })
}

const handleManualImport = async () => {
  if (!manualInput.value.trim()) {
    return $message.warning('请输入脚本内容')
  }

  try {
    let scripts = manualInput.value.split('\n')
    scripts = [...new Set(scripts),]
      .filter(line => line.trim())
      .map((command) => ({ command: command.trim() }))
    if (scripts.length === 0) {
      return $message.warning('未检测到有效的脚本内容')
    }

    let existCommand = scriptList.value.map(item => item.command)
    let filterScripts = scripts.filter(({ command }) => {
      return !existCommand.includes(command)
    })
    let filterScriptsLen = filterScripts.length
    if (filterScriptsLen !== 0 && filterScriptsLen < scripts.length) $message.warning('已过滤重复的脚本')
    if (filterScriptsLen === 0) return $message.warning('导入的脚本已存在')
    filterScripts = filterScripts.map((item, index) => {
      return {
        ...item,
        name: `${ item.command.slice(0, 15) || `脚本${ index + 1 }` }`,
        index: scriptList.value.length + index + 1,
        description: '手动输入'
      }
    })

    let { data: { len } } = await $api.importScript({ scripts: filterScripts })
    $message({ type: 'success', center: true, message: `成功导入脚本: ${ len }条` })
    emit('update-list')
    manualInputVisible.value = false
    visible.value = false
    manualInput.value = ''
  } catch (error) {
    $message.error('导入失败: ' + error.message)
  }
}
</script>

<style lang="scss">
.import_form_dialog {
  h2 {
    font-size: 14px;
    font-weight: 600;
    text-align: center;
    margin: 15px 0 25px 0;
  }
  .type_list {
    display: flex;
    align-items: center;
    justify-content: center;
    user-select: none;
    li {
      margin: 0 25px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      width: 150px;
      height: 150px;
      cursor: pointer;
      border-radius: 3px;
      &:hover {
        color: var(--el-menu-active-color);
      }
      .icon {
        width: 35px;
        height: 35px;
      }
      span {
        display: inline-block;
      }
      .from {
        font-size: 14px;
        margin: 15px 0;
      }
      .type {
        font-size: 12px;
      }
    }
  }
}

.manual-input-footer {
  display: flex;
  justify-content: center;
  gap: 20px;
}
</style>