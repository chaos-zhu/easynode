// 规则参见：https://cn.eslint.org/docs/rules/
module.exports = {
  root: true, // 当前配置文件不能往父级查找
  'globals': { 'consola': true },
  env: {
    node: true,
    es6: true
  },
  extends: [
    'eslint:recommended' // 应用Eslint全部默认规则
  ],
  'parserOptions': {
    'ecmaVersion': 'latest',
    'sourceType': 'module' // 目标类型 Node项目得添加这个
  },
  // 自定义规则，可以覆盖 extends 的配置【安装Eslint插件可以静态检查本地文件是否符合以下规则】
  'ignorePatterns': ['*.html', 'node-os-utils'],
  rules: {
    // 0: 关闭规则(允许)  1/2: 警告warning/错误error(不允许)
    'no-console': 'off',
    'no-debugger': process.env.NODE_ENV === 'production' ? 'error' : 'off',
    'template-curly-spacing': ['error', 'always'], // 模板字符串空格
    'default-case': 0,
    'no-empty': 0,
    'object-curly-spacing': ['error', 'always'],
    'no-multi-spaces': ['error'],
    indent: ['error', 2, { 'SwitchCase': 1 }], // 缩进：2
    quotes: ['error', 'single'], // 引号：single单引 double双引
    semi: ['error', 'never'], // 结尾分号：never禁止 always必须
    'comma-dangle': ['error', 'never'], // 对象拖尾逗号
    'space-before-blocks': ['error', 'always'],
    'space-in-parens': ['error', 'never'],
    'keyword-spacing': ['error', { 'before': true, 'after': true }],
    'no-redeclare': ['error', { builtinGlobals: true }], // 禁止重复对象声明
    'no-multi-assign': 0,
    'no-restricted-globals': 0,
    'no-case-declarations': 0,
    'space-before-function-paren': 0, // 函数定义时括号前面空格
    'no-async-promise-executor': 0, // 允许在回调中使用async函数
    'one-var': 0, // 允许连续声明
    // 'no-undef': 0, // 允许未定义的变量【会使env配置无效】
    'linebreak-style': 0, // 检测CRLF/LF检测【默认LF】
    'no-extra-boolean-cast': 0, // 允许意外的Boolean值转换
    'no-constant-condition': 0, // if语句中禁止常量表达式
    'no-prototype-builtins': 0, // 允许使用Object.prototypes内置对象(如：xxx.hasOwnProperty)
    'no-regex-spaces': 0, // 允许正则匹配多个空格
    'no-unexpected-multiline': 0, // 允许多行表达式
    'no-fallthrough': 0, // 允许switch穿透
    'no-delete-var': 0, // 允许 delete 删除对象属性
    'no-mixed-spaces-and-tabs': 0, // 允许空格tab混用
    'no-class-assign': 0, // 允许修改class类型
    'no-param-reassign': 0, // 允许对函数params赋值
    'max-len': 0, // 允许长行
    'func-names': 0, // 允许命名函数
    'import/no-unresolved': 0, // 不检测模块not fund
    'import/prefer-default-export': 0, // 允许单个导出
    'no-const-assign': 1, // 警告：修改const命名的变量
    'no-unused-vars': 1, // 警告：已声明未使用
    'no-unsafe-negation': 1, // 警告：使用 in / instanceof 关系运算符时，左边表达式请勿使用 ! 否定操作符
    'use-isnan': 1, // 警告：使用 isNaN() 检查 NaN
    'no-var': 2, // 禁止使用var声明
    'no-empty-pattern': 2, // 空解构赋值
    'eqeqeq': 2, // 必须使用 全等=== 或 非全等 !==
    'no-cond-assign': 2, // if语句中禁止赋值
    'no-dupe-args': 2, // 禁止function重复参数
    'no-dupe-keys': 2, // 禁止object重复key
    'no-duplicate-case': 2,
    'no-func-assign': 2, // 禁止重复声明函数
    'no-inner-declarations': 2, // 禁止在嵌套的语句块中出现变量或 function 声明
    'no-sparse-arrays': 2, // 禁止稀缺数组
    'no-unreachable': 2, // 禁止非条件return、throw、continue 和 break 语句后出现代码
    'no-unsafe-finally': 2, // 禁止finally出现控制流语句，如：return、throw等，因为这会导致try...catch捕获不到
    'valid-typeof': 2, // 强制 typeof 表达式与有效的字符串进行比较
    // auto format options
    'prefer-const': 0, // 禁用声明自动化
    'no-extra-parens': 0, // 允许函数周围出现不明括号
    'no-extra-semi': 2, // 禁止不必要的分号
    // curly: ['error', 'multi'], // if、else、for、while 语句单行代码时不使用大括号
    'dot-notation': 0, // 允许使用点号或方括号来访问对象属性
    'dot-location': ['error', 'property'], // 点操作符位置，要求跟随下一行
    'no-else-return': 2, // 禁止if中有return后又else
    'no-implicit-coercion': [2, { allow: ['!!', '~', '+'] }], // 禁止隐式转换，allow字段内符号允许
    'no-trailing-spaces': 1, //一行结束后面不要有空格
    'no-multiple-empty-lines': [1, { 'max': 1 }], // 空行最多不能超过1行
    'no-useless-return': 2,
    'wrap-iife': 0, // 允许自调用函数
    'yoda': 0, // 允许yoda语句
    'strict': 0, // 允许strict
    'no-undef-init': 0, // 允许将变量初始化为undefined
    'prefer-promise-reject-errors': 0, // 允许使用非 Error 对象作为 Promise 拒绝的原因
    'consistent-return': 0, // 允许函数不使用return
    'no-new': 0, // 允许单独new
    'no-restricted-syntax': 0, // 允许特定的语法
    'no-plusplus': 0,
    'import/extensions': 0, // 忽略扩展名
    'global-require': 0,
    'no-return-assign': 0
  }
}
