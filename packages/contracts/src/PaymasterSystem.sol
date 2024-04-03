// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { IPaymaster } from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { _packValidationData } from "@account-abstraction/contracts/core/Helpers.sol";
import { UserOperationLib } from "@account-abstraction/contracts/core/UserOperationLib.sol";

import { System } from "@latticexyz/world/src/System.sol";
import { Balances as WorldBalances } from "@latticexyz/world/src/codegen/index.sol";
import { ROOT_NAMESPACE_ID } from "@latticexyz/world/src/constants.sol";
import { EntryPoint } from "./codegen/tables/EntryPoint.sol";
import { UserBalances } from "./codegen/tables/UserBalances.sol";
import { Spender } from "./codegen/tables/Spender.sol";
import { IAllowance } from "./IAllowance.sol";

uint256 constant POST_OP_OVERHEAD = 0;

contract PaymasterSystem is System, IPaymaster, IAllowance {
  using UserOperationLib for PackedUserOperation;

  /// @inheritdoc IPaymaster
  function validatePaymasterUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 maxCost
  ) external override returns (bytes memory context, uint256 validationData) {
    _requireFromEntryPoint();
    return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
  }

  /**
   * Validate a user operation.
   * @param userOp     - The user operation.
   * @param userOpHash - The hash of the user operation.
   * @param maxCost    - The maximum cost of the user operation.
   */
  function _validatePaymasterUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 maxCost
  ) internal virtual returns (bytes memory context, uint256 validationData) {
    (userOpHash); // unused parameter

    // Require the sender to be a registered spender of a user account
    address userAccount = Spender.getUserAccount(userOp.getSender());
    if (userAccount == address(0)) {
      revert("Account is not registered as spender for any user");
    }

    // Require the user account to have sufficient balance
    uint256 balance = UserBalances.get(userAccount);
    if (maxCost > balance) {
      revert("Insufficient user balance");
    }

    // Deduct cost from the user's balance
    UserBalances.set(userAccount, balance - maxCost);

    // Pass the user account and deducted balance in the context
    context = abi.encode(userAccount, maxCost);
    validationData = _packValidationData(false, 0, 0);
  }

  /// @inheritdoc IPaymaster
  function postOp(
    IPaymaster.PostOpMode mode,
    bytes calldata context,
    uint256 actualGasCost,
    uint256 actualUserOpFeePerGas
  ) external override {
    _requireFromEntryPoint();
    _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
  }

  /**
   * Post-operation handler.
   * (verified to be called only through the entryPoint)
   * @dev If subclass returns a non-empty context from validatePaymasterUserOp,
   *      it must also implement this method.
   * @param mode          - Enum with the following options:
   *                        opSucceeded - User operation succeeded.
   *                        opReverted  - User op reverted. still has to pay for gas.
   *                        postOpReverted - User op succeeded, but caused postOp (in mode=opSucceeded) to revert.
   *                                         Now this is the 2nd call, after user's op was deliberately reverted.
   * @param context       - The context value returned by validatePaymasterUserOp
   * @param actualGasCost - Actual gas used so far (without this postOp call).
   */
  function _postOp(
    IPaymaster.PostOpMode mode,
    bytes calldata context,
    uint256 actualGasCost,
    uint256 actualUserOpFeePerGas
  ) internal virtual {
    (mode); // unused parameter
    (address user, uint256 maxCost) = abi.decode(context, (address, uint256));

    uint256 refund = maxCost - actualUserOpFeePerGas * (actualGasCost + POST_OP_OVERHEAD);

    // Refund unused cost to user
    UserBalances.set(user, UserBalances.get(user) + refund);
  }

  function getAllowance(address spender) public view returns (uint256) {
    return UserBalances.get(Spender.getUserAccount(spender));
  }

  function getBalance(address user) public view returns (uint256) {
    return UserBalances.get(user);
  }

  function depositTo(address account) public payable {
    UserBalances.set(account, UserBalances.get(account) + _msgValue());
    _depositToEntryPoint(_msgValue());
  }

  function registerSpender(address spender) public {
    require(Spender.getUserAccount(spender) == address(0), "Spender already registered");
    Spender.setUserAccount(spender, _msgSender());
  }

  function unregisterSpender(address spender) public {
    require(Spender.getUserAccount(spender) == _msgSender(), "Spender registered for another user");
    Spender.deleteRecord(spender);
  }

  /**
   * Validate the call is made from a valid entrypoint
   */
  function _requireFromEntryPoint() internal virtual {
    require(_msgSender() == EntryPoint.get(), "Sender not EntryPoint");
  }

  function _depositToEntryPoint(uint256 amount) internal {
    WorldBalances.set(ROOT_NAMESPACE_ID, WorldBalances.get(ROOT_NAMESPACE_ID) - amount);
    IEntryPoint(EntryPoint.get()).depositTo{ value: amount }(address(this));
  }
}