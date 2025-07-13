import js from '@eslint/js'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: [
      'node_modules/**',
      '**/node_modules/**',
      'dist/**',
      '**/dist/**',
      'build/**',
      '**/build/**',
      'coverage/**',
      '**/coverage/**',
      '.turbo/**',
      '**/.turbo/**',
      '**/target/**',
      'apps/*/target/**',
      'apps/server/deps/**',
      'apps/server/priv/**',
      'apps/server/_build/**',
      'apps/dashboard/src-tauri/target/**',
      'apps/nurvus/_build/**',
      'apps/nurvus/deps/**',
      'apps/nurvus/burrito_out/**',
      '**/*.gen.ts',
      '**/routeTree.gen.ts',
      '**/phoenix.js',
      'apps/dashboard/node_modules/**',
      'apps/overlays/node_modules/**',
      'apps/**/.venv/**',
      'apps/**/venv/**',
      '**/site-packages/**'
    ]
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    rules: {
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn'
    }
  }
)
