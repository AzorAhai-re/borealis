// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

contract UniswapV3Pool {

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    function slot0() public pure returns(Slot0 memory _slot0) {
        _slot0 = Slot0({
            sqrtPriceX96: 1473278467459847576161095040421829,
            tick: 196623,
            observationIndex: 548,
            observationCardinality: 720,
            observationCardinalityNext: 720,
            feeProtocol: 0,
            unlocked: true
        });
    }
}