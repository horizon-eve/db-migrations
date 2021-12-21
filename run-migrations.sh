#!/usr/bin/env bash
set -e

# Applies commons and deployer
node node_modules/db-migrate/bin/db-migrate up --auth_pwd ${AUTHPASSWORD} --api_pwd ${APIPASSWORD} --apisu_pwd ${APISUPASSWORD} --esi_pwd ${ESIPASSWORD} --database ${PGDATABASE}

node node_modules/db-migrate/bin/db-migrate up:auth # Auth Schema def
node node_modules/db-migrate/bin/db-migrate up:esi # Esi depdends on auth
bin/dev-evesde-all # Download and restore eve sde data from fuzzwork
node node_modules/db-migrate/bin/db-migrate up:api
