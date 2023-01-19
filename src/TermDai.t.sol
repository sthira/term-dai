// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./TermDai.sol";

contract TermDaiTest is DSTest {
    TermDai dai;

    function setUp() public {
        dai = new TermDai();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
