// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/* Autogenerated file. Do not edit manually. */

import { PackedUserOperation } from "./../../eip4337/PackedUserOperation.sol";
import { PostOpMode } from "./../../eip4337/IPaymaster.sol";

/**
 * @title IPaymasterSystem
 * @author MUD (https://mud.dev) by Lattice (https://lattice.xyz)
 * @dev This interface is automatically generated from the corresponding system contract. Do not edit manually.
 */
interface IPaymasterSystem {
  function validatePaymasterUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 maxCost
  ) external returns (bytes memory context, uint256 validationData);

  function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) external;

  function deposit() external payable;
}
