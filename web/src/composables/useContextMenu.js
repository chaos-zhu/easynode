import { ref } from 'vue'
import ContextMenu from '@imengyu/vue3-context-menu'

export function useContextMenu() {
  const menuRef = ref(null)
  const showMenu = (event, items) => {
    event.preventDefault()
    menuRef.value = ContextMenu.showContextMenu({
      x: event.x,
      y: event.y,
      items: items || [
        {
          label: 'A menu item',
          onClick: () => {
            alert('You click a menu item')
          }
        },
        {
          label: 'A submenu'
        },
      ]
    })
  }

  const closeMenu = () => {
    menuRef.value?.closeMenu()
  }

  return {
    menuRef,
    showMenu,
    closeMenu
  }
}
