// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "./UniV3OracleLib.sol";
import "../interfaces/IBondingCurve.sol";

library UniV3Oracle {

    function consultPriceAtTick(IBondingCurve.PriceConsultancyParams memory _params)
        internal
        view
        returns (uint256 twap)
    {
        (int24 timeWeightedAverageTick, ) = UniV3OracleLib.consult(
            _params.pool,
            _params.period
        );

        twap = UniV3OracleLib.getQuoteAtTick(
            timeWeightedAverageTick,
            _params.baseAmount,
            _params.baseToken,
            _params.quoteToken
        );
    }
}
