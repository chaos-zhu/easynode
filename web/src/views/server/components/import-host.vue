<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="225px"
    modal-class="import_form_dialog"
    append-to-body
    title="导入实例配置"
    :close-on-click-modal="false"
  >
    <h2>选择要导入的文件类型</h2>
    <ul class="type_list">
      <li @click="handleFromCsv">
        <svg-icon name="icon-csv" class="icon" />
        <span class="from">Xshell</span>
        <span class="type">(csv)</span>
        <input
          ref="csvInputRef"
          type="file"
          accept=".csv"
          multiple
          name="csvInput"
          style="display: none;"
          @change="handleCsvFile"
        >
      </li>
      <li @click="handleFromJson(false)">
        <svg-icon name="icon-json" class="icon" />
        <span class="from">FinalShell</span>
        <span class="type">(json)</span>
        <input
          ref="jsonInputRef"
          type="file"
          accept=".json"
          multiple
          name="jsonInput"
          style="display: none;"
          @click.stop
          @change="handleJsonFile"
        >
      </li>
      <li @click="handleFromJson(true)">
        <svg-icon name="icon-json" class="icon" />
        <span class="from">EadyNode</span>
        <span class="type">(json)</span>
      </li>
    </ul>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { parse } from 'csv-parse/browser/esm/sync'

const { proxy: { $api, $message } } = getCurrentInstance()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})
const emit = defineEmits(['update:show', 'update-list',])

const jsonInputRef = ref(null)
const csvInputRef = ref(null)

let visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

function handleFromCsv() {
  csvInputRef.value.click()
}

let isEasyNodeJson = ref(false)

function handleFromJson(isENJson) {
  isEasyNodeJson.value = isENJson
  // console.log('isEasyNodeJson:', isEasyNodeJson.value)
  jsonInputRef.value.click()
}

const handleCsvFile = (event) => {
  const files = event.target.files
  if (!files.length) {
    console.warn('No files selected')
    return
  }
  const csvFiles = [...files,].filter(file => file.type === 'text/csv')
  if (csvFiles.length === 0) return $message.warning('未选择有效的CSV文件')

  let readerPromises = csvFiles.map(file => {
    return new Promise((resolve, reject) => {
      let reader = new FileReader()
      reader.onload = (e) => {
        const csvText = e.target.result
        try {
          const jsonContents = parse(csvText, {
            columns: ['name', 'protocol', 'host', 'port', 'username', 'placeholder',],
            from_line: 1 // xshell导出的从第一行开始解析
          })
          handleImportHost(jsonContents)
        } catch (error) {
          console.error(`Error parsing CSV file ${ file.name }:`, error)
        }
      }
      reader.onerror = () => {
        reject(new Error(`Failed to read file: ${ file.name }`))
      }
      reader.readAsText(file)
    })
  })

  Promise.all(readerPromises)
    .then(jsonContents => {
      let formatJson = jsonContents.flat(Infinity)
      formatJson = formatJson.map(item => {
        const { name, host, port, user_name: username } = item
        return { name, host, port, username }
      })
      handleImportHost(formatJson)
    })
    .catch(error => {
      $message.error('导入失败: ', error.message)
      console.error('导入失败: ', error)
    })
    .finally(() => {
      event.target.value = null
    })
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
    .then(jsonContents => {
      let formatJson = jsonContents.flat(Infinity)
      if (!isEasyNodeJson.value) {
        formatJson = formatJson.map(item => {
          const { name, host, port, user_name: username } = item
          return { name, host, port, username }
        })
      }
      handleImportHost(formatJson)
    })
    .catch(error => {
      $message.error('导入失败: ', error.message)
      console.error('导入失败: ', error)
    })
    .finally(() => {
      event.target.value = null
    })
}

async function handleImportHost(importHost) {
  // console.log('导入: ', importHost)
  try {
    let { data: { len } } = await $api.importHost({ importHost, isEasyNodeJson: isEasyNodeJson.value })
    $message({ type: 'success', center: true, message: `成功导入实例: ${ len }台` })
    emit('update-list')
    visible.value = false
  } catch (error) {
    $message.error('导入失败:', error.message)
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
        // background-color: #f1f2f5;
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

.dialog_footer {
  display: flex;
  justify-content: center;
}
</style>
