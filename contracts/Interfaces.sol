pragma solidity ^0.8.20;

import "./IVault.sol";

interface IRouter {
    function addPlugin(address _plugin) external;
    function pluginTransfer(address _token, address _account, address _receiver, uint256 _amount) external;
    function pluginIncreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external;
    function pluginDecreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external returns (uint256);
    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external;
}

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}
interface IReader{
    function getAmountOut(IVault _vault, address _tokenIn, address _tokenOut, uint256 _amountIn) external returns (uint256, uint256);
}

pragma experimental ABIEncoderV2;

/**
 * @dev Provides a way to perform queries on swaps, joins and exits, simulating these operations and returning the exact
 * result they would have if called on the Vault given the current state. Note that the results will be affected by
 * other transactions interacting with the Pools involved.
 *
 * All query functions can be called both on-chain and off-chain.
 *
 * If calling them from a contract, note that all query functions are not `view`. Despite this, these functions produce
 * no net state change, and for all intents and purposes can be thought of as if they were indeed `view`. However,
 * calling them via STATICCALL will fail.
 *
 * If calling them from an off-chain client, make sure to use eth_call: most clients default to eth_sendTransaction for
 * non-view functions.
 *
 * In all cases, the `fromInternalBalance` and `toInternalBalance` fields are entirely ignored: we just use the same
 * structs for simplicity.
 */
interface IBalancerQueries {
    function querySwap(ISwapper.SingleSwap memory singleSwap, ISwapper.FundManagement memory funds)
        external
        returns (uint256);

    function queryBatchSwap(
        ISwapper.SwapKind kind,
        ISwapper.BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        ISwapper.FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);

}


interface ISwapper{
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    IAsset assetIn;
    IAsset assetOut;
    uint256 amount;
    bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline) external returns (uint256 amountCalculated);

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }
    function batchSwap(SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline) external returns (int256[] memory assetDeltas);
    
    function queryBatchSwap(SwapKind kind,
          BatchSwapStep[] memory swaps,
          IAsset[] memory assets,
          FundManagement memory funds) external
          returns (int256[] memory assetDeltas);
    
}