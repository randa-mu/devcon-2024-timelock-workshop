#### BASE STAGE
#### Installs Node.js, Foundry, and Moon on Ubuntu.

# Use Ubuntu as the base image
FROM ubuntu:22.04 AS base

# Set ARG for Node.js version
ARG NODE_VERSION=22

# Install required dependencies and Node.js
RUN apt-get update && \
    apt-get install -y curl ca-certificates gnupg git bash jq && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    # Verify that Node.js and npm are installed
    node -v && npm -v

# Set up the working directory
WORKDIR /app

# Install Foundry (tool from Paradigm)
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

# Copy the entire repository to /app in the container
COPY . .

RUN npm i 

RUN npm run build:all

# Install the esbuild package
RUN npm install -g esbuild

# Prune extraneous dependencies
RUN rm -rf /root/.npm/_logs/* && npm cache clean --force

# Set working directory for users to execute commands
WORKDIR /app/bls-bn254-js

# Make the script executable
RUN chmod +x /app/bls-bn254-js/scripts/keep-alive.sh

# Run the keep-running script to keep the container alive
CMD ["/app/bls-bn254-js/scripts/keep-alive.sh"]
