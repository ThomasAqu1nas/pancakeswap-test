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
         //require(msg.sender == WBNB, "CustomRouter: ONLY_WBNB");
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
 * @notice Функция, позволяющая явно указать суммы BNB для свапа и добавления ликвидности.
 * Пользователь отправляет сумму BNB, равную swapEthAmount + liquidityEthAmount.
 * Часть BNB используется для обмена на токен, оставшаяся часть вместе с токенами добавляется в ликвидность.
 * Излишки токенов возвращаются отправителю.
 * @param token Адрес токена (например, USDT).
 * @param swapEthAmount Сумма BNB, предназначенная для обмена на токены.
 * @param liquidityEthAmount Сумма BNB, предназначенная для добавления ликвидности.
 * @param minTokensOut Минимальное количество токенов, которые должны быть получены при свапе.
 * @param deadline Дедлайн для транзакции.
 */
function swapThenAddLiquidity(
    address token,
    uint256 swapEthAmount,
    uint256 liquidityEthAmount,
    uint256 minTokensOut,
    uint256 deadline
)
    external
    payable
    ensure(deadline)
    returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
{
    require(msg.value == swapEthAmount + liquidityEthAmount, "CustomRouter: INVALID_ETH_AMOUNT");

    // Выполняем свап указанного количества BNB на токены
    uint256 tokensReceived = swapEthForExactTokensInternal(token, minTokensOut, swapEthAmount, deadline);

    // Одобряем расход полученных токенов для добавления ликвидности
    require(IERC20(token).approve(pancakeRouter, tokensReceived), "CustomRouter: APPROVAL_FAILED");

    // Добавляем ликвидность, используя полученные токены и указанное количество BNB
    (amountToken, amountETH, liquidity) = IPancakeRouter(pancakeRouter).addLiquidityETH{value: liquidityEthAmount}(
        token,
        tokensReceived,
        0,
        0,
        msg.sender,
        deadline
    );

    // Возвращаем излишки токенов отправителю
    if (tokensReceived > amountToken) {
        require(IERC20(token).transfer(msg.sender, tokensReceived - amountToken), "CustomRouter: REFUND_FAILED");
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
