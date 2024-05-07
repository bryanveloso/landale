import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
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
        shark: {
          '50': '#d3dfdf',
          '100': '#c0cfd3',
          '200': '#a8bac2',
          '300': '#819ba7',
          '400': '#5a737c',
          '500': '#44585f',
          '600': '#35434b',
          '700': '#2b353b',
          '800': '#232a2e', // 'gradent.lighter'
          '900': '#1a1f23', // 'gradient.darker'
          '950': '#121517',
        },
      },
      fontFamily: {
        sans: ['var(--font-geist-sans)'],
        mono: ['var(--font-geist-mono)'],
      },
    },
  },
  plugins: [],
};

export default config;
