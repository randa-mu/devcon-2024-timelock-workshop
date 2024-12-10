// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployer} from "../../src/deployer/Deployer.sol";

contract DeployerTest is Test {
    Deployer internal deployer;
    Counter internal counter;

    function setUp() public {
        deployer = new Deployer();
        counter = new Counter();
    }

    function testDeterministicDeploy() public {
        vm.deal(address(0x1), 100 ether);

        vm.startPrank(address(0x1));
        bytes32 salt = "12345";
        bytes memory creationCode = abi.encodePacked(type(Counter).creationCode);

        address computedAddress = deployer.computeAddress(salt, keccak256(creationCode));
        address deployedAddress = deployer.deploy(salt, creationCode);
        vm.stopPrank();

        assertEq(computedAddress, deployedAddress);
    }
}

contract Counter {
    uint256 public count = 0;

    function increment() external {
        count++;
    }
}
