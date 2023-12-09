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