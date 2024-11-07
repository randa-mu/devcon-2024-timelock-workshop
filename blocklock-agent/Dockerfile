#### BASE STAGE
#### Installs Node.js, Foundry, and Moon on Ubuntu.

# Use Ubuntu as the base image
FROM ubuntu:22.04 AS base

# Set ARG for Node.js version
ARG NODE_VERSION=22

# Install required dependencies and Node.js
RUN apt-get update && \
    apt-get install -y curl ca-certificates gnupg git && \
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

# Install Moon binary
RUN curl -fsSL https://moonrepo.dev/install/moon.sh | bash
ENV PATH="/root/.moon/bin:$PATH"

#### SKELETON STAGE
#### Scaffolds repository skeleton structures.

FROM base AS skeleton

# Copy the entire repository and scaffold
COPY . .
RUN moon docker scaffold blocklock-agent

#### BUILD STAGE
#### Builds the project.

FROM base AS build

# Copy toolchain from skeleton
COPY --from=skeleton /root/.proto /root/.proto

# Copy workspace configs
COPY --from=skeleton /app/.moon/docker/workspace .

# Install project dependencies
RUN moon docker setup

# Copy project sources from skeleton
COPY --from=skeleton /app/.moon/docker/sources .

# Build the project
RUN moon run blocklock-agent:build

# Prune extraneous dependencies
RUN rm -rf /root/.npm/_logs/* && npm cache clean --force

#### START STAGE
#### Runs the project.

FROM base AS start

# Copy the built project to the start stage
COPY --from=build /app/blocklock-agent/index.cjs /app/index.cjs

# Define the command to run the application
CMD ["node", "/app/index.cjs"]
