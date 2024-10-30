ARG ARCH=linux/amd64
FROM --platform=${ARCH} ghcr.io/foundry-rs/foundry

# These commands are used to make sure Foundry is installed
RUN forge --version
RUN anvil --version

# Create a working directory
WORKDIR /app

# Copy the start script into the container
COPY start-anvil.sh /app/start-anvil.sh

# Make the script executable
RUN chmod +x /app/start-anvil.sh

# Expose port 8545 for the Ethereum RPC
EXPOSE 8545

# Run the custom start script
CMD ["/app/start-anvil.sh"]
