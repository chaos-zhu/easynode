import { ref } from 'vue'
import ContextMenu from '@/components/ContextMenu.vue'
import { createApp } from 'vue'
import ElementPlus from 'element-plus'

export function useContextMenu() {
  const menuRef = ref(null)
  let contextMenuApp = null
  let contextMenuInstance = null

  const showMenu = (event, items) => {
    event.preventDefault()

    if (contextMenuInstance) {
      closeMenu()
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
    if (contextMenuInstance) {
      contextMenuInstance.closeMenu()

      setTimeout(() => {
        if (contextMenuInstance && contextMenuInstance._container) {
          contextMenuApp?.unmount()
          document.body.removeChild(contextMenuInstance._container)
          contextMenuInstance = null
          contextMenuApp = null
          menuRef.value = null
        }
      }, 100)
    }
  }

  return {
    menuRef,
    showMenu,
    closeMenu
  }
}
