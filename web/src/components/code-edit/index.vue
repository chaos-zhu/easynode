<template>
  <el-dialog
    v-model="visible"
    width="80%"
    :top="'20px'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    center
    custom-class="container"
    @closed="handleClosed"
  >
    <template #title>
      <div class="title">
        FileName - <span>{{ status }}</span>
      </div>
    </template>
    <codemirror
      v-model="code"
      placeholder="Code goes here..."
      :style="{ height: '79vh', minHeight: '500px' }"
      :autofocus="true"
      :indent-with-tab="true"
      :tab-size="4"
      :extensions="extensions"
      @ready="status = '准备中'"
      @change="handleChange"
      @focus="status = '编辑中'"
      @blur="status = '未聚焦'"
    />
    <template #footer>
      <footer>
        <div>
          <el-select v-model="curLang" placeholder="Select language" size="small">
            <el-option
              v-for="item in languageKey"
              :key="item"
              :label="item"
              :value="item"
            />
          </el-select>
        </div>
        <div>
          <el-button type="primary" :loading="loading" @click="handleSave">保存</el-button>
          <el-button type="info" @click="handleClose">关闭</el-button>
        </div>
      </footer>
    </template>
  </el-dialog>
</template>

<script>
import { Codemirror } from 'vue-codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import languages from './languages'
import { sortString, getSuffix } from '@/utils'

const languageKey = sortString(Object.keys(languages))
// console.log('languages: ', languages)

export default {
  name: 'CodeEdit',
  components: {
    Codemirror
  },
  props: {
    show: {
      required: true,
      type: Boolean
    },
    originalCode: {
      required: true,
      type: String
    },
    filename: {
      required: true,
      type: String
    }
  },
  emits: ['update:show', 'save', 'closed',],
  data() {
    return {
      languageKey,
      curLang: null,
      status: '准备中',
      loading: false,
      isTips: false,
      code: 'hello world'
    }
  },
  computed: {
    extensions() {
      let res = []
      if(this.curLang) res.push(languages[this.curLang]())
      res.push(oneDark)
      return res
    },
    visible: {
      get() {
        return this.show
      },
      set(newVal) {
        this.$emit('update:show', newVal)
      }
    }
  },
  watch: {
    originalCode(newVal) {
      this.code = newVal
    },
    filename(newVal) {
      try {
        let name = String(newVal).toLowerCase()
        let suffix = getSuffix(name)
        switch(suffix) {
          case 'js': return this.curLang = 'javascript'
          case 'ts': return this.curLang = 'typescript'
          case 'jsx': return this.curLang = 'jsx'
          case 'tsx': return this.curLang = 'tsx'
          case 'html': return this.curLang = 'html'
          case 'css': return this.curLang = 'css'
          case 'json': return this.curLang = 'json'
          case 'swift': return this.curLang = 'swift'
          case 'yaml': return this.curLang = 'yaml'
          case 'yml': return this.curLang = 'yaml'
          case 'vb': return this.curLang = 'vb'
          case 'dockerfile': return this.curLang = 'dockerFile'
          case 'sh': return this.curLang = 'shell'
          case 'r': return this.curLang = 'r'
          case 'ruby': return this.curLang = 'ruby'
          case 'go': return this.curLang = 'go'
          case 'julia': return this.curLang = 'julia'
          case 'conf': return this.curLang = 'shell'
          case 'cpp': return this.curLang = 'cpp'
          case 'java': return this.curLang = 'java'
          case 'xml': return this.curLang = 'xml'
          case 'php': return this.curLang = 'php'
          case 'sql': return this.curLang = 'sql'
          case 'md': return this.curLang = 'markdown'
          case 'py': return this.curLang = 'python'
          default:
            console.log('不支持的文件类型: ', newVal)
            console.log('默认: ', 'shell')
            return this.curLang = 'shell'
        }
      } catch (error) {
        console.log('未知文件类型', newVal, error)
      }
    }
  },
  created() {
  },
  methods: {
    handleSave() {
      if(this.isTips) {
        this.$messageBox.confirm( '文件已变更, 确认保存?', 'Warning', {
          confirmButtonText: '确定',
          cancelButtonText: '取消',
          type: 'warning'
        })
          .then(async () => {
            this.visible = false
            this.$emit('save', this.code)
          })
      } else {
        this.visible = false
      }
    },
    handleClosed() {
      this.isTips = false
      this.$emit('closed')
    },
    handleClose() {
      if(this.isTips) {
        this.$messageBox.confirm( '文件已变更, 确认丢弃?', 'Warning', {
          confirmButtonText: '确定',
          cancelButtonText: '取消',
          type: 'warning'
        })
          .then(async () => {
            this.visible = false
          })
      } else {
        this.visible = false
      }
    },
    handleChange() {
      this.isTips = true
    }
  }
}
</script>

<style lang="scss" scoped>
</style>

<style lang="scss">
.container {
  .el-dialog__header {
    padding: 5px 0;
    .title {
      color: #409eff;
      text-align: left;
      padding-left: 10px;
      font-size: 13px;
    }
  }
  .el-dialog__body {
    padding: 0;
    .cm-scroller {
      // 滚动条整体部分
      &::-webkit-scrollbar {
        height: 8px;
        width: 8px;
        background-color: #282c34;
      }
        // 底层轨道
      &::-webkit-scrollbar-track {
        background-color: #282c34;
        border-radius: 5px;
      }
    }
  }
  .el-dialog__footer {
    padding: 10px 0;
  }
  footer {
    display: flex;
    align-items: center;
    padding: 0 15px;
    justify-content: space-between;
  }
}
</style>