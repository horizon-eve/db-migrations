# Horizon db migrations
[![doks-staging](https://github.com/horizon-eve/db-migrations/actions/workflows/doks-staging.yml/badge.svg?branch=master)](https://github.com/horizon-eve/db-migrations/actions/workflows/doks-staging.yml)

Database schemas and objects for horizon services.
Follow this guide to add new migrations: https://db-migrate.readthedocs.io/en/latest/Getting%20Started/usage/
### Usage
`npm install -g db-migrate`

`db-migrate create:<scope> <migration_name> --sql-file`

Available scopes: ```auth```,```esi```,```api```,```all```.
### Order of applicaton:
1. db-migrate up # Applies commons and deployer, creates base roles and objects
2. db-migrate up:auth # Auth Schema defs
3. db-migrate up:esi # Esi depdends on auth
4. bin/dev-evesde-all # Download and transform eve sde data from fuzzwork
5.  db-migrate up:api # API definitions
### Database configuration
SQL scripts use postgres syntax 9.x+ so the config should describe pg connection, EX:
```
{
  "dev": {
    "driver": "pg",
    "user": "user",
    "password": "password",
    "host": "localhost",
    "database": "horizondb",
    "port": "5432",
    "schema": "public"
  },
  "sql-file" : true
}
``` 
