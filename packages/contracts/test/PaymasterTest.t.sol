// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/core/EntryPointSimulations.sol";
import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { MudTest } from "@latticexyz/world/test/MudTest.t.sol";
import { NamespaceOwner } from "@latticexyz/world/src/codegen/tables/NamespaceOwner.sol";
import { ROOT_NAMESPACE_ID } from "@latticexyz/world/src/constants.sol";
import { IWorld } from "../src/codegen/world/IWorld.sol";
import { EntryPoint as EntryPointTable } from "../src/codegen/tables/EntryPoint.sol";

import { TestCounter } from "./utils/TestCounter.sol";
import { BytesLib } from "./utils/BytesLib.sol";

using ECDSA for bytes32;

contract PaymasterTest is MudTest {
  EntryPoint entryPoint;
  EntryPointSimulations entryPointSimulations;
  SimpleAccountFactory accountFactory;
  IWorld paymaster;
  TestCounter counter;

  address payable beneficiary;
  address paymasterOperator;
  address user;
  uint256 userKey;
  address guarantor;
  uint256 guarantorKey;
  SimpleAccount account;

  function setUp() public override {
    super.setUp();

    beneficiary = payable(makeAddr("beneficiary"));
    paymasterOperator = makeAddr("paymasterOperator");
    (user, userKey) = makeAddrAndKey("user");
    (guarantor, guarantorKey) = makeAddrAndKey("guarantor");
    entryPoint = new EntryPoint();
    entryPointSimulations = new EntryPointSimulations();
    accountFactory = new SimpleAccountFactory(entryPoint);
    paymaster = IWorld(worldAddress);
    account = accountFactory.createAccount(user, 0);
    counter = new TestCounter();

    vm.prank(NamespaceOwner.get(ROOT_NAMESPACE_ID));
    EntryPointTable.set(address(entryPoint));
  }

  function testDepositTo() external {
    vm.deal(address(this), 1 ether);
    paymaster.depositTo{ value: 1 ether }(user);
    assertEq(paymaster.getBalance(user), 1 ether);

    vm.prank(user);
    paymaster.registerSpender(address(account));
    assertEq(paymaster.getAllowance(address(account)), 1 ether);
  }

  // sanity check for everything works without paymaster
  function testCall() external {
    vm.deal(address(account), 1 ether);
    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeCall(TestCounter.count, ())
    );
    op.signature = signUserOp(op, userKey);
    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = op;
    entryPoint.handleOps(ops, beneficiary);

    // TODO: test the counter is increased and sender is correct
  }

  function testPaymaster() external {
    vm.deal(address(this), 1 ether);
    paymaster.depositTo{ value: 1 ether }(user);

    vm.prank(user);
    paymaster.registerSpender(address(account));

    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeCall(TestCounter.count, ())
    );
    op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
    op.signature = signUserOp(op, userKey);
    submitUserOp(op);

    // TODO: test the counter is increased and sender is correct
  }

  function testRefund() external {
    uint256 startBalance = 1 ether;
    vm.deal(address(this), startBalance);
    paymaster.depositTo{ value: startBalance }(user);

    assertEq(paymaster.getBalance(user), startBalance);

    vm.prank(user);
    paymaster.registerSpender(address(account));

    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeCall(TestCounter.count, ())
    );
    op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
    op.signature = signUserOp(op, userKey);
    uint256 gasUsed = submitUserOp(op);
    uint256 realFeePerGas = getUserOpGasPrice(op);
    uint256 realCost = gasUsed * realFeePerGas;
    uint256 estimatedCost = startBalance - paymaster.getBalance(user);
    int256 diffCost = int256(estimatedCost) - int256(realCost);
    int256 diffGas = diffCost / int256(realFeePerGas);

    // Assert the estimated cost is always greater than the real cost
    assertGt(diffCost, 0);
    // Assert the difference is less than 500 gas units
    assertLt(diffGas, 500);

    console.log("real cost:", realCost);
    console.log("estimated cost:", estimatedCost);
    console.log("diff cost:");
    console.logInt(diffCost);
    console.log("diff gas:");
    console.logInt(diffGas);
  }

  function testRefundFuzz(uint256 repeat, string calldata junk) external {
    uint256 startBalance = 1 ether;
    vm.deal(address(this), startBalance);
    paymaster.depositTo{ value: startBalance }(user);

    assertEq(paymaster.getBalance(user), startBalance);

    vm.prank(user);
    paymaster.registerSpender(address(account));

    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeCall(TestCounter.gasWaster, (repeat, junk))
    );
    op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
    op.signature = signUserOp(op, userKey);
    uint256 gasUsed = submitUserOp(op);

    uint256 realFeePerGas = getUserOpGasPrice(op);
    uint256 realCost = gasUsed * realFeePerGas;
    uint256 estimatedCost = startBalance - paymaster.getBalance(user);
    int256 diffCost = int256(estimatedCost) - int256(realCost);
    int256 diffGas = diffCost / int256(realFeePerGas);

    // Assert the estimated cost is always greater than the real cost
    assertGt(diffCost, 0);
    // Assert the difference is less than 500 gas units
    assertLt(diffGas, 500);

    console.log("real cost:", realCost);
    console.log("estimated cost:", estimatedCost);
    console.log("diff cost:");
    console.logInt(diffCost);
    console.log("diff gas:");
    console.logInt(diffGas);
  }

  function fillUserOp(
    SimpleAccount _sender,
    uint256 _key,
    address _to,
    uint256 _value,
    bytes memory _data
  ) public view returns (PackedUserOperation memory op) {
    op.sender = address(_sender);
    op.nonce = entryPoint.getNonce(address(_sender), 0);
    op.callData = abi.encodeCall(SimpleAccount.execute, (_to, _value, _data));
    op.accountGasLimits = bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(50000))));
    op.preVerificationGas = 50000;
    op.gasFees = bytes32(abi.encodePacked(bytes16(uint128(100)), bytes16(uint128(1000000000))));
    op.signature = signUserOp(op, _key);
    return op;
  }

  function signUserOp(PackedUserOperation memory op, uint256 _key) public view returns (bytes memory signature) {
    bytes32 hash = entryPoint.getUserOpHash(op);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, MessageHashUtils.toEthSignedMessageHash(hash));
    signature = abi.encodePacked(r, s, v);
  }

  function submitUserOp(PackedUserOperation memory op) public returns (uint256 gasUsed) {
    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = op;
    gasUsed = gasleft();
    entryPoint.handleOps(ops, beneficiary);
    gasUsed -= gasleft();
  }

  function getUserOpGasPrice(PackedUserOperation memory op) internal view returns (uint256) {
    uint256 maxFeePerGas = uint256(uint128(uint256(op.gasFees)));
    uint256 maxPriorityFeePerGas = uint128(bytes16(op.gasFees));
    if (maxFeePerGas == maxPriorityFeePerGas) {
      // legacy mode (for networks that don't support basefee opcode)
      return maxFeePerGas;
    }
    return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
  }
}
