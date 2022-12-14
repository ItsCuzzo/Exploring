// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../interfaces/ICity.sol";
import "../City.sol";

contract CityTest is Test {
    City public city;

    address public constant ALICE = address(0xbabe);

    /// @dev This is a bytes32 value whereby each of the 25 movement related
    /// bytes, reading from left-to-right, represent a move set (4 moves) that
    /// returns the player to their original starting position. Put simply, each
    /// series of 4 moves that are parsed will move the player in a square.
    ///
    /// `0xE1` represents `11100001` in binary. Parsed to moves however, this is
    /// equivalent to UP (11), LEFT (10), DOWN (00) and RIGHT (01) respectively.
    bytes32 public moves = 0xE1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E100000000000000;

    function setUp() public {
        city = new City();
    }

    function testExplore() public {
        startHoax(ALICE, ALICE);
        
        city.explore(moves);
        
        (
            uint128 lastExplore,
            uint64 cansFound,
            uint64 nonce
        ) = city.players(ALICE);

        assertEq(lastExplore, block.timestamp);
        assertEq(cansFound, 180);
        assertEq(nonce, 1);
    }

    function testCannotExploreIfExhausted() public {
        startHoax(ALICE, ALICE);

        city.explore(moves);
        vm.expectRevert(ICity.Exhausted.selector);
        city.explore(moves);
    }

    function testCannotExploreOutOfBounds(address player) public {
        startHoax(player, player);

        bytes32 oobUp = bytes32(0);
        vm.expectRevert(ICity.OutOfBounds.selector);
        city.explore(oobUp);

        bytes32 oobDown = bytes32(type(uint256).max);
        vm.expectRevert(ICity.OutOfBounds.selector);
        city.explore(oobUp);
    }

}
