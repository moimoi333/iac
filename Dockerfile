FROM node:18-bookworm-slim
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY public/ ./public/
COPY server.js ./
# Les données du repo deviennent les défauts (copiés au 1er démarrage si le PVC est vide)
COPY data/ ./defaults/
RUN mkdir -p ./data

EXPOSE 3000
CMD ["node", "server.js"]
