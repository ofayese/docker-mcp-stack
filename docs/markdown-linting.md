# Markdown Linting Configuration

This directory contains the markdown linting configuration for the Docker MCP Stack project.
The setup ensures consistent, high-quality documentation across all markdown files.

## 📁 Files Overview

- **`.markdownlint.json`** - Main configuration file with linting rules
- **`.markdownlintignore`** - Files and directories to exclude from linting
- **`package.json`** - Node.js dependencies and scripts for markdown linting
- **`scripts/lint-docs.ps1`** - PowerShell utility script for various linting operations

## 🚀 Quick Start

### Installation

Install the markdown linting dependencies:

```bash
# Using npm
npm install

# Or using Make
make lint-docs-install
```

### Usage

#### Check for Issues

```bash
# Check all markdown files
npm run lint:md

# Or using Make
make lint-docs

# Or using PowerShell script directly
./scripts/lint-docs.ps1 -Action check
```

#### Auto-fix Issues

```bash
# Auto-fix all markdown files
npm run lint:md:fix

# Or using Make
make lint-docs-fix

# Or using PowerShell script
./scripts/lint-docs.ps1 -Action fix
```

#### Generate Report

```bash
# Generate detailed report
make lint-docs-report

# Or using PowerShell script
./scripts/lint-docs.ps1 -Action report
```

## ⚙️ Configuration Details

### Enabled Rules

The `.markdownlint.json` configuration includes the following key settings:

| Rule | Setting | Description |
|------|---------|-------------|
| **MD003** | `atx` | Use ATX-style headers (`#`, `##`, etc.) |
| **MD007** | `indent: 2` | Use 2-space indentation for lists |
| **MD013** | `line_length: 120` | Maximum line length of 120 characters |
| **MD024** | `siblings_only: true` | Allow duplicate headers if not siblings |
| **MD033** | Allow specific HTML | Permit certain HTML elements |
| **MD046** | `fenced` | Use fenced code blocks |
| **MD048** | `backtick` | Use backticks for code fences |

### Ignored Elements

The following are excluded from linting:

- Files in `node_modules/`
- Files in `backups/`
- Log files (`*.log`)
- Temporary files (`*.tmp`, `*.temp`)
- IDE/editor files (`.vscode/`, `.idea/`, etc.)
- OS-generated files (`.DS_Store`, `Thumbs.db`)

## 📝 Available Scripts

### NPM Scripts

| Script | Command | Description |
|--------|---------|-------------|
| `lint:md` | `markdownlint "**/*.md"` | Lint all markdown files |
| `lint:md:fix` | `markdownlint "**/*.md" --fix` | Auto-fix markdown issues |
| `lint:md:config` | `markdownlint --config .markdownlint.json "**/*.md"` | Lint with explicit config |
| `docs:check` | `npm run lint:md` | Alias for checking docs |
| `docs:fix` | `npm run lint:md:fix` | Alias for fixing docs |

### Make Targets

| Target | Description |
|--------|-------------|
| `make lint-docs-install` | Install dependencies |
| `make lint-docs` | Check markdown files |
| `make lint-docs-fix` | Auto-fix markdown issues |
| `make lint-docs-report` | Generate detailed report |

### PowerShell Script Actions

| Action | Description |
|--------|-------------|
| `check` | Check markdown files for issues |
| `fix` | Auto-fix issues where possible |
| `report` | Generate comprehensive linting report |
| `install` | Install required dependencies |
| `help` | Show detailed help information |

## 🔧 Customization

### Adding New Rules

To add or modify linting rules, edit `.markdownlint.json`:

```json
{
  "default": true,
  "MD001": false,
  "MD013": {
    "line_length": 100
  }
}
```

### Ignoring Files

To ignore additional files or directories, add them to `.markdownlintignore`:

```gitignore
# Custom ignores
temp-docs/
*.draft.md
```

### Rule References

For a complete list of available rules, see:

- [Markdownlint Rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)
- [Markdownlint CLI](https://github.com/igorshubovych/markdownlint-cli)

## 🎯 Best Practices

### Writing Guidelines

1. **Headers**: Use ATX-style headers (`#`, `##`, `###`)
2. **Line Length**: Keep lines under 120 characters
3. **Lists**: Use consistent 2-space indentation
4. **Code Blocks**: Use fenced code blocks with language specification
5. **Links**: Use reference-style links for readability
6. **Tables**: Ensure proper alignment and formatting

### Integration

#### CI/CD Integration

Add to your CI/CD pipeline:

```yaml
- name: Lint Documentation
  run: |
    npm install
    npm run lint:md
```

#### Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/sh
npm run lint:md
```

#### VS Code Integration

Install the [markdownlint extension](https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint)
for real-time linting in VS Code.

## 🐛 Troubleshooting

### Common Issues

1. **Command not found**: Ensure npm packages are installed with `npm install`
2. **Permission denied**: On Unix systems, make scripts executable: `chmod +x scripts/lint-docs.ps1`
3. **Config not found**: Ensure `.markdownlint.json` exists in the project root

### Getting Help

Run the help command for detailed usage information:

```bash
./scripts/lint-docs.ps1 -Action help
```

## 📚 Resources

- [Markdownlint Documentation](https://github.com/DavidAnson/markdownlint)
- [Markdown Style Guide](https://google.github.io/styleguide/docguide/style.html)
- [CommonMark Specification](https://commonmark.org/)
