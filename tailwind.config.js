const { fontFamily } = require('tailwindcss/defaultTheme')

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './components/**/*.{js,ts,jsx,tsx}',
    './pages/**/*.{js,ts,jsx,tsx}'
  ],
  theme: {
    extend: {
      boxShadow: {
        'sidebar-inset': 'inset -1px 0 0 rgb(0 0 0 / .8)',
        'titlebar-inset': 'inset 0 -1px 0 rgb(0 0 0 / .8)'
      },
      colors: {
        sidebar: 'rgb(40 40 40 / .8)',
        titlebar: 'rgb(60 60 60 /.8)',
        window: 'rgb(40 40 40 / .8)'
      },
      fontFamily: {
        inter: ['InterVariable', ...fontFamily.sans],
        system: ['system-ui', ...fontFamily.sans]
      }
    }
  },
  plugins: []
}
