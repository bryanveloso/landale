import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        main: {
          dark: '#241f33',
          light: '#efefef',
          avagreen: '#5be058',
          avapurple: '#6644e8',
          avablue: '#1cdaf4',
          avayellow: '#ffdd33',
        },
        muted: {
          green: '#bbf4b0',
          purple: '#928add',
          bluegrey: '#6d8591',
          yellow: '#fff683',
          lightgreen: '#e7f7e7',
          lightbluegrey: '#b4cbd6',
          dark: '#0d0a11',
          midgrey: '#939393',
        },
        gradient: {
          lighter: '#23292f',
          darker: '#1a1f23',
        },
      },
    },
  },
  plugins: [],
}
export default config
