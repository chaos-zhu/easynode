<template>
  <el-dialog
    v-model="visible"
    width="60%"
    :top="'30px'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    center
    custom-class="container"
    @closed="handleClosed"
  >
    <template #header>
      <div class="title">
        {{ filename }}
        <!-- {{ filename }} - <span>{{ status }}</span> -->
      </div>
    </template>
    <codemirror
      ref="cmRef"
      v-model="code"
      placeholder="Code goes here..."
      :style="{ height: '80vh', minHeight: '500px' }"
      :disabled="disabled"
      :autofocus="true"
      :indent-with-tab="true"
      :tab-size="4"
      :extensions="extensions"
      @ready="handleReady"
      @change="handleChange"
      @focus="status = '编辑中'"
      @blur="status = '未聚焦'"
    />
    <template #footer>
      <footer>
        <div v-if="!disabled" class="select_wrap">
          <el-select v-model="curLang" placeholder="Select language">
            <el-option
              v-for="item in languageKey"
              :key="item"
              :label="item"
              :value="item"
            />
          </el-select>
        </div>
        <div class="footer_btns">
          <el-button
            v-if="!disabled"
            type="primary"
            :loading="loading"
            @click="handleSave"
          >
            保存
          </el-button>
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
// console.log('languages: ', languageKey)

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
    },
    disabled: {
      type: Boolean,
      default: false
    },
    scrollToBottom: {
      type: Boolean,
      default: false
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
      code: 'loading...',
      editorView: null
    }
  },
  computed: {
    extensions() {
      let res = []
      if (this.curLang) res.push(languages[this.curLang]())
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
      if (this.scrollToBottom) {
        // 内容更新时，只有用户在底部才自动滚动
        setTimeout(() => {
          this.scrollToEnd(false) // 不强制滚动，会检查用户位置
        }, 500)
      }
    },
    filename(newVal) {
      try {
        let name = String(newVal).toLowerCase()
        let suffix = getSuffix(name)
        switch (suffix) {
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
          case 'log': return this.curLang = 'json'
          default:
            // console.log('不支持的文件类型: ', newVal)
            // console.log('默认: ', 'shell')
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
    handleReady(payload) {
      this.status = '准备中'
      // 保存 view 实例以便后续使用
      if (payload && payload.view) {
        this.editorView = payload.view
      }
      // 编辑器准备就绪后，如果需要滚动到底部则执行（首次打开强制滚动）
      if (this.scrollToBottom) {
        // 延迟执行，确保编辑器和内容完全渲染
        setTimeout(() => {
          this.scrollToEnd(true) // 首次打开强制滚动
        }, 300)
      }
    },
    isScrollAtBottom() {
      // 检测滚动条是否在底部（允许50px的误差）
      try {
        const view = this.editorView || (this.$refs.cmRef && this.$refs.cmRef.view)
        if (view && view.scrollDOM) {
          const scroller = view.scrollDOM
          const threshold = 50 // 距离底部50px以内认为是在底部
          const isAtBottom = scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - threshold
          return isAtBottom
        }
        return false
      } catch (error) {
        return false
      }
    },
    // force: 是否强制滚动（用于首次打开）
    scrollToEnd(force = false) {
      try {
        const view = this.editorView || (this.$refs.cmRef && this.$refs.cmRef.view)
        if (view && view.scrollDOM) {
          const scroller = view.scrollDOM
          // 用户不在底部，不自动滚动
          if (!force && !this.isScrollAtBottom()) {
            return
          }
          // 用户在底部或强制滚动，执行滚动
          requestAnimationFrame(() => {
            scroller.scrollTo({
              top: scroller.scrollHeight,
              behavior: 'smooth'
            })
          })
        }
      } catch (error) {
        console.warn('滚动到底部失败:', error)
      }
    },
    handleSave() {
      if (this.isTips) {
        this.$messageBox.confirm('文件已变更, 确认保存?', 'Warning', {
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
      if (this.isTips && !this.disabled) {
        this.$messageBox.confirm('文件已变更, 确认丢弃?', 'Warning', {
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
        height: 4px;
        width: 4px;
        background-color: #282c34;
      }
        // 底层轨道
      &::-webkit-scrollbar-track {
        background-color: #282c34;
        border-radius: 3px;
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
.select_wrap {
  width: 150px;
  margin-right: 15px;
}
</style>