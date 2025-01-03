# 🏦 DeFi Safety Workshop on Timelock Encryption 🛡️

Welcome to the **DeFi Safety Workshop on Timelock Encryption**! This repository contains all the resources, code, and materials needed for a hands-on developer workshop focused on improving security in decentralized finance (DeFi) using timelock encryption. [Timelock](https://randa.mu/features/timelock-encryption-on-chain) encryption enables data to be encrypted and decrypted only after a specified time period or condition is met. This approach is valuable for delaying access to sensitive information, securing transactions, and mitigating front-running attacks.

## 📋 Table of Contents
1. [About the Workshop](#about-the-workshop)
2. [Prerequisites](#prerequisites)
3. [Setup Instructions](#setup-instructions)
4. [Workshop Agenda](#workshop-agenda)
5. [Learning Objectives](#learning-objectives)
6. [Resources](#resources)
7. [Contributing](#contributing)
8. [License](#license)

## About the Workshop

In this workshop, we explore how the security of smart contracts and DeFi applications can be enhanced using **timelock encryption**.

Participants will:
- Learn the fundamentals of timelock encryption and its applications in DeFi. It is worth mentioning that this differs from [Timelock smart contracts](https://www.lcx.com/introduction-to-timelock-smart-contracts/), also known as time-based or delayed contracts, which are a specialized type of smart contract that introduces a delay or time-based constraint on the execution of certain actions or transactions.
- Understand the potential vulnerabilities that timelock encryption addresses to enhance the security of DeFi protocols.
- Implement a simple smart contract that incorporates timelock functionalities.

## Workshop Agenda

1. **Introduction to Timelock Encryption**
    - An introduction to timelock encryption:
        - What is it?
        - Features
        - Use cases
2. **Enhancing Security in DeFi with Timelock Encryption**
    - Overview of use cases in DeFi (e.g., securing auctions, sealed bids, delayed transactions, securing governance actions relating to lending parameters, securing staking reward distribution information, among others).
3. **Hands-On Exercise: Simple Auction Smart Contract with Sealed Bids Secured by Timelock Encryption**
4. **Q&A and Wrap-Up**

## Learning Objectives

By the end of the workshop, participants will be able to:
- Understand the principles and benefits of timelock encryption in DeFi.
- Implement and deploy Solidity smart contracts with timelock functionality.


## Prerequisites

Before getting started, ensure you have the following tools installed:

1. **Docker**: Make sure Docker is installed on your system. You can download Docker from [Docker's official website](https://www.docker.com/get-started).
   
2. **Docker Compose**: Docker Compose is usually included with Docker Desktop installations. To verify its installation, run the following command:
   ```bash
   docker compose version
   ```

## Setup Instructions

Follow these steps to set up your local environment for the workshop:

1. **Clone the Repository**
    ```bash
    git clone https://github.com/randa-mu/devcon-2024-timelock-workshop.git
    cd devcon-2024-timelock-workshop
    ```

2. **Start Services Using Docker Compose**: The `docker-compose.yml` file defines all the services that are required to run the project. To start these services in detached mode (background), run the following command:
    ```bash
    docker compose up -d
    ```

    Docker Compose will automatically:
        - Create all required images.
        - Build the services as needed.
        - Set up networks and containers.

3. **Verify Running Containers
To check that all services are running correctly, use**:
    ```bash
    docker compose ps
    ```

    This will show a list of all containers and their current status. Ensure that each service defined in `docker-compose.yml` is listed and is running.

Once you've verified that all the required services are up and running, please follow the [step-by-step guide](STEP_BY_STEP_GUIDE.md) provided for the hands-on exercise. 


## Resources

Here are some helpful resources for further reading:
- [Timelock Encryption On-Chain](https://randa.mu/features/timelock-encryption-on-chain)
- [Ethereum Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [OpenZeppelin Contracts Library](https://docs.openzeppelin.com/contracts/)

## Contributing

Contributions are welcome! If you have any suggestions or improvements for the workshop, feel free to submit a pull request or open an issue.

1. Fork the repository.
2. Clone your forked repository to your local machine.
3. Create a new branch: `git checkout -b feature/your-feature-name`.
4. Commit your changes: `git commit -m 'Add some feature'`.
5. Push to the branch: `git push origin feature/your-feature-name`.
6. Open a pull request.


## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
