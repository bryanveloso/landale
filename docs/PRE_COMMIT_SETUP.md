# Pre-commit Hooks Setup

This project uses [pre-commit](https://pre-commit.com/) to ensure code quality and consistency across all languages used in the Landale project.

## Supported Languages and Tools

### Elixir (Apps/Server)
- **mix format**: Automatic code formatting using `.formatter.exs`
- **credo**: Static code analysis for code quality
- **mix compile**: Compilation check to catch syntax errors

### TypeScript/JavaScript (Apps/Overlays/Dashboard, Packages)
- **ESLint**: Linting with existing `eslint.config.mjs` configuration
- **Prettier**: Code formatting with existing `.prettierrc.mjs` configuration
- **TypeScript**: Type checking using `tsc --noEmit`

### Python (Apps/Analysis, Apps/Phononmaser)
- **Black**: Code formatting for Python files
- **isort**: Import sorting
- **flake8**: Linting and style checking
- **mypy**: Static type checking

### General/Multi-language
- **Trailing whitespace**: Remove trailing whitespace
- **End of file fixer**: Ensure files end with newline
- **Check merge conflicts**: Detect merge conflict markers
- **Check yaml/json/toml**: Validate configuration files
- **Large files check**: Prevent committing large files
- **Mixed line endings**: Ensure consistent line endings

## Installation

### Quick Setup
```bash
# Install pre-commit and setup hooks
./scripts/setup-pre-commit.sh
```

### Manual Setup
```bash
# Install pre-commit framework
pip install pre-commit

# Install Python development dependencies
pip install -r requirements-dev.txt

# Install hooks
bun run pre-commit:install

# Test the setup
bun run pre-commit:run
```

## Usage

### Automatic (Recommended)
Pre-commit hooks will run automatically on every `git commit`. If any hook fails, the commit will be blocked until issues are fixed.

### Manual Execution
```bash
# Run all hooks on all files
bun run pre-commit:run

# Run hooks on staged files only
bun run pre-commit:run-staged

# Update hooks to latest versions
bun run pre-commit:update
```

## Language-Specific Requirements

### Elixir
For Elixir hooks to work, you need Elixir and Mix installed:
```bash
# Install Elixir (macOS)
brew install elixir

# Or use asdf for version management
asdf install elixir 1.18.0
```

### Python
Python 3.12+ is required. Virtual environments are recommended:
```bash
# Create virtual environment for Python apps
cd apps/analysis
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### TypeScript/JavaScript
Bun is used as the primary runtime:
```bash
# Install Bun
curl -fsSL https://bun.sh/install | bash

# Install dependencies
bun install
```

## Troubleshooting

### Skipping Hooks Temporarily
```bash
# Skip all hooks for a single commit
git commit --no-verify

# Skip specific hooks
SKIP=eslint,mix-format git commit
```

### Common Issues

1. **Workspace dependency errors**: Some workspace dependencies may be missing. This is a known issue and doesn't affect pre-commit functionality.

2. **Elixir hooks failing**: Ensure Elixir is installed and `mix deps.get` has been run in `apps/server`.

3. **TypeScript hooks failing**: Ensure Bun is installed and `bun install` has been run.

4. **Python hooks failing**: Ensure Python dev dependencies are installed with `pip install -r requirements-dev.txt`.

## Configuration

The pre-commit configuration is stored in `.pre-commit-config.yaml`. You can:

- Enable/disable specific hooks
- Add new hooks
- Modify hook arguments
- Exclude specific files or directories

## Integration with CI/CD

Pre-commit hooks should also be run in CI/CD pipelines to ensure consistency:

```yaml
# Example GitHub Actions step
- name: Run pre-commit
  uses: pre-commit/action@v3.0.0
```