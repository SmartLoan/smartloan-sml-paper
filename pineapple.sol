pragma solidity ^0.5.8;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
}

contract Token{
    using SafeMath for uint256;
	uint256 totalSupply_;
	address[] public lenders;

    event Transfer(address indexed from,address indexed to,uint256 value);
    event Approval(address indexed owner,address indexed spender,uint256 value);

	mapping(address => uint256) balances;
	mapping (address => mapping(address => uint256)) internal allowed;
	

    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    function transfer(address _to,uint256 _value) public returns(bool){
        require(_value <= balances[msg.sender]);
        require(_to != address(0));
        
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);

        emit Transfer(msg.sender,_to,_value);
        return true;
    }

    function balanceOf(address _owner) public view returns(uint256) {
        return balances[_owner];
    }

    function transferFrom(address _from,address _to, uint256 _value) public returns(bool){
        require(_value <= balances[_from]);
        //require(_value <= allowed[_from][msg.sender]);
        require(_to != address(0));

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        //allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);

        emit Transfer(_from,_to,_value);

        return true;
    }
    
    function saveAddress() payable public {
        lenders.push(msg.sender);
   }
}

contract PineappleToken is Token{
    string public name = "Pineapple Token";
    string public symbol = "PPAP";
    uint256 public decimals = 18;
	uint256 public INITIAL_SUPPLY = 1e5;
    //
	address payable public tokenWallet;
    address payable public owner;
    
    uint256 public ICOStartTime = now;
    uint256 public ICOEndTime = now.add(60);  
    bool public ICOCompleted;
    uint256 public constant tokenBuyRate = 0.001 ether;
    
    uint256 public RepaymentStartTime;
    uint256 public RepaymentCount;
    uint256 public monthlySalary = 0;
    

    modifier whenIcoCompleted{
        require(ICOCompleted);
        _;
    }
    
    modifier onlyCrowdsale{
        require(now < ICOEndTime && now > ICOStartTime);
        _;
    }

    modifier onlyOwner{
        require(msg.sender == owner);
        _;
    }

    modifier afterCrowdsale{
        require(now > ICOEndTime);
        _;
    }
    
    modifier repaymentPeriod{
        require(now > RepaymentStartTime);
        _;
    }
    
    //Call function to start repayment period
    function startRepayment(uint256 _monthlySalary, uint256 _RepaymentCount) public onlyOwner afterCrowdsale returns(bool){
        RepaymentStartTime = now;
        monthlySalary = _monthlySalary.mul(1 ether); //when input, it is in wei
        RepaymentCount = _RepaymentCount;
        endBurnLeftoverToken();
        return true;
    }
    
    //Can only start to distribute interest after the repayment period started
    function distributeInterest() public payable onlyOwner afterCrowdsale repaymentPeriod{
        //Interest is 5%per anum of monthly reported salary. monthlySalary
        require(monthlySalary > 0);
        uint256 InterestRate = monthlySalary.div(100).mul(5).div(INITIAL_SUPPLY);
        uint256 InterestCalc = 0 ether;
        for (uint i=0; i<lenders.length; i++) {
            address payable makePayAdd = address(uint160(lenders[i]));
            InterestCalc = balances[makePayAdd].mul(InterestRate);
            require (InterestCalc > 0, "Amount is less than the minimum value");
            require (msg.sender.balance >= InterestCalc, "Contract balance is empty");
            makePayAdd.transfer(InterestCalc); //ether must be in contract balance
        }
    }
    
    function endBurnLeftoverToken() public afterCrowdsale onlyOwner{
        totalSupply_ = totalSupply_.sub(balances[msg.sender]);
        emit Transfer(msg.sender, address(0), balances[msg.sender]);
        balances[msg.sender] = 0;
    }

    function Repayment() public payable onlyOwner afterCrowdsale repaymentPeriod {
        uint256 tokensRepay;
        uint256 tokensRepayEther = 0 ether;
        
        for (uint i=0; i<lenders.length; i++) {
            address payable makePayAdd = address(uint160(lenders[i]));
            
            tokensRepay = balances[makePayAdd].div(RepaymentCount);
            tokensRepayEther = tokensRepay.mul(tokenBuyRate);
            
            require (tokensRepayEther > 0, "Amount is less than the minimum value");
            require (msg.sender.balance >= tokensRepayEther, "Contract balance is empty");
            
            makePayAdd.transfer(tokensRepayEther); //ether must be in contract balance
            transferFrom(makePayAdd,msg.sender,tokensRepay);
        }
        
        //burn the repaid tokens here
        endBurnLeftoverToken();
        RepaymentCount--;
    }
    
    function buyTokens() public payable onlyCrowdsale{
        require(msg.sender != address(0));
        require(balances[tokenWallet] > 0);
        
        uint256 etherUsed = uint256(msg.value);
        require(etherUsed > 0);
        uint256 tokensToBuy = etherUsed.div(tokenBuyRate);
        
        // Return extra ether when tokensToBuy > balances[tokenWallet]
        if(tokensToBuy > balances[tokenWallet]){
            uint256 exceedingTokens = tokensToBuy.sub(balances[tokenWallet]);
            uint256 exceedingEther = 0 ether;

            exceedingEther = exceedingTokens.mul(tokenBuyRate);
            msg.sender.transfer(exceedingEther);
            tokensToBuy = tokensToBuy.sub(exceedingTokens);
            etherUsed = etherUsed.sub(exceedingEther);
        }
        //Need some additional safety algo to prevent direct call of the transferFrom function
        transferFrom(owner,msg.sender,uint256(tokensToBuy));
        //Keep track of lenders for future repayment purpose
        saveAddress();
    }
    
    function depositContract() public payable onlyOwner afterCrowdsale repaymentPeriod{
        require(msg.sender != address(0));
        require(balances[tokenWallet] > 0);
    }

    function emergencyExtract() external payable onlyOwner{
        owner.transfer(address(this).balance);
    }
	
	constructor () public Token(){
        totalSupply_ = INITIAL_SUPPLY;
        owner = msg.sender;
        tokenWallet = owner;
        balances[tokenWallet] = INITIAL_SUPPLY;
    }
}
