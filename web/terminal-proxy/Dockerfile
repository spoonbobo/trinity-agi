FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache docker-cli

COPY package.json ./
RUN npm install --production

COPY server.js ./
COPY rbac/ ./rbac/
COPY rbac/rbac-registry.js ./

EXPOSE 18790

CMD ["node", "server.js"]
