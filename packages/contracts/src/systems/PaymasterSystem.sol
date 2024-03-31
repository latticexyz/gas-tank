// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { System } from "@latticexyz/world/src/System.sol";
import { Balances } from "@latticexyz/world/src/codegen/index.sol";
import { ROOT_NAMESPACE_ID } from "@latticexyz/world/src/constants.sol";
import { IPaymaster, PostOpMode } from "../eip4337/IPaymaster.sol";
import { PackedUserOperation } from "../eip4337/PackedUserOperation.sol";
import { IEntryPoint } from "../eip4337/IEntryPoint.sol";
import { _packValidationData } from "../eip4337/Helpers.sol";
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
      // TODO
      return ("", _packValidationData(false, 0, 0));
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
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
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal virtual {
        (mode, context, actualGasCost); // unused params
        revert("not implemented");
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
        Balances.set(ROOT_NAMESPACE_ID, Balances.get(ROOT_NAMESPACE_ID) - _msgValue());
        IEntryPoint(EntryPoint.get()).depositTo{value: _msgValue()}(address(this));
    }
}
