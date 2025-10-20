<!--
  终端搜索组件
  - 向上向下查找
  - 区分大小写
  - 正则表达式
  - 查找范围为终端缓冲区（scrollback设置的行数）
-->
<template>
  <div v-if="visible" class="terminal_search_bar" :style="searchBarStyle">
    <div class="search_container">
      <el-input
        ref="searchInputRef"
        v-model="searchKeyword"
        placeholder="查找内容..."
        size="small"
        class="search_input"
        clearable
        @keyup.enter="handleEnterKey"
      >
        <template #suffix>
          <div class="search_result_info">
            <span v-if="searchKeyword" class="result_status">
              <template v-if="searchStatus === 'found'">
                <span class="count_text">{{ currentMatchIndex }}/{{ totalMatches }}</span>
              </template>
              <template v-else-if="searchStatus === 'not-found'">
                <el-icon style="color: var(--el-color-warning)">
                  <CircleClose />
                </el-icon>
                <span class="status_text">未找到</span>
              </template>
            </span>
          </div>
        </template>
      </el-input>

      <el-tooltip placement="bottom">
        <template #content>
          <div style="max-width: 300px;">
            搜索范围：终端缓冲区内的内容（最多1万行）<br>
            超出缓冲区的内容无法搜索
          </div>
        </template>
        <el-icon class="search_info_icon" :size="16">
          <InfoFilled />
        </el-icon>
      </el-tooltip>

      <div class="search_actions">
        <el-tooltip content="向上查找 (Shift+Enter)" placement="top">
          <el-button
            :icon="ArrowUp"
            size="small"
            :disabled="!searchKeyword"
            @click="findPrevious"
          />
        </el-tooltip>

        <el-tooltip content="向下查找 (Enter)" placement="top">
          <el-button
            :icon="ArrowDown"
            size="small"
            :disabled="!searchKeyword"
            @click="findNext"
          />
        </el-tooltip>

        <el-tooltip :content="isCaseSensitive ? '区分大小写' : '不区分大小写'" placement="top">
          <el-button
            size="small"
            :type="isCaseSensitive ? 'primary' : ''"
            @click="toggleCaseSensitive"
          >
            Aa  <!-- true=蓝色 false=灰色 -->
          </el-button>
        </el-tooltip>

        <el-tooltip :content="isUseRegex ? '正则表达式' : '普通文本'" placement="top">
          <el-button
            size="small"
            :type="isUseRegex ? 'primary' : ''"
            @click="toggleRegex"
          >
            .*  <!-- true=蓝色 false=灰色 -->
          </el-button>
        </el-tooltip>

        <el-tooltip content="关闭" placement="top">
          <el-button
            :icon="Close"
            size="small"
            @click="close"
          />
        </el-tooltip>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, nextTick, computed } from 'vue'
import { ArrowUp, ArrowDown, Close, InfoFilled, CircleClose } from '@element-plus/icons-vue'

const props = defineProps({
  searchAddon: {
    type: Object,
    required: true
  },
  terminal: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['close',])

const visible = ref(false)
const searchKeyword = ref('')
const isCaseSensitive = ref(false)
const isUseRegex = ref(false)
const searchStatus = ref('') // 'found','not-found',''
const totalMatches = ref(0) // 总匹配数
const currentMatchIndex = ref(0) // 当前匹配索引
const matchPositions = ref([]) // 缓存所有匹配位置 [{行, 列, 长度}]
const searchInputRef = ref(null)

const searchBarStyle = computed(() => ({
  position: 'absolute',
  top: '10px',
  right: '10px',
  zIndex: 1000
}))

const show = () => {
  visible.value = true
  nextTick(() => {
    searchInputRef.value?.focus()
  })
}

const close = () => {
  visible.value = false
  searchKeyword.value = ''
  searchStatus.value = ''
  totalMatches.value = 0
  currentMatchIndex.value = 0
  matchPositions.value = []
  props.searchAddon?.clearDecorations()
  emit('close')
}

// 遍历缓冲区进行查找匹配计数，只在关键词改变时执行一次
const countMatches = () => {
  if (!searchKeyword.value) {
    totalMatches.value = 0
    matchPositions.value = []
    return
  }

  try {
    const buffer = props.terminal.buffer.active
    const searchTerm = searchKeyword.value
    let count = 0
    const positions = []

    // 构建搜索方法
    let searchMethod
    const isCaseSensitiveValue = isCaseSensitive.value

    if (isUseRegex.value) {
      // 正则搜索
      try {
        const flags = isCaseSensitiveValue ? 'g' : 'gi'
        const searchRegex = new RegExp(searchTerm, flags)
        searchMethod = (text) => {
          return Array.from(text.matchAll(searchRegex), match => ({
            index: match.index,
            length: match[0].length
          }))
        }
      } catch (e) {
        totalMatches.value = 0
        matchPositions.value = []
        return
      }
    } else {
      // 普通搜索
      const term = isCaseSensitiveValue ? searchTerm : searchTerm.toLowerCase()
      searchMethod = (text) => {
        const content = isCaseSensitiveValue ? text : text.toLowerCase()
        const matches = []
        let index = content.indexOf(term)

        while (index !== -1) {
          matches.push({ index, length: term.length })
          index = content.indexOf(term, index + 1)
        }
        return matches
      }
    }

    // 逐行遍历所有缓冲区行
    const totalRows = buffer.baseY + buffer.cursorY + 1

    for (let i = 0; i < totalRows && i < buffer.length; i++) {
      const line = buffer.getLine(i)
      if (!line) continue

      const lineText = line.translateToString(true)
      const matches = searchMethod(lineText)

      for (const match of matches) {
        count++
        positions.push({
          line: i,
          col: match.index,
          length: match.length
        })
      }
    }

    totalMatches.value = count
    matchPositions.value = positions
  } catch (error) {
    console.warn('计数匹配项报错:', error)
    totalMatches.value = 0
    matchPositions.value = []
  }
}

const performSearch = (isNext = true) => {
  if (!searchKeyword.value) {
    searchStatus.value = ''
    currentMatchIndex.value = 0
    return
  }

  const result = isNext
    ? props.searchAddon?.findNext(searchKeyword.value, {
      caseSensitive: isCaseSensitive.value,
      regex: isUseRegex.value,
      wholeWord: false
    })
    : props.searchAddon?.findPrevious(searchKeyword.value, {
      caseSensitive: isCaseSensitive.value,
      regex: isUseRegex.value,
      wholeWord: false
    })

  // 更新状态和索引值
  searchStatus.value = result ? 'found' : 'not-found'

  if (result && totalMatches.value > 0) {
    // 根据方向更新索引值
    if (isNext) {
      currentMatchIndex.value = currentMatchIndex.value >= totalMatches.value ? 1 : currentMatchIndex.value + 1
    } else {
      currentMatchIndex.value = currentMatchIndex.value <= 1 ? totalMatches.value : currentMatchIndex.value - 1
    }
  }
}

const findNext = () => {
  performSearch(true)
}

const findPrevious = () => {
  performSearch(false)
}

// 处理Enter和Shift+Enter
const handleEnterKey = (event) => {
  if (event.shiftKey) {
    // Shift+Enter是向上查找
    findPrevious()
  } else {
    // 只有Enter是向下查找
    findNext()
  }
}

const toggleCaseSensitive = () => {
  isCaseSensitive.value = !isCaseSensitive.value
  resetSearch()
}

const toggleRegex = () => {
  isUseRegex.value = !isUseRegex.value
  resetSearch()
}

const resetSearch = () => {
  searchStatus.value = ''
  currentMatchIndex.value = 0
  if (searchKeyword.value) {
    // 重新计数
    countMatches()
    // 从第一个开始
    currentMatchIndex.value = 1
    performSearch(true)
  }
}

watch(searchKeyword, (newVal) => {
  if (!newVal) {
    props.searchAddon?.clearDecorations()
    searchStatus.value = ''
    totalMatches.value = 0
    currentMatchIndex.value = 0
    matchPositions.value = []
  } else {
    searchStatus.value = ''
    currentMatchIndex.value = 0
    countMatches()
    if (totalMatches.value > 0) {
      currentMatchIndex.value = 1
      performSearch(true)
    } else {
      searchStatus.value = 'not-found'
    }
  }
})

defineExpose({
  show,
  close
})
</script>

<style lang="scss" scoped>
.terminal_search_bar {
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color);
  border-radius: 6px;
  padding: 8px;
  box-shadow: var(--el-box-shadow-light);
  user-select: none;

  .search_container {
    display: flex;
    gap: 8px;
    align-items: center;

    .search_info_icon {
      color: var(--el-color-info);
      cursor: help;
      flex-shrink: 0;
    }

    .search_input {
      width: 200px;

      .search_result_info {
        display: flex;
        align-items: center;
        gap: 4px;

        .result_status {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
          margin-right: 4px;

          .status_text {
            font-size: 12px;
          }

          .count_text {
            font-size: 12px;
            font-weight: 500;
            color: var(--el-color-primary);
          }
        }
      }
    }

    .search_actions {
      display: flex;
      gap: 4px;

      :deep(.el-button) {
        min-width: 32px;
        padding: 0;
      }
    }
  }
}
</style>
