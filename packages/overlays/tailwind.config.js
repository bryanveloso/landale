/** @type {import('tailwindcss').Config} */

export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    colors: {
      black: '#000000',
      white: '#ffffff',

      //
      avagreen: '#5be058',
      avablue: '#1cdaf4',
      avapurple: '#6644e8',
      avayellow: '#ffdd33',
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

      //
      shark: {
        50: '#d3dfdf',
        100: '#c0cfd3',
        200: '#a8bac2',
        300: '#819ba7',
        400: '#5a737c',
        500: '#44585f',
        600: '#35434b',
        700: '#2b353b',
        800: '#232a2e' /* gradent.lighter */,
        900: '#1a1f23' /* gradient.darker */,
        950: '#121517',
      },
    },
    fontFamily: {
      sans: ['Inter Variable', 'sans-serif'],
    },
    extend: {
      height: { canvas: '1080px' },
      width: { canvas: '1920px' },
    },
  },
  plugins: [],
};
