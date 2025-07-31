# Database Migration System

## Overview

Chiikawarden uses a consolidated database migration system built on SQLx for SQLite. The system has been optimized for pre-release development with a single comprehensive schema file that eliminates migration inconsistencies.

## Current State

### Consolidated Schema (v1.0)
- **File**: `migrations/001_initial_schema.sql`
- **Status**: Complete consolidated schema including all tables, indexes, triggers, and optimizations
- **Migration Version**: 1
- **Consolidation Date**: Pre-release development phase
- **Previous Migrations**: Combined migrations 001, 002, and 003 into single file

### Database Tables
- `users` - User accounts with authentication data
- `ciphers` - Encrypted vault items
- `folders` - Organization folders
- `collections` - Organization collections
- `sync_state` - Synchronization tracking with real-time sync extensions
- `audit_log` - Security audit trail
- `sessions` - User session management
- `db_stats` - Performance monitoring
- `sync_settings` - Real-time sync user preferences
- `websocket_connections` - WebSocket connection tracking
- `sync_events` - Sync events log for debugging and monitoring

## Consolidation Process

### What Was Consolidated
The following migration files were consolidated into `001_initial_schema.sql`:
- **Original 001_initial_schema.sql**: Base database schema with core tables
- **Original 002_realtime_sync_extensions.sql**: Real-time sync functionality
- **Original 003_add_sessions_table.sql**: Sessions table (redundant, already in 001)

### Consolidation Benefits
- **Eliminates Migration Inconsistencies**: Single source of truth for database structure
- **Simplified Development**: No need to track multiple migration files during pre-release
- **Faster Database Initialization**: Single migration execution instead of sequential migrations
- **Reduced Complexity**: Easier to understand complete database structure

### Important Notes
- **Development Database Reset Required**: Existing development databases need to be reset
- **Pre-release Only**: This consolidation is intended for pre-release development phase
- **Future Migrations**: Post-release migrations will be incremental additions

## Migration Guidelines

### For Future Migrations (Post-Release)

1. **Create New Migration Files**
   ```
   migrations/002_add_new_feature.sql
   migrations/003_performance_improvements.sql
   ```

2. **Migration File Structure**
   ```sql
   -- Migration description and purpose
   -- Version: 002
   -- Description: Add new feature X
   
   -- Table modifications
   ALTER TABLE users ADD COLUMN new_field TEXT;
   
   -- Index creation
   CREATE INDEX IF NOT EXISTS idx_users_new_field ON users(new_field);
   
   -- Data migration (if needed)
   UPDATE users SET new_field = 'default_value' WHERE new_field IS NULL;
   ```

3. **Update Migration Runner**
   ```rust
   // In migrations.rs, add new migration to the vector
   Migration {
       version: 2,
       description: "add_new_feature".to_string(),
       sql: include_str!("../../../migrations/002_add_new_feature.sql").to_string(),
   },
   ```

### Best Practices

#### DO:
- ✅ Use `IF NOT EXISTS` for table and index creation
- ✅ Include descriptive comments in migration files
- ✅ Test migrations on a copy of production data
- ✅ Use transactions for data modifications
- ✅ Validate migration SQL before deployment
- ✅ Keep migrations small and focused
- ✅ Use proper data types and constraints

#### DON'T:
- ❌ Modify existing migration files after release
- ❌ Drop tables or columns without careful consideration
- ❌ Use hardcoded values in migrations
- ❌ Skip version numbers in migration sequence
- ❌ Mix schema changes with data changes in complex ways

### Migration Safety

#### Pre-Migration Checks
1. Backup database before applying migrations
2. Validate SQL syntax
3. Check for potential data loss operations
4. Verify foreign key constraints
5. Test on development/staging environment

#### Post-Migration Validation
1. Verify all tables exist and have correct structure
2. Check indexes are created properly
3. Validate triggers are working
4. Run application tests
5. Monitor performance impact

## Development Workflow

### Local Development
1. **Database Reset**: Use development utilities to reset local database
2. **Schema Changes**: Modify consolidated schema during pre-release
3. **Testing**: Run validation scripts to ensure consistency

### Production Deployment
1. **Backup**: Always backup production database
2. **Migration**: Apply new migrations in sequence
3. **Validation**: Run health checks post-migration
4. **Monitoring**: Monitor application performance

## Troubleshooting

### Common Issues

#### Migration Already Applied
```
Error: Migration version X already applied
```
**Solution**: Check `__migrations` table to see applied migrations

#### Column Already Exists
```
Error: duplicate column name
```
**Solution**: Use `ALTER TABLE ADD COLUMN IF NOT EXISTS` (SQLite 3.35+) or check column existence first

#### Foreign Key Constraint Failed
```
Error: FOREIGN KEY constraint failed
```
**Solution**: Ensure referenced tables/columns exist and data is consistent

### Recovery Procedures

#### Rollback Migration (Development Only)
1. Restore from backup
2. Remove migration entry from `__migrations` table
3. Fix migration SQL and reapply

#### Data Corruption
1. Stop application
2. Restore from latest backup
3. Reapply migrations from backup point
4. Validate data integrity

## Monitoring and Maintenance

### Health Checks
- Database connectivity
- Migration status
- Table integrity
- Index effectiveness
- Performance metrics

### Performance Monitoring
- Query execution times
- Index usage statistics
- Database size growth
- Connection pool metrics

## Tools and Utilities

### Development Commands
```bash
# Validate schema
cargo run --bin validate_schema

# Reset development database
cargo run --bin reset_dev_db

# Check migration status
cargo run --bin migration_status
```

### Database Inspection
```sql
-- Check applied migrations
SELECT * FROM __migrations ORDER BY version;

-- Verify table structure
.schema table_name

-- Check indexes
SELECT name, sql FROM sqlite_master WHERE type='index';

-- Analyze performance
ANALYZE;
EXPLAIN QUERY PLAN SELECT ...;
```

## Security Considerations

- Never log sensitive data during migrations
- Use parameterized queries for data modifications
- Validate input data before migration
- Audit migration changes
- Secure migration files in version control

## Version History

- **v1.0**: Consolidated schema with all tables, indexes, and triggers
- **Future**: Incremental migrations for new features and optimizations
