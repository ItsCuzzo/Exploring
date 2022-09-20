// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./interfaces/ICity.sol";

/// @title Inspired by the Hobo Wars daily event of city exploration.
/// @author ItsCuzzo
/// @dev Source: https://wiki.hobowars.com/index.php?title=Exploring
/// Remember that this implementation is heavily unoptimised for the
/// purpose of the article, stay tuned for Part III where things get
/// extra saucy.

contract City is ICity {

    /// @dev Struct that contains player statistics.
    /// lastExplore: The timestamp of the last invoke of `explore`.
    /// cansFound: Total number of cans found.
    /// nonce: Used to roll starting position of the player.
    struct Stats {
        uint128 lastExplore;
        uint64 cansFound;
        uint64 nonce;
    }

    /// @dev Used to denote the number of movement related bytes.
    /// Recall that 25 of 32 bytes are required to denote 100
    /// moves. 2 bits per move * 100 moves = 200 bits = 25 bytes.
    uint256 public constant MOVEMENT_BYTES = 25;

    /// @dev Total number of tiles within the map, inclusive of the
    /// 0 value. A value of `2499` represents a 50 x 50 grid.
    /// The value of `mapSize` SHOULD always be a perfect square root
    /// number in order to keep the representation of a grid consistent.
    uint256 public mapSize = 2499;

    /// @dev Maximum number of cans that can be found at a single tile.
    uint256 public maxCans = 7;

    /// @dev Probability out of 99 that an explorer will find an amount
    /// of cans upon movement to a new tile. This value is inclusive of the
    /// 0 value. Loot will be found if: 0 <= roll < lootChance.
    /// E.g. A roll of 49 at `lootChance` 50 indicates cans have been found.
    uint256 public lootChance = 50;

    /// @dev Cooldown timer until `explore` is callable again by a particular
    /// caller.
    uint256 public cooldown = 7 days;

    /// @dev Mapping of `address` to `Stats` struct which contains lifetime
    /// stats of the player.
    mapping(address => Stats) public players;

    /// @notice Function used to explore the city and find some precious cans!
    /// @param moves Some binary string in hexadecimal format that represents
    /// the desired move set.
    /// @dev 192741 Gas Consumed w/ no optimisor.
    function explore(bytes32 moves) external {

        /// We use an `unchecked` block here because we want to allow underflow
        /// errors. If we don't use an `unchecked` block, the variable used to track
        /// a players current position reverts in an 'unclean' manner.
        ///
        /// In addition to this, using `unchecked` blocks are a basic form of
        /// gas optimisation but should be used with great care!
        unchecked {            
            
            /// Access the respective `Stats` struct for `msg.sender`.
            Stats storage stats = players[msg.sender];

            /// Determine if the caller is on cooldown.
            if (block.timestamp - stats.lastExplore < cooldown) revert Exhausted();

            /// Calculate a 'random' value which will be used to determine our starting position.
            /// It's worth mentioning that additional parameters can be added here to seemingly
            /// increase randomness, but ultimately, pretty much every source of on-chain
            /// randomness is deterministic by nature with a little bit of technical know how.
            uint256 gameState = uint256(keccak256(abi.encodePacked(
                msg.sender, stats.nonce
            )));

            /// Determine the starting position of the explore run using the previously
            /// defined `gameState` variable modulo `mapSize`.
            uint256 position = gameState % mapSize + 1;

            /// Define a variable to cache the move set for a particular byte, we reuse
            /// this variable upon each iteration of the outer loop below to save a widdle
            /// bit of gas. The value of `moveSet` will always equal the full 4 move series.
            uint8 moveSet;

            /// Define a variable to cache a single move for a given `moveSet`. We reuse
            /// this variable upon each iteration of the inner loop below to save a widdle
            /// bit of gas. The value of `move` will always be a single move of `moveSet`.
            uint8 move;

            /// Define a variable to keep track of the number of cans found within this
            /// particular invocation of `explore`.
            uint256 cansFound;

            /// Iterate through each byte in `moves` reading from left-to-right. We only iterate
            /// over 25 of the 32 bytes as this is the total number of bytes that represent
            /// 100 moves. This loop will read `moves[0]` -> `moves[24]`.
            for (uint256 i = 0; i < MOVEMENT_BYTES; i++) {
                
                /// Assign byte `moves[i]` to `moveSet`. `moveSet` now holds a value which
                /// represents 4 different moves. Since each byte in `moves` is 0xE1 (225), this
                /// represents: 11 10 00 01 or UP LEFT DOWN RIGHT.
                moveSet = uint8(moves[i]);

                /// Iterate through each move in `moveSet`. The value of `j` will be used
                /// to represent the shift value used to 'clean' the relevant upper bits
                /// of `moveSet`.
                for (uint256 j = 0; j < 8; j += 2) {

                    /// Parse out the respective move. YES, this is an unoptimal way of
                    /// parsing out a move, but remember, this is meant to be a naive
                    /// Solidity implementation. We will gas optimise and do some cool
                    /// tricks later ;)
                    ///
                    /// E.g. At `j` = 0, `moveSet` = 11 10 00 01 (225).
                    /// (`moveSet` << `j`) >> 6 = 00 00 00 11 (3).
                    /// (225 << 0) >> 6 = 3
                    move = (moveSet << uint8(j)) >> 6;

                    /// Update the players current `position` value. The reasoning for
                    /// either incrementing or decrementing by 50 is that remember our
                    /// `mapSize` is 2500 tiles (inclusive of 0). This number perfectly
                    /// represents a 50 x 50 grid. If we move up (3), then we have decreased
                    /// our position by 50 tiles. If we move down (0), we have increased
                    /// our position by 50 tiles.
                    if (move == 3) position -= 50;
                    else if (move == 2) position--;
                    else if (move == 1) position++;
                    else position += 50;

                    /// Determine if the player has ventured out of bounds. As mentioned
                    /// in the article, we can only achieve an out of bounds `position`
                    /// at the lower and upper bounds of `mapSize`.
                    ///
                    /// Reducing our position below 0 indicates that we have travelled
                    /// beyond the city limits. Increasing our position above `mapSize`
                    /// is indicative of the same outcome also.
                    if (position > mapSize) revert OutOfBounds();

                    /// Calculate an event ID to determine if we have found any cans at upon
                    /// venturing to this tile. We include the values of `i` and `j` for
                    /// additional 'randomness' in our seeding.
                    uint256 eventId = uint256(keccak256(abi.encodePacked(block.timestamp, position, i, j)));

                    /// Determine if the player has found any cans! We modulo `eventId` by 100
                    /// to get our resulting loot chance. Since we modulo by 100, the value
                    /// of our roll is in the bounds of: 0 <= roll < 100. If the player has
                    /// rolled a number lower than `lootChance`, we have found cans!
                    if (eventId % 100 < lootChance) {

                        /// Determine the number of cans found by the player. We reuse `eventId`
                        /// to avoid excessive gas consumption and determine the total found by
                        /// `eventId` % `maxCans` + 1. The reasoning for incrementing the outcome
                        /// by 1 is that it is possible for the modulo result to return a value
                        /// of 0. However, since loot is found, we want to reward the player regardless.
                        cansFound += eventId % maxCans + 1;
                    }

                }
            }

            /// After all is said and done, update the `Stats` struct with the
            /// relevant information.
            stats.lastExplore = uint128(block.timestamp);
            stats.cansFound += uint64(cansFound);
            stats.nonce++;
        }

    }

}
