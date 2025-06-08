# Contributing to Docker MCP Stack

Thank you for your interest in contributing to the Docker MCP Stack project! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Contributing Process](#contributing-process)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation Standards](#documentation-standards)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Security Reporting](#security-reporting)

## Code of Conduct

This project adheres to a code of conduct that ensures a welcoming and inclusive environment for all contributors. By participating, you agree to uphold these standards:

- Be respectful and inclusive
- Focus on constructive feedback
- Accept responsibility for mistakes
- Support the community and project goals

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Git
- Basic knowledge of containerization and shell scripting
- Familiarity with nginx, Prometheus, and monitoring systems (for infrastructure contributions)

### Initial Setup

1. Fork the repository
2. Clone your fork locally:

   ```bash
   git clone https://github.com/your-username/docker-mcp-stack.git
   cd docker-mcp-stack
   ```

3. Set up the development environment:

   ```bash
   # Copy and configure environment file
   cp .env.secure.example .env
   # Edit .env with appropriate values
   
   # Install development dependencies
   npm install
   ```

4. Verify your setup:

   ```bash
   # Run tests and linting
   npm run lint:md
   make test
   ```

## Development Environment

### Using Development Container

The project includes a VS Code development container configuration:

1. Install Docker and VS Code with the Remote-Containers extension
2. Open the project in VS Code
3. When prompted, click "Reopen in Container"
4. The development environment will be automatically configured

### Manual Setup

If not using the development container:

1. Install required tools:
   - Node.js 20+ (for markdown linting)
   - shellcheck (for shell script linting)
   - docker-compose
   - make

2. Install project dependencies:

   ```bash
   npm install
   ```

## Contributing Process

1. **Create an Issue**: Before starting work, create or find an existing issue describing the problem or enhancement
2. **Fork and Branch**: Fork the repository and create a feature branch
3. **Develop**: Make your changes following the coding standards
4. **Test**: Ensure all tests pass and add new tests if needed
5. **Document**: Update documentation for any new features or changes
6. **Submit**: Create a pull request with a clear description

## Coding Standards

### Shell Scripts

- Use `#!/bin/bash` for all shell scripts
- Enable strict mode: `set -euo pipefail`
- Use meaningful variable names in UPPERCASE for constants
- Include error handling and logging
- Follow the existing pattern from utility scripts
- Use shellcheck for linting

```bash
#!/bin/bash
# Brief description of the script purpose

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function example
function main() {
    local arg="$1"
    
    if [[ -z "$arg" ]]; then
        log_error "Missing required argument"
        return 1
    fi
    
    log_info "Processing: $arg"
    # Implementation
}
```

### Docker and Compose

- Use specific image tags, avoid `latest`
- Include health checks for all services
- Use multi-stage builds where appropriate
- Follow Docker security best practices
- Add resource limits for production services

### Configuration

- Use environment variables for configuration
- Provide secure defaults in `.env.secure.example`
- Document all configuration options
- Validate configuration in scripts

### Nginx Configuration

- Follow security best practices
- Include appropriate headers
- Use rate limiting for public endpoints
- Comment complex configurations

## Testing Guidelines

### Running Tests

```bash
# Run all tests
make test

# Run specific test categories
make test-backup
make test-health
make test-benchmark
```

### Writing Tests

- Add tests for all new functionality
- Include both positive and negative test cases
- Test error conditions and edge cases
- Use descriptive test names

### Test Structure

```bash
#!/bin/bash
# test_example.sh

source "$(dirname "$0")/../scripts/utils/validation.sh"

test_example_function() {
    local result
    result=$(example_function "test_input")
    
    if [[ "$result" == "expected_output" ]]; then
        log_info "✅ Test passed: example_function"
        return 0
    else
        log_error "❌ Test failed: example_function"
        log_error "Expected: expected_output"
        log_error "Got: $result"
        return 1
    fi
}
```

## Documentation Standards

### Markdown

- Follow the project's markdownlint configuration
- Use clear, concise language
- Include code examples where appropriate
- Keep line length under 120 characters
- Use proper heading hierarchy

### Code Documentation

- Include comments for complex logic
- Document function parameters and return values
- Provide usage examples for scripts
- Update README when adding new features

### API Documentation

- Document all endpoints in `docs/api-reference.md`
- Include request/response examples
- Document error conditions
- Provide usage examples

## Commit Message Guidelines

Follow the conventional commit format:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(backup): add differential backup support

Implement differential backup functionality to complement
existing full and incremental backup strategies.

Closes #123
```

```
fix(nginx): resolve rate limiting configuration issue

Update nginx configuration to properly handle rate limiting
for the API endpoints.

Fixes #456
```

## Pull Request Process

1. **Title**: Use a clear, descriptive title
2. **Description**: Provide a detailed description of changes
3. **Testing**: Describe how the changes were tested
4. **Documentation**: Note any documentation updates
5. **Breaking Changes**: Highlight any breaking changes
6. **Checklist**: Complete the PR checklist

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] All existing tests pass
- [ ] New tests added and pass
- [ ] Manual testing completed

## Documentation
- [ ] README updated
- [ ] API documentation updated
- [ ] Changelog updated

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] No new warnings introduced
```

## Issue Reporting

When reporting issues:

1. **Search** existing issues first
2. **Use templates** provided for bug reports and feature requests
3. **Provide context**: Include environment details, steps to reproduce
4. **Include logs**: Attach relevant log files or error messages
5. **Be specific**: Clear, actionable descriptions

### Bug Report Template

- Environment (OS, Docker version, etc.)
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages/logs
- Additional context

## Security Reporting

For security vulnerabilities:

1. **Do not** create public issues
2. **Email** security concerns to project maintainers
3. **Include** detailed description and reproduction steps
4. **Allow** reasonable time for response and fix

## Getting Help

- **Documentation**: Check existing documentation first
- **Issues**: Search existing issues for similar problems
- **Discussions**: Use GitHub Discussions for questions
- **Community**: Engage respectfully with the community

## Recognition

Contributors will be recognized in:

- CHANGELOG.md for significant contributions
- README.md contributors section
- Release notes for major features

Thank you for contributing to Docker MCP Stack! Your efforts help improve the project for everyone.
