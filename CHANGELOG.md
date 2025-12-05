# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial public release
- Automated installation script
- AWS IoT certificate generation and management
- Mosquitto MQTT bridge configuration
- Certificate backup and restore functionality
- Comprehensive troubleshooting tool
- Full documentation and examples
- CI/CD with GitHub Actions (ShellCheck, validation, releases)

### Security
- Configuration files excluded from version control
- Certificate permissions properly set (600 for private keys)
- TLS 1.2 minimum for AWS IoT connections

## [1.0.0] - 2025-12-05

### Added
- Complete PiKVM AWS IoT setup automation
- Configurable project prefix and device identification
- MQTT topic customization
- AWS IoT policy management
- PiKVM PST (persistent storage) integration
- Support for multiple device identification methods (CPU serial, MAC address, custom)
- Detailed logging and error handling

### Documentation
- Comprehensive README with examples
- Configuration template with all options
- Contributing guidelines
- MIT License

### CI/CD
- ShellCheck validation workflow
- Script validation workflow
- Automated release workflow
- GitHub Actions badges

[Unreleased]: https://github.com/ChezGroup/pikvm-aws-iot-setup/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ChezGroup/pikvm-aws-iot-setup/releases/tag/v1.0.0
