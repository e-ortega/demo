# Stage 1: build the static assets
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
# if you use yarn change accordingly
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: serve with nginx
FROM nginx:stable-alpine
# remove default config and copy our custom config if needed (optional)
RUN rm -rf /usr/share/nginx/html/*
COPY --from=builder /app/dist /usr/share/nginx/html
# Optional: copy a custom nginx conf if you want SPA fallback to index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
