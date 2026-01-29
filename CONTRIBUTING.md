# Contributing to macula-mri-khepri

Thank you for your interest in contributing!

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/my-feature`)
3. **Commit** your changes with descriptive messages
4. **Push** to your fork
5. **Submit** a Pull Request

## Development Setup

```bash
# Clone and build
git clone https://github.com/macula-io/macula-mri-khepri.git
cd macula-mri-khepri
rebar3 compile

# Run tests
rebar3 eunit

# Run dialyzer
rebar3 dialyzer

# Generate docs
rebar3 ex_doc
```

## Code Standards

- Follow Erlang/OTP conventions
- Add `@doc` and `-spec` for all exported functions
- Write tests for new functionality
- Keep commits focused and atomic

## Reporting Issues

Please use [GitHub Issues](https://github.com/macula-io/macula-mri-khepri/issues) with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Erlang/OTP version

## License

By contributing, you agree that your contributions will be licensed under Apache-2.0.
