import express from 'express'
import http from 'http'

const app = express()
const server = http.createServer(http)

const PORT = process.env.PORT || 8007

console.log('Server started...')

app.use(express.json())
app.use(express.urlencoded({ extended: false }))

server.listen(PORT, () => console.log(`Listening on PORT ${PORT}`))
