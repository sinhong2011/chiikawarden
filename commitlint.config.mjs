/**
 * Commitlint configuration for Chiikawarden
 * Enforces conventional commit message standards
 * 
 * @see https://commitlint.js.org/
 * @see https://www.conventionalcommits.org/
 */

export default {
  extends: ['@commitlint/config-conventional'],
  
  rules: {
    // Type enum - allowed commit types
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation changes
        'style',    // Code style changes (formatting, missing semi-colons, etc)
        'refactor', // Code refactoring without changing functionality
        'perf',     // Performance improvements
        'test',     // Adding or updating tests
        'chore',    // Maintenance tasks, dependency updates
        'ci',       // CI/CD related changes
        'build',    // Build system or external dependencies
        'revert',   // Reverting previous commits
        'wip',      // Work in progress (use sparingly)
      ],
    ],
    
    // Subject and body rules
    'subject-case': [2, 'never', ['pascal-case', 'upper-case']],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    'subject-max-length': [2, 'always', 72],
    'subject-min-length': [2, 'always', 10],
    
    // Header rules
    'header-max-length': [2, 'always', 100],
    'header-min-length': [2, 'always', 15],
    
    // Body rules
    'body-leading-blank': [2, 'always'],
    'body-max-line-length': [2, 'always', 100],
    
    // Footer rules
    'footer-leading-blank': [2, 'always'],
    'footer-max-line-length': [2, 'always', 100],
    
    // Type and scope rules
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'lower-case'],
    'scope-empty': [0], // Scope is optional
    
    // Additional custom rules for this project
    'signed-off-by': [0], // Not required for this project
    
    // Custom scope validation for project-specific areas
    'scope-enum': [
      2,
      'always',
      [
        // Frontend scopes
        'ui',
        'components',
        'hooks',
        'stores',
        'services',
        'routes',
        'auth',
        'vault',
        'forms',
        'i18n',
        
        // Backend scopes
        'tauri',
        'rust',
        'crypto',
        'storage',
        'api',
        'commands',
        'models',
        
        // Infrastructure scopes
        'build',
        'config',
        'deps',
        'ci',
        'docs',
        'tests',
        'storybook',
        'types',
        
        // Feature scopes
        'migration',
        'security',
        'performance',
        'accessibility',
      ],
    ],
  },
  
  // Help URL for developers
  helpUrl: 'https://github.com/conventional-changelog/commitlint/#what-is-commitlint',
};
