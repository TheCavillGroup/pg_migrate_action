# pg_migrate_action

GitHub Action wrapper for `migrate.sh` — applies numbered Postgres `.sql` migrations.

```yaml
- uses: TheCavillGroup/pg_migrate_action@v1
  with:
    db-username: ${{ secrets.DB_USERNAME }}
    db-password: ${{ secrets.DB_PASSWORD }}
    db-host: ${{ secrets.DB_HOST }}
    db-port: "5432"
    db-name: mydb
    migrations-dir: ./migrations
    dry-run: "false"
```
