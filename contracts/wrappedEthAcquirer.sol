pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./Interfaces.sol";

contract wrappedEthAcquirer is Ownable (0xb17f6e542373E5662a37E8c354377Be2eecfBA82) {
    struct params {
        address stable;
        uint256 thresh;
        uint256 amtStableSell;
    }
    mapping(address=>mapping(address=>uint256)) public userBalances;
    mapping(address=>params) public userParams;
    address[] users;
    address public immutable WETH; //0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
    address public immutable VAULT; //0x489ee077994B6658eAfA855C308275EAd8097C4A
    address public immutable READER; //0x22199a49A999c351eF7927602CFB187ec3cae489
    address public immutable ROUTER; //0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064
    address public immutable BALVAULT; //0xBA12222222228d8Ba445958a75a0704d566BF2C8
    address public AGENT; //0xad1e507f8a0cb1b91421f3bb86bbe29f001cbcc6
    address public immutable WSTETH; //0x5979D7b546E38E414F7E9822514be443A4800529
    bytes32 public immutable balPoolId; //0x9791d590788598535278552eecd4b211bfc790cb000000000000000000000498
    address public immutable BALANCERQUERY; //0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5 
    address public secondStage;
    mapping(address=>bool) public secondStageCallingPermissions;

    event registered(address indexed stable, uint256 indexed thresh, uint256 indexed amtStableSell, address owner);
    event updatedParams(address indexed stable, uint256 indexed thresh, uint256 indexed amtStableSell, address owner);

    constructor(address _secondStage, address _WETH, address _WSTETH, bytes32 _balPoolId, address vault, address reader, address router, address agent, address balvault, address balancerquery){
        secondStage = _secondStage;
        WETH = _WETH;
        WSTETH = _WSTETH;
        balPoolId = _balPoolId;
        ROUTER = router;
        READER = reader;
        VAULT = vault;
        AGENT = agent;
        BALVAULT = balvault;
        BALANCERQUERY = balancerquery;
    }

    function replenish(address token, uint256 amt) public {
        IERC20(token).transferFrom(msg.sender, address(this), amt);
        userBalances[msg.sender][token] += amt;
    }
    
    function withdraw(address token, uint256 amt) public {
        require(amt <= userBalances[msg.sender][token], "Insufficient balance");
        IERC20(token).transfer(msg.sender, amt);
        userBalances[msg.sender][token] -= amt;
    }

    function drawAdditional(address from) internal {
        params memory param = userParams[from];
        address token = param.stable;
        uint256 toDraw = userBalances[from][token]<param.amtStableSell ? param.amtStableSell - userBalances[from][token] : 0;
        if (toDraw>0){
            IERC20(token).transferFrom(from, address(this), toDraw);
            userBalances[from][token] += toDraw;
        }  
    }

    function register(address _stable, uint256 _thresh, uint256 _amtStableSell) public {
        if(userParams[msg.sender].stable == address(0)){
            users.push(msg.sender);
        }
        userParams[msg.sender] = params(
            _stable,
            _thresh,
            _amtStableSell
        );
        drawAdditional(msg.sender);
        
        emit registered(_stable, _thresh, _amtStableSell, msg.sender);
    }

    function modify(address _stable, uint256 _thresh, uint256 _amtStableSell) public{
        params memory param = userParams[msg.sender];
        address stable = _stable != address(0) ? _stable : param.stable;
        uint256 thresh = _thresh > 0 ? _thresh : param.thresh;
        uint256 amtStableSell = _amtStableSell > 0 ? _amtStableSell : param.amtStableSell;
        userParams[msg.sender] = params(
            stable,
            thresh,
            amtStableSell
        );
        emit updatedParams(stable, thresh, amtStableSell, msg.sender);
    }

    function tradeWethForWstethIfNeeded(address _for) internal {
        params memory param = userParams[_for];
        if (userBalances[_for][WETH] >= param.thresh){
            //swap weth for wsteth on Bal
            ISwapper.SingleSwap memory swapdata = ISwapper.SingleSwap(
                balPoolId,
                ISwapper.SwapKind(0),
                IAsset(WETH),
                IAsset(WSTETH),
                userBalances[_for][WETH],
                bytes("0")
            );
            ISwapper.FundManagement memory fm = ISwapper.FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            );
            IERC20(WETH).approve(BALVAULT, type(uint256).max);
            uint256 prevWsteth = IERC20(WSTETH).balanceOf(address(this));
            ISwapper(BALVAULT).swap(
                swapdata,
                fm,
                (IBalancerQueries(BALANCERQUERY).querySwap(swapdata, fm)*80)/100,
                block.timestamp + 1800
            );
            uint256 postWsteth = IERC20(WSTETH).balanceOf(address(this));
            userBalances[_for][WSTETH] += (postWsteth-prevWsteth);
            userBalances[_for][WETH] = 0;
        }
    }

    function swapStableForWeth(address _for) public {
        require((msg.sender == _for)||(msg.sender == this.owner())||(msg.sender == AGENT), "NOT PERMITTTED");
        //the owner permission is temporary for debugging
        //quote the price from gmx reader
        params memory param = userParams[_for];
        (uint256 afterFees,) = IReader(READER).getAmountOut(
            IVault(VAULT),
            param.stable,
            WETH,
            param.amtStableSell
        );
        //adjust for slippage
        uint256 admissible = (afterFees*80)/100;
        drawAdditional(_for);
        //swap
        address [] memory path = new address[](2);
        path[0] = param.stable;
        path[1] = WETH;
        uint256 prevWeth = IERC20(WETH).balanceOf(address(this));
        IERC20(param.stable).approve(ROUTER, type(uint256).max);
        IRouter(ROUTER).swap(
            path, param.amtStableSell, admissible, address(this)
        );
        uint256 currentWeth = IERC20(WETH).balanceOf(address(this));
        userBalances[_for][WETH] += (currentWeth-prevWeth);
        userBalances[_for][param.stable] -= param.amtStableSell;
        tradeWethForWstethIfNeeded(_for);
    }

    function target() public {
        require(msg.sender == AGENT, "ONLY AGENT");
            for (uint256 i = 0; i<users.length; i++){
                swapStableForWeth(users[i]);
            }
        
    }

}