# Horizon db migrations
Database schemas and objects for horizon services. 
### Usage:
1. db-migrate up # Applies commons and deployer, creates base roles and objects
2. db-migrate up:auth # Auth Schema def
3. db-migrate up:esi # Esi depdends on auth
4. bin/dev-evesde-all # Download and restore eve sde data from fuzzwork
5.  db-migrate up:api
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
