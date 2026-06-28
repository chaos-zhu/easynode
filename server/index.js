global.rpdToken = require('crypto').randomBytes(32).toString('hex')
require('dotenv').config()
require('./app/main.js')
