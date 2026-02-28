FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache docker-cli

COPY package.json ./
RUN npm install --production

COPY server.js ./
COPY rbac-registry.js ./
COPY rbac/ ./rbac/

EXPOSE 18790

CMD ["node", "server.js"]
