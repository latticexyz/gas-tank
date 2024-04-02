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

import { TestCounter} from "./utils/TestCounter.sol";
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
    vm.deal(address(account), 1e18);
    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeWithSelector(TestCounter.count.selector)
    );
    op.signature = signUserOp(op, userKey);
    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = op;
    entryPoint.handleOps(ops, beneficiary);

    // TODO: test the counter is increased and sender is correct
  }

  function testPaymaster() external {
    vm.deal(address(account), 1e18);
    PackedUserOperation memory op = fillUserOp(
      account,
      userKey,
      address(counter),
      0,
      abi.encodeWithSelector(TestCounter.count.selector)
    );
    op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
    op.signature = signUserOp(op, userKey);
    submitUserOp(op);

    // TODO: test the counter is increased and sender is correct
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
    op.callData = abi.encodeWithSelector(SimpleAccount.execute.selector, _to, _value, _data);
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

  function submitUserOp(PackedUserOperation memory op) public {
    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = op;
    entryPoint.handleOps(ops, beneficiary);
  }
}
