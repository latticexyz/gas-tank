// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { IPaymaster } from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { _packValidationData } from "@account-abstraction/contracts/core/Helpers.sol";

import { System } from "@latticexyz/world/src/System.sol";
import { Balances } from "@latticexyz/world/src/codegen/index.sol";
import { ROOT_NAMESPACE_ID } from "@latticexyz/world/src/constants.sol";
import { EntryPoint } from "../codegen/index.sol";

contract PaymasterSystem is System, IPaymaster {
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
      (userOp, userOpHash, maxCost, context, validationData);
      // Require the sender to be a valid spender of a user account
      // Require the user account balance associated with the app smart account to have sufficient balance
      // Deduct gasPrice * (verificationGasLimit + callGasLimit + paymasterVerificationGasLimit + postOpGasLimit) from the user account balance
      // Pass the deducted balance in context
      return ("", _packValidationData(false, 0, 0));
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
        (mode, context, actualGasCost, actualUserOpFeePerGas); // unused params
        revert("not implemented");
        // Refund decutedBalance - (actualGasCost * actualUserOpFeePerGas + overhead for postOp) to the user account balance
    }

    function depositTo(address account) public payable {
      // Increase balance for this account
      // Deposit the value in the entry point
    }

    function registerSpender(address spender) public {
      // Add a new spender to the spender table
    }

    function unregisterSpender(address spender) public {
      // Remove a spender from the spender table
    }

    /**
     * Validate the call is made from a valid entrypoint
     */
    function _requireFromEntryPoint() internal virtual {
        require(_msgSender() == EntryPoint.get(), "Sender not EntryPoint");
    }

    ///////////////////////////////////////
    // STUFF BELOW HERE JUST FOR DEV

    /**
     * Add a deposit for this paymaster, used for paying for transaction fees.
     */
    function deposit() public payable {
      _depositToEntryPoint(_msgValue());
    }

    function _depositToEntryPoint(uint256 amount) internal {
        Balances.set(ROOT_NAMESPACE_ID, Balances.get(ROOT_NAMESPACE_ID) - amount);
        IEntryPoint(EntryPoint.get()).depositTo{value: amount}(address(this)); 
    }
}
