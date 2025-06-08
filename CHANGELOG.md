# Changelog

All notable changes to the Docker MCP Stack project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Comprehensive API reference documentation in `docs/api-reference.md`
- Security-focused environment configuration template (`.env.secure.example`)
- Enhanced nginx configuration with security headers and rate limiting
- Resource limits for SmolLM2 model runner in Docker Compose
- Standardized `.gitignore` file with comprehensive exclusions
- Directory structure preservation with `.gitkeep` files in backup folders
- Contributing guidelines and project governance documentation
- This changelog file to track project evolution

### Enhanced

- Improved security posture with stronger default configurations
- Better documentation structure and API usage examples
- Enhanced backup directory organization and version control integration

### Security

- Added OWASP-recommended security headers in nginx configuration
- Implemented rate limiting to prevent abuse
- Created secure environment variable templates with strong password guidance
- Enhanced gitignore patterns to prevent accidental exposure of sensitive data

## [1.0.0] - Initial Release

### Added

- Docker Compose stack with Gordon MCP integration
- SmolLM2 model runner with configurable parameters
- Comprehensive backup and recovery system with full, incremental, and differential backups
- Monitoring stack with Prometheus and Grafana
- Nginx reverse proxy with SSL/TLS support
- Automated health monitoring and service management scripts
- Benchmark testing framework for model performance evaluation
- SystemD service integration for production deployments
- Markdown documentation linting and validation
- Development container support with VS Code integration

### Features

- **Multi-Model Support**: Flexible architecture supporting various AI models
- **Monitoring & Observability**: Built-in Prometheus metrics and Grafana dashboards
- **Backup System**: Automated backup strategies with rotation and validation
- **Security**: SSL/TLS encryption and security-focused configurations
- **Development Tools**: Integrated linting, testing, and development workflows
- **Production Ready**: SystemD service files and production deployment scripts

### Infrastructure

- Docker Compose orchestration for all services
- Nginx reverse proxy with load balancing capabilities
- Prometheus monitoring with custom metrics collection
- Grafana dashboards for system visualization
- Automated SSL certificate management
- Health check endpoints for all services

### Documentation

- Comprehensive README with setup and usage instructions
- Backup and recovery documentation
- Markdown linting setup guide
- API reference and usage examples
- Development and contribution guidelines
