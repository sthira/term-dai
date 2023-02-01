// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

interface VatAbstract {
    function live() external view returns (uint256);
}

interface GateAbstract {
    function vat() external view returns (address);
    function draw(address dst_, uint256 amount_) external;
}

interface DaiJoinAbstract {
    function exit(address, uint256) external;
}

interface GemAbstract {
    function transferFrom(address, address, uint256) external returns (bool);
}

// Term Dai creates a new group of users incentivized to monitor the long term health of Dai and argue for 
// emergency shutdown to activate their immediate redemption to protect all Dai holders along with themselves
// in exchange for a guaranteed payout in dai for holding until term 
contract TermDai {
    // --- Auth ---
    mapping (address => uint256) public wards; // Addresses with admin authority
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    function rely(address _usr) external auth { wards[_usr] = 1; emit Rely(_usr); }  // Add admin
    function deny(address _usr) external auth { wards[_usr] = 0; emit Deny(_usr); }  // Remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "td/not-authorized");
        _;
    }

    // --- User Approvals ---
    mapping(address => mapping (address => uint256)) public can; // address => approved address => approval status
    event Approval(address indexed sender, address indexed usr, uint256 approval);
    function hope(address usr) external { can[msg.sender][usr] = 1; emit Approval(msg.sender, usr, 1);}
    function nope(address usr) external { can[msg.sender][usr] = 0; emit Approval(msg.sender, usr, 0);}
    function wish(address sender, address usr) internal view returns (bool) {
        return either(sender == usr, can[sender][usr] == 1);
    }

    GateAbstract public gate; // gate
    VatAbstract public immutable vat; // vat
    GemAbstract public immutable dai; // dai erc20 token
    DaiJoinAbstract public immutable daiJoin; // dai join

    // class = keccak256(maturity timestamp)
    mapping(address => mapping(bytes32 => uint256)) public tDai; // user address => class => balance [wad]
    mapping(bytes32 => uint256) public totalSupply; // class => total supply [wad]
    
    // gov controlled issuance params
    struct Params {
        uint256 size; // total issuance size [wad]
        uint256 discount; // discount fraction [tad] ex: 0.03 for 3%
    }
    // term duration (seconds) => issuance parameters {issuance size, issuance discount}
    mapping(uint256 => Params) public issuanceParams;
    // ex: 30 days => {10MM, 3%}

    uint256 live; // operational status of term dai

    event File(bytes32 indexed what, address data);
    event MoveTermDai(address indexed src, address indexed dst, bytes32 indexed class_, uint256 bal);
    event UpdateIssuanceParams(uint256 indexed duration, uint256 size, uint256 discount);
    event Closed(uint256 timestamp, uint256 vatLive);

    constructor(address gate_, address dai_, address daiJoin_) {
        wards[msg.sender] = 1; // set admin
        emit Rely(msg.sender);

        gate = GateAbstract(gate_); // set gate
        vat = VatAbstract(gate.vat()); // set vat from gate
        dai = GemAbstract(dai_); // set dai
        daiJoin = DaiJoinAbstract(daiJoin_); // set dai join

        live = 1; // will be set to 0 when this term dai instance is closed
    }

    // --- Utils ---
    uint256 constant internal TAD = 10 ** 10;
    uint256 constant internal WAD = 10 ** 18;
    uint256 constant internal RAY = 10 ** 27;

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Setup ---
    /// Update Gate address
    /// @dev Restricted to authorized governance addresses
    /// @param what what value are we updating
    /// @param data what are we updating it to
    function file(bytes32 what, address data) external auth {
        if (what == "gate") {
            require(vat == VatAbstract(GateAbstract(data).vat()), "vat-does-not-match");
            gate = GateAbstract(data); // update gate address

            emit File(what, address(data));
        } else revert("td/file-not-recognized");
    }

    // --- Internal ---
    /// Mint Term Dai balance
    /// @param usr User address
    /// @param maturity Maturity timestamp of term dai balance
    /// @param bal Term dai balance amount [wad]
    function mintTermDai(
        address usr,
        uint256 maturity,
        uint256 bal
    ) internal {
        // calculate term dai class with maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        tDai[usr][class_] = tDai[usr][class_] + bal;
        totalSupply[class_] = totalSupply[class_] + bal;
        emit MoveTermDai(address(0), usr, class_, bal);
    }

    /// Burn Term Dai balance
    /// @param usr User address
    /// @param maturity Maturity timestamp of term dai balance
    /// @param bal Term dai balance amount [wad]
    function burnTermDai(
        address usr,
        uint256 maturity,
        uint256 bal
    ) internal {
        // calculate term dai class with maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        require(tDai[usr][class_] >= bal, "td/insufficient-balance");

        tDai[usr][class_] = tDai[usr][class_] - bal;
        totalSupply[class_] = totalSupply[class_] - bal;
        emit MoveTermDai(usr, address(0), class_, bal);
    }

    // --- Transfer ---
    /// Transfer term dai balance
    /// @param src Source address to transfer balance from
    /// @param dst Destination address to transfer balance to
    /// @param class_ Term dai balance class
    /// @param bal Term dai balance amount to transfer [wad]
    function moveTermDai(
        address src,
        address dst,
        bytes32 class_,
        uint256 bal
    ) external {
        require(wish(src, msg.sender), "not-allowed");
        require(tDai[src][class_] >= bal, "td/insufficient-balance");

        tDai[src][class_] = tDai[src][class_] - bal;
        tDai[dst][class_] = tDai[dst][class_] + bal;

        emit MoveTermDai(src, dst, class_, bal);
    }

    // --- Authorized Issuance and Redemption ---
    /// Create Term Dai Balance (Authorized Issuance)
    /// @param maturity Maturity Timestamp set for the issued balance
    /// @param amount_ dai amount transferred, term dai amount issued [wad]
    /// @dev Authorized address executing the method and funding it with dai balance
    /// @dev will receive the term dai transfer
    function create(uint256 maturity, uint256 amount_) public auth {
        require(live == 1, "td/not-live"); // stop issuance when closed

        // authorized extension contracts will collect and transfer entire dai amount
        // to back minted term dai balance
        dai.transferFrom(msg.sender, address(this), amount_);
        mintTermDai(msg.sender, maturity, amount_);
    }
    
    /// Remove Term Dai Balance (Authorized Redemption)
    /// @param maturity Maturity Timestamp of the balance to be redeemed
    /// @param amount_ dai amount transferred to redeemer, term dai amount redeemed [wad]
    /// @dev Authorized address executing the method and funding it with the term dai balance
    /// @dev will receive the dai transfer
    function remove(uint256 maturity, uint256 amount_) public auth {
         burnTermDai(msg.sender, maturity, amount_);
         dai.transferFrom(address(this), msg.sender, amount_);
    }

    // --- Gov Parameters ---
    /// Update Issuance Parameters
    /// @param duration Time Duration set during issuance used for lookup, ex: 2592000 for 30 days
    /// @param size_ Term dai issuance limit set by governance for a particular duration
    /// @param discount_ Amount of dai governance will fund for each unit of term dai issuance [tad]
    /// @dev number type of discount is tad- 10 fixed-decimal number
    function updateParams(uint256 duration, uint256 size_, uint256 discount_) public auth {
        issuanceParams[duration].size = size_;
        issuanceParams[duration].discount = discount_;
        emit UpdateIssuanceParams(duration, size_, discount_);
    }

    // --- Issuance ---
    /// User Issuance
    /// @param usr User address to take dai balance from and issue term dai balance to
    /// @param amount_ amount of term dai to issue
    /// @param duration duration in seconds to lookup issuance parameters and calculate maturity
    function issue(address usr, uint256 amount_, uint256 duration) public {
        require(wish(usr, msg.sender), "not-allowed");
        require(live == 1, "td/not-live");

        // reduce issuance size by issuance amount
        // operation fails if issuance limit is lower
        issuanceParams[duration].size = (issuanceParams[duration].size - amount_);

        uint256 discountPortion = (amount_ * issuanceParams[duration].discount) / TAD; // calculate discount portion [wad * tad / tad = wad]
        uint256 userPortion = (amount_ - discountPortion); // calculate user portion [wad]
        
        // pull discount portion from gate and convert to dai erc20 balance
        gate.draw(address(this), discountPortion * RAY); // gate requires dai amount in [rad = wad * ray]
        daiJoin.exit(address(this), discountPortion); // dai join requires dai amount in [wad]

        // pull user portion from user
        dai.transferFrom(usr, address(this), userPortion);
        
        // issue term dai balance to user 
        // calculate maturity date by adding duration to current block timestamp 
        mintTermDai(usr, (block.timestamp + duration), amount_);
    }

    // --- Redemption ---
    function redeem(address usr, uint256 amount_, uint256 maturity) public {
        require(wish(usr, msg.sender), "not-allowed");

        // check maturity date is past current
        // OR skip this check if live flag is 0, instance is closed
        require((maturity >= block.timestamp) || (live == 0), "td/cannot-redeem");

        // burn term dai
        burnTermDai(usr, maturity, amount_);
        
        // transfer dai to user
        dai.transferFrom(address(this), usr, amount_);
    }

    // --- Close ---
    /// Closes this term dai instance
    /// @dev live set to 0
    function close() external {
        require(live == 1, "td/closed"); // can be closed only once
        
        // at least one close condition needs to be met:
        // * maker protocol is shutdown
        // * governance executes close
        require(wards[msg.sender] == 1 || VatAbstract(vat).live() == 0, "close/conditions-not-met");

        live = 0; // close instance, activate immediate redemption of all term dai 1:1

        // close timestamp, and vat.live status at close
        emit Closed(block.timestamp, VatAbstract(vat).live());
    }
}