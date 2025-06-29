import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import reactPlugin from 'eslint-plugin-react'
import reactHooksPlugin from 'eslint-plugin-react-hooks'

export default tseslint.config(
  // Global ignores
  {
    ignores: [
      '**/dist/**',
      '**/node_modules/**',
      '**/.turbo/**',
      '**/coverage/**',
      'ecosystem/**',
      'packages/*/dist/**',
      'packages/*/build/**',
      'apps/analysis/**',
      'apps/phononmaser/**',
      'scripts/**/*.sh'
    ]
  },

  // JavaScript files - basic rules only, no TypeScript parser
  {
    files: ['**/*.{js,mjs,cjs}'],
    extends: [js.configs.recommended],
    rules: {
      'no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true
        }
      ]
    }
  },

  // TypeScript files - full type-aware rules
  {
    files: ['**/*.{ts,tsx}'],
    extends: [js.configs.recommended, ...tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname
      }
    },
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true,
          destructuredArrayIgnorePattern: '^_'
        }
      ],
      '@typescript-eslint/consistent-type-imports': [
        'error',
        {
          prefer: 'type-imports',
          fixStyle: 'inline-type-imports'
        }
      ],
      '@typescript-eslint/no-misused-promises': [
        'error',
        {
          checksVoidReturn: {
            attributes: false,
            arguments: false
          }
        }
      ],
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/prefer-nullish-coalescing': 'warn',
      '@typescript-eslint/prefer-optional-chain': 'warn',
      '@typescript-eslint/restrict-template-expressions': 'off',
      '@typescript-eslint/no-unnecessary-condition': 'off'
    }
  },

  // React-specific rules for React apps
  {
    files: ['apps/dashboard/**/*.{ts,tsx}', 'apps/overlays/**/*.{ts,tsx}'],
    plugins: {
      react: reactPlugin,
      'react-hooks': reactHooksPlugin
    },
    settings: {
      react: {
        version: 'detect'
      }
    },
    rules: {
      ...reactPlugin.configs.recommended.rules,
      ...reactHooksPlugin.configs.recommended.rules,
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off',
      'react/jsx-uses-react': 'off',
      'react/display-name': 'off'
    }
  },

  // Server-specific rules (Node.js environment)
  {
    files: ['apps/server/**/*.{ts,js}'],
    rules: {
      'no-console': 'off', // Console logging is fine in server code
      '@typescript-eslint/require-await': 'off', // Async handlers often don't await
      '@typescript-eslint/no-misused-promises': 'off' // Express handlers return promises
    }
  },

  // Package-specific rules (stricter for shared code)
  {
    files: ['packages/**/*.{ts,js}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'error', // Packages should be well-typed
      'no-console': 'warn' // Packages shouldn't log directly
    }
  },

  // Scripts - relaxed rules for utility scripts
  {
    files: ['scripts/**/*.{ts,js}'],
    rules: {
      'no-console': 'off', // Scripts often need console output
      '@typescript-eslint/no-explicit-any': 'off', // Scripts can be more flexible
      '@typescript-eslint/no-unused-vars': 'warn', // Warn instead of error
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-return': 'off'
    }
  },

  // Test files - more relaxed rules
  {
    files: ['**/*.{test,spec}.{ts,tsx,js,jsx}', '**/__tests__/**/*.{ts,tsx,js,jsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off'
    }
  }
)
