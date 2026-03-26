FROM node:20-alpine

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY src/ ./src/
COPY rbac/ ./rbac/

USER node
EXPOSE 18791
CMD ["node", "src/index.js"]
