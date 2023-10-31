require("./ngrok.config.js")

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  images: {
    domains: ['rainwave.cc'],
    unoptimized: true,
  },
}

module.exports = nextConfig
