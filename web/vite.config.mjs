import { fileURLToPath, URL } from 'url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueJsx from '@vitejs/plugin-vue-jsx'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { AntDesignXVueResolver } from 'ant-design-x-vue/resolver'
import viteCompression from 'vite-plugin-compression'
import { codeInspectorPlugin } from 'code-inspector-plugin'

const serviceURI = 'http://localhost:8082/'
const serviceApiPrefix = '/api/v1'
const sftpCachePrefix = '/sftp-cache'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 18090,
    // strictPort: true,
    cors: true,
    proxy: {
      [serviceApiPrefix]: {
        target: serviceURI
        // rewrite: (p) => p.replace(/^\/api/, '')
      },
      [sftpCachePrefix]: {
        target: serviceURI
        // rewrite: (p) => p.replace(/^\/api/, '')
      }
    }
    // 解决内网穿透一直重定向的问题
    // hmr: {
    //   protocol: 'ws',
    //   host: 'localhost'
    // }
  },
  build: {
    // outDir: '../server/app/static',
    emptyOutDir: true
  },
  define: {
    'process.env': {
      serviceURI,
      serviceApiPrefix
    }
  },
  plugins: [
    vue(),
    vueJsx(),
    AutoImport({
      resolvers: [
        ElementPlusResolver(),
        AntDesignXVueResolver(),
      ]
    }),
    Components({
      resolvers: [
        ElementPlusResolver(),
        AntDesignXVueResolver(),
      ]
    }),
    viteCompression({
      algorithm: 'gzip',
      deleteOriginFile: false
    }),
    codeInspectorPlugin({
      bundler: 'vite'
    }),
  ],
  css: {
    preprocessorOptions: {
      scss: {
        additionalData: '@use "@/assets/scss/element/index.scss" as *;'
      }
    },
    postcss: {
      plugins: [
      ]
    }
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL(
        './src',
        import.meta.url
      )),
      '@views': fileURLToPath(new URL(
        './src/views',
        import.meta.url
      )),
      '@utils': fileURLToPath(new URL(
        './src/utils',
        import.meta.url
      )),
      '@store': fileURLToPath(new URL(
        './src/store',
        import.meta.url
      ))
    }
  }
})
