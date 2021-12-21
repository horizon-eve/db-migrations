FROM node:16

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

RUN npm install
# If you are building your code for production
#RUN npm ci --only=production

# postgres client
#RUN apt-get update && apt-get install -y postgresql-client-12
RUN apt-get install -y curl gnupg \
  && echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && apt-get update \
  && apt-get install -y postgresql-client-14

# Bundle app source
COPY . .

# Update permissions
RUN ["chmod", "+x", "/usr/src/app/run-migrations.sh"]
RUN ["chmod", "-R", "+x", "/usr/src/app/bin"]

CMD ./run-migrations.sh
