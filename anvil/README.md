# anvil

This project sets up a private Ethereum testnet using Foundry's [Forge](https://book.getfoundry.sh/forge/) and [Anvil](https://book.getfoundry.sh/anvil/) within a Docker container. 

Anvil is a local testnet node shipped with Foundry. It is used for testing smart contracts from frontends or for interacting over RPC.

The testnet includes a custom mnemonic, a specified number of accounts, and predefined account balances.


## Prerequisites

Install [Docker](https://docs.docker.com/engine/install/) on your system.

## Setup and Configuration

### Dockerfile Overview
The [Dockerfile](Dockerfile) sets up a Docker image with Foundry's Forge and Anvil installed. It includes a custom startup script to initialize the testnet.

### Start Script 
The [start-anvil.sh](start-anvil.sh) script initializes the Anvil Ethereum node with custom settings, including the mnemonic, number of accounts, and account balance.

### Building and Running the Docker Container
Build the Docker Image:

Navigate to the directory containing the Dockerfile and start-anvil.sh, then run:
```shell
docker build -t foundry-anvil-testnet .
```

Run the Docker Container:
```sh
docker run -p 8545:8545 foundry-anvil-testnet
```

This command exposes the Ethereum RPC on port 8545.

### Customization

`Mnemonic`: We can change the MNEMONIC variable in the `start-anvil.sh` script to use a different mnemonic phrase.

`Number of Accounts`: Adjust the `NUM_ACCOUNTS` variable in the `start-anvil.sh` script to create a different number of accounts.

`Account Balances`: Modify the `ACCOUNT_BALANCE` variable in the `start-anvil.sh` script to set different initial balances for the accounts.


To connect to the testnet, use the following `RPC URL` in your Ethereum client or dApp:
```shell
http://<container host ip>:8545
```