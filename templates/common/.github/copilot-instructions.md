# Copilot Instructions

## Project: {{PROJECT_NAME}}

### General Rules

- Write clean, readable code with minimal comments (comment only when intent is non-obvious)
- Prefer explicit over implicit
- Follow the conventions already established in this codebase
- All GitHub Actions must be pinned by full commit SHA, not by tag

### Toolchain Versions

- Pin runtime and package manager versions exactly, in each ecosystem's standard file: `.node-version`, `devEngines.packageManager` (or `packageManager`) in `package.json`, `.python-version`, `global.json`
- Use `mise.toml` only for tools that have no standard version file (e.g. Terraform, or a linter that CI runs), and pin those exactly too
- Do not loosen a pin to a major or minor range. Renovate opens the update PRs and CI checks them
- In CI, read versions from these files (e.g. `node-version-file`, `global-json-file`) instead of repeating them in workflows
- Declare every tool that the build, tests, or CI run, and only those. Do not rely on tools installed globally on a developer's machine

### Security

- Never commit secrets, API keys, or credentials
- Use environment variables or secret managers for sensitive values
- Validate all external input
