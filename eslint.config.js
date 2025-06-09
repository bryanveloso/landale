import base from '@landale/eslint/base'

export default [
  ...base,
  {
    ignores: ['packages/*/dist/**', 'packages/*/build/**', '.turbo/**']
  }
]
