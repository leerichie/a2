FROM node:22-alpine

WORKDIR /app
COPY package.json ./
COPY src ./src
COPY public ./public

RUN chown -R node:node /app
USER node
EXPOSE 8787
CMD ["node", "src/server.mjs"]
