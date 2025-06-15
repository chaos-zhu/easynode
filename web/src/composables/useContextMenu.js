import { ref } from 'vue'
import ContextMenu from '@/components/ContextMenu.vue'
import { createApp } from 'vue'
import ElementPlus from 'element-plus'

export function useContextMenu() {
  const menuRef = ref(null)
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
    document.body.appendChild(container)

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
  }

  const closeMenu = () => {
    if (contextMenuInstance && !isClosing) {
      isClosing = true
      contextMenuInstance.closeMenu()

      setTimeout(() => {
        if (contextMenuInstance && contextMenuInstance._container) {
          try {
            contextMenuApp?.unmount()
            if (document.body.contains(contextMenuInstance._container)) {
              document.body.removeChild(contextMenuInstance._container)
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
      contextMenuInstance.closeMenu()

      try {
        contextMenuApp?.unmount()
        if (document.body.contains(contextMenuInstance._container)) {
          document.body.removeChild(contextMenuInstance._container)
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
    showMenu,
    closeMenu
  }
}
