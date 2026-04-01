<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="225px"
    modal-class="import_script_dialog"
    append-to-body
    :title="t('scripts.importConfigTitle')"
    :close-on-click-modal="false"
  >
    <h2>{{ t('scripts.chooseImportGroup') }}</h2>
    <el-select v-model="targetGroup" :placeholder="t('scripts.selectGroup')" style="width: 50%;margin-bottom: 10px;">
      <el-option
        v-for="item in groupList"
        :key="item.id"
        :label="item.name"
        :value="item.id"
      />
    </el-select>

    <h2>{{ t('scripts.chooseImportType') }}</h2>
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
      <li @click="() => manualInputVisible = true">
        <svg-icon name="icon-bianji1" class="icon" />
        <span class="from">{{ t('scripts.manualInput') }}</span>
      </li>
    </ul>
  </el-dialog>

  <el-dialog
    v-model="manualInputVisible"
    width="600px"
    top="150px"
    :title="t('scripts.manualInputTitle')"
    :close-on-click-modal="false"
    append-to-body
  >
    <el-input
      v-model="manualInput"
      type="textarea"
      :autosize="{ minRows: 15 }"
      :placeholder="t('scripts.manualInputPlaceholder')"
    />
    <template #footer>
      <div class="manual-input-footer">
        <el-button @click="manualInputVisible = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" @click="handleManualImport">{{ t('scripts.import') }}</el-button>
      </div>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'

const { proxy: { $api, $message, $store } } = getCurrentInstance()
const { t } = useI18n()

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
const targetGroup = ref('default')

let visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

let scriptList = computed(() => $store.scriptList)
const groupList = computed(() => $store.scriptGroupList.filter(item => item.id !== 'builtin'))

function handleFromJson() {
  jsonInputRef.value.click()
}

const handleJsonFile = (event) => {
  let files = event.target.files
  let jsonFiles = Array.from(files).filter(file => file.name.endsWith('.json'))
  if (jsonFiles.length === 0) return $message.warning(t('scripts.invalidJsonFile'))

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
      if (formatJson.length === 0) return $message.warning(t('scripts.importedScriptsExist'))
      formatJson = formatJson.map((item) => {
        return {
          ...item,
          group: targetGroup.value
        }
      })
      try {
        let { data: { len } } = await $api.importScript({ scripts: formatJson })
        $message({ type: 'success', center: true, message: t('scripts.importSuccess', { count: len }) })
        emit('update-list')
        visible.value = false
      } catch (error) {
        $message.error(t('scripts.importFailed', { message: error.message }))
      }
    })
    .catch(error => {
      $message.error(t('scripts.importFailed', { message: error.message }))
      console.error('导入失败: ', error)
    })
    .finally(() => {
      event.target.value = null
    })
}

const handleManualImport = async () => {
  if (!manualInput.value.trim()) {
    return $message.warning(t('scripts.inputScriptContent'))
  }

  try {
    let scripts = manualInput.value.split('\n')
    scripts = [...new Set(scripts),]
      .filter(line => line.trim())
      .map((command) => ({ command: command.trim() }))
    if (scripts.length === 0) {
      return $message.warning(t('scripts.noValidScriptContent'))
    }

    let existCommand = scriptList.value.map(item => item.command)
    let filterScripts = scripts.filter(({ command }) => {
      return !existCommand.includes(command)
    })
    let filterScriptsLen = filterScripts.length
    if (filterScriptsLen !== 0 && filterScriptsLen < scripts.length) $message.warning(t('scripts.duplicateScriptsFiltered'))
    if (filterScriptsLen === 0) return $message.warning(t('scripts.importedScriptsExist'))
    filterScripts = filterScripts.map((item, index) => {
      return {
        ...item,
        name: `${ item.command.slice(0, 15) || t('scripts.scriptDefaultName', { index: index + 1 }) }`,
        index: scriptList.value.length + index + 1,
        description: t('scripts.manualInputDescription'),
        group: targetGroup.value
      }
    })

    let { data: { len } } = await $api.importScript({ scripts: filterScripts })
    $message({ type: 'success', center: true, message: t('scripts.importSuccess', { count: len }) })
    emit('update-list')
    manualInputVisible.value = false
    visible.value = false
    manualInput.value = ''
  } catch (error) {
    $message.error(t('scripts.importFailed', { message: error.message }))
  }
}
</script>

<style lang="scss">
.import_script_dialog {
  h2 {
    font-size: 14px;
    font-weight: 600;
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
      height: 120px;
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