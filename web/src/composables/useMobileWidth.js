import { ref, onMounted, onUnmounted } from 'vue'

export default function useMobileWidth(maxWidth = 968) {
  const isMobileScreen = ref(window.innerWidth < maxWidth)
  function updateScreenWidth() {
    isMobileScreen.value = window.innerWidth < maxWidth
  }
  onMounted(() => {
    window.addEventListener('resize', updateScreenWidth)
  })

  onUnmounted(() => {
    window.removeEventListener('resize', updateScreenWidth)
  })
  return { isMobileScreen }
}
