// AES-256-CBC requires a 32-byte key. Keep the random bytes as a Buffer;
// converting them to hex produces a 64-character value and breaks RDP token encryption.
import crypto from 'node:crypto'
import dotenv from 'dotenv'

global.rpdToken = crypto.randomBytes(32)
dotenv.config()
await import('./app/main.js')
