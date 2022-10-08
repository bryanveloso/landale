/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  images: {
    domains: ['upload-os-bbs.mihoyo.com']
  }
}

module.exports = nextConfig
