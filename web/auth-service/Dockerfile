FROM node:20-alpine

WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY src/ ./src/
COPY rbac/ ./rbac/

EXPOSE 18791
CMD ["node", "src/index.js"]
