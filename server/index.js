const consola = require('consola')
global.consola = consola
global.rpdToken = Array.from({ length:32 },()=>Math.random().toString(36)[2]).join('')
require('dotenv').config()
require('./app/main.js')
