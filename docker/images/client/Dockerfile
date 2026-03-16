# 1. Build Stage
FROM node:20-alpine AS build

WORKDIR /app

# Copy package configuration
COPY package.json ./

# Install Node dependencies
RUN npm install

# Copy the React source code
COPY src/Client/React ./src/Client/React

# Build the static Vite application
RUN npm run build

# 2. Production Serve Stage
FROM nginx:alpine AS serve

# Remove default Nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy the built assets from the build stage
# (Vite outputs to the dist folder inside the target directory)
COPY --from=build /app/src/Client/React/dist /usr/share/nginx/html

# Expose standard HTTP port
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]