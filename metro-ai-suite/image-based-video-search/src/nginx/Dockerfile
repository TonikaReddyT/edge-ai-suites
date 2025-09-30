FROM nginx:1.27-alpine

# Install OpenSSL
RUN apk add --no-cache openssl bash

# Copy nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy cert generation script
COPY generate_certs.sh /usr/local/bin/generate_certs.sh
RUN chmod +x /usr/local/bin/generate_certs.sh

# Create SSL directory
RUN mkdir -p /etc/nginx/ssl

# Expose ports
EXPOSE 80 443

# Run script (which starts nginx)
ENTRYPOINT ["/usr/local/bin/generate_certs.sh"]
