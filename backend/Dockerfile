FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
COPY server.mjs ./
EXPOSE 8080
CMD ["npm", "start"]
