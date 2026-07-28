import fs from 'fs-extra'
import { createRequire } from 'node:module'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import CryptoJS from 'crypto-js'
import { init, parse } from 'es-module-lexer'
import { AESDecryptAsync, SHA256Encrypt } from './encrypt.js'
import { RuntimeState } from './runtime-state.js'
const runtimeState = new RuntimeState().getInstance()
const plusModuleCache = new Map()
const dataModuleUrlPattern = /data:text\/javascript;base64,[A-Za-z0-9+/]+={0,2}(?:#[A-Za-z0-9._-]+)?/g
const moduleLexerReady = init

function isPlusAvailable() {
  return Boolean(runtimeState.getDecryptKey()) && !runtimeState.getPlusKicked()
}

function sanitizeLoaderError(error) {
  const message = error?.message || String(error)
  return message.replace(dataModuleUrlPattern, '[Plus ESM module]')
}

async function resolveImportSpecifiers(source, plusPath) {
  await moduleLexerReady
  const moduleUrl = pathToFileURL(path.resolve(plusPath))
  const resolver = createRequire(moduleUrl)
  const resolveSpecifier = (specifier) => {
    if (specifier.startsWith('node:')) return specifier
    if (specifier.startsWith('.') || specifier.startsWith('/')) {
      return new URL(specifier, moduleUrl).href
    }
    const resolvedPath = resolver.resolve(specifier)
    return resolvedPath.startsWith('node:') ? resolvedPath : pathToFileURL(resolvedPath).href
  }

  const [imports] = parse(source)
  let resolvedSource = source
  // 从后向前替换，保证 lexer 返回的源码下标不会因前面的替换而偏移。
  for (let index = imports.length - 1; index >= 0; index -= 1) {
    const importRecord = imports[index]
    // 非字面量动态导入（如 import(moduleName)）在运行时才能确定，保持原样。
    if (typeof importRecord.n !== 'string') continue
    const resolvedSpecifier = resolveSpecifier(importRecord.n)
    const quote = importRecord.d >= 0 ? source[importRecord.s] : ''
    const replacement = quote === '\'' || quote === '"' || quote === '`'
      ? `${ quote }${ resolvedSpecifier }${ quote }`
      : resolvedSpecifier
    resolvedSource = `${ resolvedSource.slice(0, importRecord.s) }${ replacement }${ resolvedSource.slice(importRecord.e) }`
  }
  return resolvedSource
}

async function resolveDecryptKey(decryptKeyCipher) {
  const decryptKey = await AESDecryptAsync(decryptKeyCipher)
  if (!decryptKey) {
    throw new Error('解密密钥解析失败')
  }
  return {
    decryptKey,
    fingerprint: SHA256Encrypt(decryptKey)
  }
}

async function decryptAndImportOnce(plusPath, decryptKey) {
  const encryptedContent = await fs.readFile(plusPath, 'utf-8')
  const bytes = CryptoJS.AES.decrypt(encryptedContent, decryptKey)
  const decryptedContent = bytes.toString(CryptoJS.enc.Utf8)
  if (!decryptedContent) {
    throw new Error('解密失败,请检查密钥是否正确')
  }
  const esmContent = await resolveImportSpecifiers(decryptedContent, plusPath)
  const moduleId = path.basename(path.dirname(plusPath))
  const sourceLabel = `easynode-plus-${ moduleId }.mjs`
  const encodedContent = Buffer.from(`${ esmContent }\n//# sourceURL=${ sourceLabel }\n`).toString('base64')
  return import(`data:text/javascript;base64,${ encodedContent }#plus-${ moduleId }`)
}

function createCacheEntry(absolutePath, decryptKeyCipher) {
  const entry = {
    keyFingerprint: null,
    validatedCipher: decryptKeyCipher,
    modulePromise: null
  }

  entry.modulePromise = resolveDecryptKey(decryptKeyCipher)
    .then(({ decryptKey, fingerprint }) => {
      entry.keyFingerprint = fingerprint
      return decryptAndImportOnce(absolutePath, decryptKey)
    })
    .catch((error) => {
      if (plusModuleCache.get(absolutePath) === entry) {
        plusModuleCache.delete(absolutePath)
      }
      throw error
    })
  plusModuleCache.set(absolutePath, entry)
  return entry
}

async function validateCachedAuthorization(entry, decryptKeyCipher) {
  if (entry.validatedCipher === decryptKeyCipher) return

  const [, currentAuth] = await Promise.all([
    entry.modulePromise,
    resolveDecryptKey(decryptKeyCipher)
  ])
  if (entry.keyFingerprint !== currentAuth.fingerprint) {
    throw new Error('Plus解密密钥已变化')
  }

  // 同一明文密钥重新激活时密文会变化，仅在状态仍有效时记录本次校验结果。
  if (isPlusAvailable() && runtimeState.getDecryptKey() === decryptKeyCipher) {
    entry.validatedCipher = decryptKeyCipher
  }
}

async function decryptAndExecuteAsync(plusPath) {
  try {
    if (!isPlusAvailable()) {
      throw new Error(runtimeState.getPlusKicked() ? 'Plus授权已失效' : '缺少解密密钥')
    }

    const absolutePath = path.resolve(plusPath)
    const decryptKeyCipher = runtimeState.getDecryptKey()
    const entry = plusModuleCache.get(absolutePath)
      || createCacheEntry(absolutePath, decryptKeyCipher)

    await validateCachedAuthorization(entry, decryptKeyCipher)
    const plusModule = await entry.modulePromise

    // 加载过程中授权可能被清除，返回模块前再次校验。
    if (!isPlusAvailable() || runtimeState.getDecryptKey() !== decryptKeyCipher) {
      throw new Error('Plus授权状态已变化')
    }

    return plusModule
  } catch (error) {
    logger.info('解锁plus功能失败: ', sanitizeLoaderError(error))
    return null
  }
}

export default decryptAndExecuteAsync
