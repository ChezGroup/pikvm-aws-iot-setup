# Contributing to PiKVM AWS IoT Setup

Thank you for your interest in contributing! This document provides guidelines
for contributing to this project.

## 🚀 Getting Started

1. Fork the repository
2. Clone your fork:
   `git clone https://github.com/your-username/pikvm-aws-iot-setup.git`
3. Create a feature branch: `git checkout -b feature/amazing-feature`
4. Make your changes
5. Test your changes on actual PiKVM hardware
6. Commit: `git commit -m 'Add amazing feature'`
7. Push: `git push origin feature/amazing-feature`
8. Open a Pull Request

## 📋 Development Guidelines

### Shell Script Standards

- **ShellCheck**: All scripts must pass ShellCheck validation
- **Bash**: Use bash-specific features (we require bash)
- **Error handling**: Use `set -e` and check return codes
- **Comments**: Add comments for complex logic
- **Functions**: Use functions for reusable code

### Code Style

```bash
# Good - Clear variable names
PROJECT_PREFIX="my-company"
DEVICE_ID="abc123"

# Bad - Unclear names
PP="mc"
DI="abc123"

# Good - Proper error handling
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

# Bad - No error handling
aws sts get-caller-identity
```

### Testing

Before submitting a PR:

1. **Test on PiKVM**: Actually run the scripts on PiKVM hardware
2. **Test all paths**: Test both fresh install and upgrade scenarios
3. **Test error handling**: Try invalid configurations
4. **Run ShellCheck**: `shellcheck *.sh`

### Documentation

- Update README.md if adding features
- Add comments for complex code
- Update config.sh.example for new options
- Include examples in commit messages

## 🐛 Reporting Bugs

When reporting bugs, please include:

1. **Description**: Clear description of the issue
2. **Steps to reproduce**: How to reproduce the problem
3. **Expected behavior**: What should happen
4. **Actual behavior**: What actually happens
5. **Environment**: PiKVM version, OS, etc.
6. **Logs**: Relevant log output

## 💡 Suggesting Features

Feature requests are welcome! Please:

1. Check if the feature already exists
2. Explain the use case
3. Provide examples if possible
4. Consider backward compatibility

## 🔄 Pull Request Process

1. **Update documentation**: README, comments, etc.
2. **Add tests**: If applicable
3. **Follow code style**: Match existing code
4. **One feature per PR**: Keep PRs focused
5. **Update CHANGELOG**: Add entry to CHANGELOG.md
6. **CI must pass**: All checks must be green

### PR Title Format

```
feat: Add support for custom device IDs
fix: Certificate permission issues on fresh install
docs: Update installation instructions
chore: Update dependencies
```

## 📝 Commit Message Format

Follow conventional commits:

```
<type>: <subject>

<body>

<footer>
```

Types:

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

Example:

```
feat: Add certificate backup functionality

- Added backup command to manage_certificates.sh
- Creates timestamped tar.gz archives
- Stores backups in /tmp by default

Closes #42
```

## 🔒 Security

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email security concerns to: [security contact]
3. Include detailed description
4. We'll respond within 48 hours

## ❓ Questions

Have questions? Feel free to:

- Open a
  [Discussion](https://github.com/ChezGroup/pikvm-aws-iot-setup/discussions)
- Ask in an existing issue
- Check the [FAQ](README.md#faq)

## 📄 License

By contributing, you agree that your contributions will be licensed under the
MIT License.

Thank you for contributing! 🎉
