export const loadMarkdownCSS = (isDark) => {
  const existingLink = document.getElementById('markdown-css')
  if (existingLink) existingLink.remove()
  const link = document.createElement('link')
  link.id = 'markdown-css'
  link.rel = 'stylesheet'
  link.href = isDark
    ? 'https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown-dark.min.css'
    : 'https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css'
  document.head.appendChild(link)
}
