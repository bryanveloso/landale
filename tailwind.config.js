const { fontFamily } = require('tailwindcss/defaultTheme')

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './components/**/*.{js,ts,jsx,tsx}',
    './pages/**/*.{js,ts,jsx,tsx}'
  ],
  theme: {
    extend: {
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
