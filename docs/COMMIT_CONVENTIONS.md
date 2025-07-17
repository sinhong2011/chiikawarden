# Commit Message Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to ensure consistent and meaningful commit messages. All commit messages are automatically validated using [commitlint](https://commitlint.js.org/) integrated with [Lefthook](https://github.com/evilmartians/lefthook).

## Format

```
type(scope): description

[optional body]

[optional footer(s)]
```

## Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(auth): add biometric authentication` |
| `fix` | Bug fix | `fix(vault): resolve cipher decryption issue` |
| `docs` | Documentation changes | `docs(readme): update installation guide` |
| `style` | Code style changes (formatting, etc.) | `style(components): fix indentation` |
| `refactor` | Code refactoring | `refactor(hooks): extract auth logic` |
| `perf` | Performance improvements | `perf(crypto): optimize encryption speed` |
| `test` | Adding or updating tests | `test(auth): add login flow tests` |
| `chore` | Maintenance tasks | `chore(deps): update dependencies` |
| `ci` | CI/CD changes | `ci(github): add security scanning` |
| `build` | Build system changes | `build(tauri): update build config` |
| `revert` | Reverting commits | `revert: feat(auth): add oauth support` |

## Scopes

Scopes help identify which part of the codebase is affected:

### Frontend Scopes
- `ui` - User interface components
- `components` - React components
- `hooks` - Custom React hooks
- `stores` - State management (Zustand)
- `services` - Business logic services
- `routes` - Routing and pages
- `auth` - Authentication features
- `vault` - Vault management
- `forms` - Form components and validation
- `i18n` - Internationalization

### Backend Scopes
- `tauri` - Tauri application layer
- `rust` - Rust backend code
- `crypto` - Cryptographic services
- `storage` - Data storage layer
- `api` - API integration
- `commands` - Tauri commands
- `models` - Data models

### Infrastructure Scopes
- `build` - Build configuration
- `config` - Configuration files
- `deps` - Dependencies
- `ci` - Continuous integration
- `docs` - Documentation
- `tests` - Testing infrastructure
- `storybook` - Storybook configuration
- `types` - TypeScript types

### Feature Scopes
- `migration` - Migration-related changes
- `security` - Security improvements
- `performance` - Performance optimizations
- `accessibility` - Accessibility improvements

## Examples

### Good Commit Messages

```bash
feat(auth): implement biometric authentication for vault unlock
fix(vault): resolve issue with cipher search not returning results
docs(api): add comprehensive API documentation for vault operations
refactor(components): extract reusable form validation logic
perf(crypto): optimize key derivation performance by 40%
test(auth): add comprehensive test coverage for login flows
chore(deps): update React to version 19.1.0
ci(github): add automated security vulnerability scanning
```

### Bad Commit Messages

```bash
# Too vague
fix: bug fix

# Not following format
Added new feature for authentication

# Missing type
(auth): add login functionality

# Type not in allowed list
update(auth): modify login flow

# Subject too short
feat: add auth

# Subject too long (over 72 characters)
feat(auth): implement a comprehensive biometric authentication system with support for multiple devices
```

## Rules Enforced

- **Type**: Must be one of the allowed types (required)
- **Scope**: Must be one of the defined scopes (optional but recommended)
- **Subject**: 
  - Must be 10-72 characters long
  - Must not end with a period
  - Must be in lowercase (except proper nouns)
  - Must be in imperative mood ("add" not "added" or "adds")
- **Header**: Must be 15-100 characters total
- **Body**: 
  - Must have blank line before body (if present)
  - Lines must not exceed 100 characters
- **Footer**: 
  - Must have blank line before footer (if present)
  - Lines must not exceed 100 characters

## Validation

Commit messages are automatically validated:

1. **Pre-commit**: When you commit, commitlint runs automatically via Lefthook
2. **Manual check**: Run `bun run commit:check` to validate the last commit
3. **Range check**: Run `bun run commit:lint` to check recent commits

## Bypassing Validation

⚠️ **Not recommended** - Only use in emergency situations:

```bash
git commit --no-verify -m "emergency fix"
```

## Tools and Integration

### Commitlint Configuration
- Configuration file: `commitlint.config.js`
- Extends: `@commitlint/config-conventional`
- Custom rules for project-specific scopes

### Lefthook Integration
- Hook: `commit-msg`
- Command: `bunx commitlint --edit {1}`
- Provides helpful error messages with examples

### Available Scripts
```bash
# Check last commit message
bun run commit:check

# Lint recent commits
bun run commit:lint

# Install/reinstall hooks
bun run hooks:install
```

## Benefits

1. **Consistency**: All commits follow the same format
2. **Automation**: Enables automated changelog generation
3. **Clarity**: Easy to understand what each commit does
4. **Filtering**: Easy to filter commits by type or scope
5. **Tooling**: Better integration with development tools
6. **Collaboration**: Clearer communication in team environment

## Getting Help

- **Conventional Commits**: https://www.conventionalcommits.org/
- **Commitlint**: https://commitlint.js.org/
- **Project Issues**: Create an issue if you need help with commit messages

## Migration Note

This project recently migrated from SolidJS to React. When working on migration-related changes, use the `migration` scope:

```bash
feat(migration): convert auth components from SolidJS to React
fix(migration): resolve TypeScript issues in migrated components
docs(migration): update README to reflect React architecture
```
