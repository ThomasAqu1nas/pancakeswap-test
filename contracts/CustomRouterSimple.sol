// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/**************************************/
/*           ИНТЕРФЕЙСЫ              */
/**************************************/
interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakePair {
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface IPancakeRouter {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

/**************************************/
/*         PancakeLibrary             */
/**************************************/
library PancakeLibrary {
    // Сортировка адресов токенов: token0 < token1
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
         require(tokenA != tokenB, "PancakeLibrary: IDENTICAL_ADDRESSES");
         (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
         require(token0 != address(0), "PancakeLibrary: ZERO_ADDRESS");
    }
    
    // Получение адреса пары через фабрику; требует, чтобы пара уже существовала.
    function pairFor(address factory, address tokenA, address tokenB) internal view returns (address pair) {
         pair = IPancakeFactory(factory).getPair(tokenA, tokenB);
         require(pair != address(0), "PancakeLibrary: PAIR_NOT_EXIST");
    }
}

/**************************************/
/*       CUSTOM ROUTER КОНТРАКТ       */
/**************************************/
contract CustomRouter {
    address public immutable factory;
    address public immutable WBNB;
    address public immutable pancakeRouter;
    
    modifier ensure(uint256 deadline) {
         require(deadline >= block.timestamp, "CustomRouter: TRANSACTION_EXPIRED");
         _;
    }
    
    constructor(address _factory, address _WBNB, address _pancakeRouter) {
         factory = _factory;
         WBNB = _WBNB;
         pancakeRouter = _pancakeRouter;
    }
    
    // Принимаем ETH только от WBNB (например, при вызове withdraw)
    receive() external payable {
         require(msg.sender == WBNB, "CustomRouter: ONLY_WBNB");
    }
    
    /**************************************/
    /*      ФУНКЦИЯ СВАПА ETH -> ТОКЕН     */
    /**************************************/
    
    /**
     * @notice Внешняя функция для свапа ETH (оборачиваемого в WBNB) на точное количество токенов.
     * @dev Требует, чтобы msg.value равнялось swapEthAmount.
     * @param amountOut Точное ожидаемое количество токенов.
     * @param token Адрес целевого токена.
     * @param swapEthAmount Сумма ETH, используемая для свапа.
     * @param deadline Дедлайн для транзакции.
     * @return tokensReceived Количество полученных токенов.
     */
    function swapEthForExactTokensExternal(
         uint256 amountOut,
         address token,
         uint256 swapEthAmount,
         uint256 deadline
    )
         external
         payable
         ensure(deadline)
         returns (uint256 tokensReceived)
    {
         require(msg.value == swapEthAmount, "CustomRouter: INCORRECT_ETH_AMOUNT");
         tokensReceived = swapEthForExactTokensInternal(token, amountOut, swapEthAmount, deadline);
         // Перевод полученных токенов на адрес вызывающего
         require(IERC20(token).transfer(msg.sender, tokensReceived), "CustomRouter: TOKEN_TRANSFER_FAILED");
    }
    
    /**
     * @notice Внутренняя функция, выполняющая свап ETH -> токены.
     * Токены зачисляются на адрес этого контракта, и функция измеряет разницу балансов.
     */
    function swapEthForExactTokensInternal(
         address token,
         uint256 expectedTokenOut,
         uint256 swapEthAmount,
         uint256 deadline
    )
         internal
         ensure(deadline)
         returns (uint256 tokensReceived)
    {
         uint256 initialBalance = IERC20(token).balanceOf(address(this));
         IWETH(WBNB).deposit{value: swapEthAmount}();
         address pair = PancakeLibrary.pairFor(factory, WBNB, token);
         
         require(IWETH(WBNB).transfer(pair, swapEthAmount), "CustomRouter: WBNB_TRANSFER_FAILED");
         
         (address token0, ) = PancakeLibrary.sortTokens(WBNB, token);
         uint256 amount0Out = WBNB == token0 ? 0 : expectedTokenOut;
         uint256 amount1Out = WBNB == token0 ? expectedTokenOut : 0;
         
         IPancakePair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
         
         tokensReceived = IERC20(token).balanceOf(address(this)) - initialBalance;
    }
    
    /**************************************/
    /*    ФУНКЦИЯ ДОБАВЛЕНИЯ ЛИКВИДНОСТИ  */
    /**************************************/
    
    /**
     * @notice Функция для добавления ликвидности, которая напрямую вызывает функцию addLiquidityETH
     * у официального PancakeSwap Router. В этой функции токены переводятся от вызывающего.
     * @param token Адрес токена, с которым пара WBNB.
     * @param tokenAmount Количество токенов для добавления ликвидности.
     * @param ethAmount Количество ETH для ликвидности.
     * @param tokenMin Минимальное количество токенов, принимаемое в ликвидность.
     * @param ethMin Минимальное количество ETH, принимаемое в ликвидность.
     * @param deadline Дедлайн для транзакции.
     */
    function addLiquidityDirectly(
         address token,
         uint256 tokenAmount,
         uint256 ethAmount,
         uint256 tokenMin,
         uint256 ethMin,
         uint256 deadline
    )
         external
         payable
         ensure(deadline)
         returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
         require(msg.value == ethAmount, "CustomRouter: INCORRECT_ETH_AMOUNT");
         
         require(IERC20(token).transferFrom(msg.sender, address(this), tokenAmount), "CustomRouter: TOKEN_TRANSFER_FROM_FAILED");
         
         require(IERC20(token).approve(pancakeRouter, tokenAmount), "CustomRouter: APPROVAL_FAILED");
         
         (amountToken, amountETH, liquidity) = IPancakeRouter(pancakeRouter).addLiquidityETH{value: ethAmount}(
             token,
             tokenAmount,
             tokenMin,
             ethMin,
             msg.sender,
             deadline
         );
    }
    
    /**
     * @notice Композитная функция, которая сначала выполняет свап ETH в токены,
     * а затем добавляет полученные токены и дополнительный ETH в ликвидность.
     * Токены, полученные после свапа, остаются в контракте и используются для добавления ликвидности.
     * Излишки токенов возвращаются вызывающему.
     * @param token Адрес целевого токена.
     * @param swapEthAmount Сумма ETH, используемая для свапа.
     * @param expectedTokenOut Ожидаемое количество токенов после свапа.
     * @param tokenMin Минимальное количество токенов для ликвидности.
     * @param ethMin Минимальное количество ETH для ликвидности.
     * @param additionalEthForLiquidity Дополнительный ETH, который пойдёт в ликвидность.
     * @param deadline Дедлайн для транзакции.
     */
    function swapThenAddLiquidity(
         address token,
         uint256 swapEthAmount,
         uint256 expectedTokenOut,
         uint256 tokenMin,
         uint256 ethMin,
         uint256 additionalEthForLiquidity,
         uint256 deadline
    )
         external
         payable
         ensure(deadline)
         returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
         require(msg.value == swapEthAmount + additionalEthForLiquidity, "CustomRouter: INCORRECT_TOTAL_ETH");
         
         uint256 tokensReceived = swapEthForExactTokensInternal(token, expectedTokenOut, swapEthAmount, deadline);
         (amountToken, amountETH, liquidity) = addLiquidityWithTokensInContract(token, tokensReceived, additionalEthForLiquidity, tokenMin, ethMin, deadline);
         
         uint256 remainingTokens = IERC20(token).balanceOf(address(this));
         if (remainingTokens > 0) {
             IERC20(token).transfer(msg.sender, remainingTokens);
         }
    }
    
    /**
     * @notice Внутренняя функция для добавления ликвидности с токенами, уже находящимися в контракте.
     * Одобряет расход токенов и вызывает addLiquidityETH у PancakeSwap Router.
     */
    function addLiquidityWithTokensInContract(
         address token,
         uint256 tokenAmount,
         uint256 ethAmount,
         uint256 tokenMin,
         uint256 ethMin,
         uint256 deadline
    )
         internal
         returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
         require(IERC20(token).approve(pancakeRouter, tokenAmount), "CustomRouter: APPROVAL_FAILED");
         (amountToken, amountETH, liquidity) = IPancakeRouter(pancakeRouter).addLiquidityETH{value: ethAmount}(
             token,
             tokenAmount,
             tokenMin,
             ethMin,
             msg.sender,
             deadline
         );
    }
}
