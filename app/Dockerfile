FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_CALLSIGN=syedazam
ENV VITE_CALLSIGN=$VITE_CALLSIGN
RUN npm test && npm run build

FROM nginx:1.30-alpine
COPY --from=build /app/dist/ /usr/share/nginx/html/
EXPOSE 80
