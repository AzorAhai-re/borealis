// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

contract UniswapV3Pool {
    function token1() public pure returns(address){
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function token0() public pure returns(address){
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        pure
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        secondsAgos; // just to surpress compiler warning

        int56[] memory _tickCumulatives = new int56[](2);
        _tickCumulatives[0] = 7822720026373;
        _tickCumulatives[1] = 7823446812459;
        tickCumulatives = _tickCumulatives;

       uint160[] memory _secondsPerLiquidityCumulativeX128s = new uint160[](2);
       _secondsPerLiquidityCumulativeX128s[0] = 198044337547992690118316800002740227814977;
       _secondsPerLiquidityCumulativeX128s[1] = 198044337547992690217121261946121024560557;
       secondsPerLiquidityCumulativeX128s = _secondsPerLiquidityCumulativeX128s;
    }
}
