# Hose

Hose is a token faucet for the `furnace` testnet.

## Quickstart

To run locally, you can run `yarn start`

To build the output javascript which is found at `./index.js`, run `yarn build`.

## API endpoints

| URL                                               | Expected Response | Description                                    |
|---------------------------------------------------|-------------------|------------------------------------------------|
| GET /health                                       | 200               | Used for healthchecking when the service is up |
| POST /gimme?address=0xsomeETHAddressInHexEncoding | 204               | Sends ether to the provided ETH address        |

## Environment

Hose supports the following env vars:

| Name                       | Description                                                                          | Default                                                          | 
|----------------------------|--------------------------------------------------------------------------------------|------------------------------------------------------------------|
| HOSE_RPC_URL               | the `furnace` endpoint to connect to. Supports both http and websockets              | http://localhost:8545                                            |
| HOSE_PRIVATE_KEY           | the private key of the wallet that will be paying out tokens                         | 640956938a00da1be5f1335d0e3a6dba6f57d832b10fd6b0278b980c43087662 |
| HOSE_PORT                  | the HTTP port to listen on.                                                          | 8082                                                             |
| HOSE_TOKENS_PER_REQUEST    | the number of tokens received per faucet request.                                    | 20                                                               |
| HOSE_REQUESTS_PER_DAY      | the max number of requests per IP or address per day.                                | 24                                                               |
| HOSE_MINIMUM_CONFIRMATIONS | the number of blockchain confirmations to wait for before considering a tx verified. | 1                                                                |


