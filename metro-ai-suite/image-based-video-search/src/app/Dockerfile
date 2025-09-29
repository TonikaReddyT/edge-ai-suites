# ----------------------
# Stage 1: Build Vue app
# ----------------------
FROM node:24 as build

WORKDIR /usr/src/app

# Copy only app dependencies first (for caching)
COPY package*.json ./
RUN npm install

# Copy the rest of the app source
COPY . .

# Build Vue app for production
RUN npm run build


# ------------------------
# Stage 2: Nginx container
# ------------------------
FROM nginx:alpine

# Install openssl to generate certs
RUN apk add --no-cache openssl

# Create SSL directory (for certs at runtime)
RUN mkdir -p /etc/nginx/ssl

# Copy custom nginx.conf (path relative to build context `src/`)
COPY nginx.conf /etc/nginx/nginx.conf

# Copy built Vue app from previous stage
COPY --from=build /usr/src/app/dist /usr/share/nginx/html

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose standard HTTP + HTTPS
EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]