pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./Interfaces.sol";

contract debtManager is Ownable(0xb17f6e542373E5662a37E8c354377Be2eecfBA82){

    struct position{
        uint256 usdcBalance;
        uint256 wstethBalance;
    }

    struct thresholds{
        uint256 reinvestment;
        uint256 health;
    }

    address public immutable WSTETH_SOURCE;
    uint256 public HFWEI;
    address public AAVEPOOL;
    address public AGENT;
    address public immutable WSTETH;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public UNDERLYINGBAL;
    address public constant RPDW =0x6b02fEFd2F2e06f51E17b7d5b8B20D75fd6916be;
    bytes32 public constant dolaPoolBytesId = 0x8bc65eed474d1a00555825c91feab6a8255c2107000000000000000000000453;
    address public DOLA;
    address public dolaPoolToken;
    address public poolREwardPool;
    address public immutable balancerQuery;
    mapping(address=>position) public userBalances;
    mapping(address=>uint256) public userThresholds;
    uint256 public UPPERHFWEI;
    address[] public users;
    

    constructor (address wsteth_source, address ub, address aavepool, address wsteth, address dola, uint256 hf, address prp, address dpt, uint256 uhf, address agent, address bq){
        WSTETH = wsteth;
        UNDERLYINGBAL = ub;
        AGENT = agent;
        balancerQuery = bq;
        WSTETH_SOURCE = wsteth_source;
        AAVEPOOL = aavepool;
        dolaPoolToken = dpt;
        poolREwardPool = prp;
        DOLA = dola;
        HFWEI = hf;
        UPPERHFWEI = uhf;
    }


    function initialise(uint256 reinvestment) public {
        uint256 wstethBalance = IAcquirer(WSTETH_SOURCE).balanceGetter(msg.sender, WSTETH);
        uint256 myPermission = IERC20(WSTETH).allowance(WSTETH_SOURCE, address(this));
        uint256 toTransfer = myPermission>wstethBalance ? wstethBalance : myPermission;
        require (toTransfer > 0, "You are broke");
        userThresholds[msg.sender] = reinvestment;
        //transfer all the money and credit them to the original owner
        IERC20(WSTETH).transferFrom(WSTETH_SOURCE, address(this), toTransfer);
        userBalances[msg.sender].wstethBalance += toTransfer; //userbalances are superflouos; wsteth balances in job1 will play the role of shares
        //approve uint256 max to aave
        IERC20(WSTETH).approve(AAVEPOOL, type(uint256).max);
        //supply wsteth to the aave pool
        IPool(AAVEPOOL).supply(WSTETH, IERC20(WSTETH).balanceOf(address(this)), address(this), 0);
        //compute how much we can borrow
        (uint256 collateral, uint256 debt, uint256 available,,,uint256 healthfactor) = IPool(AAVEPOOL).getUserAccountData(address(this));
        //we can borrow min(available, collateral/hf-debt)
        uint256 expected = (collateral*1e18)/HFWEI - debt;
        uint256 toBorrow = expected>available ? available : expected;
        IPool(AAVEPOOL).borrow(USDC, toBorrow, 2, 0, address(this));
        //put usdc into the pool
        IERC20(USDC).approve(RPDW, type(uint256).max);
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(DOLA);
        assets[1] = IAsset(dolaPoolToken);
        assets[2] = IAsset(USDC);
        uint256[] memory vals = new uint256[](3);
        vals[0] = 0;
        vals[1] = 0;
        vals[2] = IERC20(USDC).balanceOf(address(this));
        IBalancerVault.JoinPoolRequest memory jpr = IBalancerVault.JoinPoolRequest(
            assets,
            vals,
            abi.encode(uint256(1), [uint256(0), uint256(IERC20(USDC).balanceOf(address(this)))], IERC20(USDC).balanceOf(address(this))/4),
            false
        );
        IRewardPool4626(RPDW).depositSingle(poolREwardPool, IERC20(USDC), IERC20(USDC).balanceOf(address(this)), dolaPoolBytesId, jpr);
    }

    //if hf is too low
    function securePosition() public { 
        require(msg.sender == AGENT, "Only agnet");
            (uint256 collateral, uint256 debt, uint256 available,,,uint256 healthfactor) = IPool(AAVEPOOL).getUserAccountData(address(this));
            //we need to redeem debt - collaterisation/targetHf
            uint256 toRedeem = debt - (collateral*1e18)/HFWEI; //feeds are in usd
            IRewardPool4626(poolREwardPool).withdrawAndUnwrap(toRedeem, false);
            //now unwrap in balancer
            (,uint256[] memory quotes) = IBalancerQueries(balancerQuery).queryExit(dolaPoolBytesId, address(this), address(this), 
        abi.encode(uint256(0), IERC20(dolaPoolToken).balanceOf(address(this))/10000, uint256(2)));
            uint256 quoteUsdc = quotes[2];
            IBalancerVault(UNDERLYINGBAL).exitPool(dolaPoolBytesId, address(this), payable(address(this)),  abi.encode(uint256(0), (quoteUsdc*9)/10, uint256(2)));
            //repay part of debt
            IPool(AAVEPOOL).repay(USDC, toRedeem, 2, address(this));
            //position is now secure
        
    }

    function shouldIRebalance() public view returns (bool flag, bytes memory cdata){
        (uint256 collateral, uint256 debt, uint256 available,,,uint256 healthfactor) = IPool(AAVEPOOL).getUserAccountData(address(this));
        if (healthfactor < HFWEI){
            return (true, abi.encodeWithSelector(this.securePosition.selector));
        }
        else {
            return (false, abi.encodeWithSelector(this.securePosition.selector));
        }
    }


}