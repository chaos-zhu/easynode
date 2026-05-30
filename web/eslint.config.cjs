const vue = require('eslint-plugin-vue')
const vueParser = require('vue-eslint-parser')

module.exports = [
  {
    ignores: ['*.html']
  },

  ...vue.configs['flat/recommended'],

  {
    files: ['**/*.{js,vue}'],

    languageOptions: {
      parser: vueParser,
      ecmaVersion: 2022,
      sourceType: 'module',
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
        ecmaFeatures: {
          jsx: true
        }
      },
      globals: {
        window: 'readonly',
        document: 'readonly',
        navigator: 'readonly',
        location: 'readonly',
        console: 'readonly',
        process: 'readonly',
        module: 'readonly',
        require: 'readonly',
      }
    },

    rules: {
      // vue
      'vue/max-attributes-per-line': ['error', {
        singleline: 3,
        multiline: {
          max: 1
        }
      }],
      'vue/no-v-model-argument': 'off',
      'vue/multi-word-component-names': 'off',
      'vue/no-multiple-template-root': 'off',
      'vue/singleline-html-element-content-newline': 'off',

      // js
      'no-case-declarations': 'off',
      'space-before-blocks': ['error', 'always'],
      'space-in-parens': ['error', 'never'],
      'keyword-spacing': ['error', { before: true, after: true }],
      'no-async-promise-executor': 'off',

      // 没装 eslint-plugin-import / eslint-plugin-eslint-comments 时，不要写这些规则
      // 'import/no-extraneous-dependencies': 'off',
      // 'eslint-comments/no-unlimited-disable': 'off',
      // 'import/no-unresolved': 'off',
      // 'import/prefer-default-export': 'off',
      // 'import/extensions': 'off',

      'no-console': 'off',
      'no-debugger': process.env.NODE_ENV === 'production' ? 'error' : 'off',
      'template-curly-spacing': ['error', 'always'],
      'default-case': 'off',
      'object-curly-spacing': ['error', 'always'],
      'no-multi-spaces': 'error',
      indent: ['error', 2, { SwitchCase: 1 }],
      quotes: ['error', 'single'],
      semi: ['error', 'never'],
      'comma-dangle': ['error', {
        arrays: 'always',
        objects: 'never',
        imports: 'never',
        exports: 'never',
        functions: 'never'
      }],
      'no-redeclare': ['error', { builtinGlobals: true }],
      'no-multi-assign': 'off',
      'no-restricted-globals': 'off',
      'space-before-function-paren': 'off',
      'one-var': 'off',
      'linebreak-style': 'off',
      'no-extra-boolean-cast': 'off',
      'no-constant-condition': 'off',
      'no-prototype-builtins': 'off',
      'no-regex-spaces': 'off',
      'no-unexpected-multiline': 'off',
      'no-fallthrough': 'off',
      'no-delete-var': 'off',
      'no-mixed-spaces-and-tabs': 'off',
      'no-class-assign': 'off',
      'no-param-reassign': 'off',
      'max-len': 'off',
      'func-names': 'off',
      'no-const-assign': 'warn',
      'no-unused-vars': 'warn',
      'no-unsafe-negation': 'warn',
      'use-isnan': 'warn',
      'no-var': 'error',
      'no-empty-pattern': 'error',
      eqeqeq: 'error',
      'no-cond-assign': 'error',
      'no-dupe-args': 'error',
      'no-dupe-keys': 'error',
      'no-duplicate-case': 'error',
      'no-empty': 'error',
      'no-func-assign': 'error',
      'no-inner-declarations': 'error',
      'no-sparse-arrays': 'error',
      'no-unreachable': 'error',
      'no-unsafe-finally': 'error',
      'valid-typeof': 'error',
      'prefer-const': 'off',
      'no-extra-parens': 'off',
      'no-extra-semi': 'error',
      'dot-notation': 'off',
      'dot-location': ['error', 'property'],
      'no-else-return': 'error',
      'no-implicit-coercion': ['error', { allow: ['!!', '~', '+'] }],
      'no-trailing-spaces': 'warn',
      'no-multiple-empty-lines': ['warn', { max: 1 }],
      'no-useless-return': 'error',
      'wrap-iife': 'off',
      yoda: 'off',
      strict: 'off',
      'no-undef-init': 'off',
      'prefer-promise-reject-errors': 'off',
      'consistent-return': 'off',
      'no-new': 'off',
      'no-restricted-syntax': 'off',
      'no-plusplus': 'off',
      'global-require': 'off',
      'no-return-assign': 'off'
    }
  }
]