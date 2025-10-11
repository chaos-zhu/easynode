import { ref } from 'vue'
import ContextMenu from '@/components/ContextMenu.vue'
import { createApp } from 'vue'
import ElementPlus from 'element-plus'

export function useContextMenu() {
  const menuRef = ref(null)
  const isVisible = ref(false)
  let contextMenuApp = null
  let contextMenuInstance = null
  let isClosing = false

  const showMenu = async (event, items) => {
    event.preventDefault()

    // 如果正在关闭中，等待关闭完成
    if (isClosing) {
      await new Promise(resolve => {
        const checkClosed = () => {
          if (!isClosing) {
            resolve()
          } else {
            setTimeout(checkClosed, 10)
          }
        }
        checkClosed()
      })
    }

    // 如果已有菜单实例，先同步关闭
    if (contextMenuInstance) {
      await closeMenuSync()
    }

    contextMenuApp = createApp(ContextMenu)
    contextMenuApp.use(ElementPlus)

    const container = document.createElement('div')

    // 检测全屏状态，决定挂载位置
    const fullscreenElement = document.fullscreenElement
    if (fullscreenElement) {
      // 在全屏模式下，挂载到全屏元素中
      fullscreenElement.appendChild(container)
    } else {
      // 非全屏模式，挂载到body
      document.body.appendChild(container)
    }

    contextMenuInstance = contextMenuApp.mount(container)
    menuRef.value = contextMenuInstance

    contextMenuInstance.showMenu(event, items || [
      {
        label: 'A menu item',
        onClick: () => {
          alert('You click a menu item')
        }
      },
      {
        label: 'A submenu',
        children: [
          {
            label: 'Sub item 1',
            onClick: () => {
              console.log('Sub item 1 clicked')
            }
          },
        ]
      },
    ])

    contextMenuInstance._container = container
    isVisible.value = true
  }

  const closeMenu = () => {
    if (contextMenuInstance && !isClosing) {
      isClosing = true
      isVisible.value = false
      contextMenuInstance.closeMenu()

      setTimeout(() => {
        if (contextMenuInstance && contextMenuInstance._container) {
          try {
            contextMenuApp?.unmount()
            // 检查容器的父元素，从正确的父元素中移除
            const container = contextMenuInstance._container
            if (container && container.parentNode) {
              container.parentNode.removeChild(container)
            }
          } catch (error) {
            console.warn('清理菜单时出错:', error)
          }
          contextMenuInstance = null
          contextMenuApp = null
          menuRef.value = null
        }
        isClosing = false
      }, 100)
    }
  }

  const closeMenuSync = () => {
    return new Promise((resolve) => {
      if (!contextMenuInstance) {
        resolve()
        return
      }

      isClosing = true
      isVisible.value = false
      contextMenuInstance.closeMenu()

      try {
        contextMenuApp?.unmount()
        // 检查容器的父元素，从正确的父元素中移除
        const container = contextMenuInstance._container
        if (container && container.parentNode) {
          container.parentNode.removeChild(container)
        }
      } catch (error) {
        console.warn('同步清理菜单时出错:', error)
      }

      contextMenuInstance = null
      contextMenuApp = null
      menuRef.value = null
      isClosing = false
      resolve()
    })
  }

  return {
    menuRef,
    isVisible,
    showMenu,
    closeMenu
  }
}
