# pg_migrate_action

GitHub Action wrapper for `migrate.sh` — applies numbered Postgres `.sql` migrations.

```yaml
- uses: TheCavillGroup/pg_migrate_action@v1
  with:
    database-url: ${{ secrets.DATABASE_URL }}
    migrations-dir: ./migrations
    dry-run: "false"
```
