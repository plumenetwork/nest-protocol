import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";

type BundleRoute = "increase" | "decrease-instant" | "decrease-redeem";
type DecreaseRoute = "decrease-instant" | "decrease-redeem";
type Route = BundleRoute | "invariant-check";

type Hex = string;

type MarketParams = {
    loanToken: string;
    collateralToken: string;
    oracle: string;
    irm: string;
    lltv: bigint;
};

type Position = {
    borrowShares: bigint;
    collateral: bigint;
};

type MarketState = {
    totalBorrowAssets: bigint;
    totalBorrowShares: bigint;
};

type ExtraInputs = {
    extraLoanAssets: bigint;
    extraCollateral: bigint;
    tokenTransferredBackToUser: bigint;
};

type Quote = {
    borrowSharesDelta: bigint;
    repaySharesDelta: bigint;
    supplyCollateralDelta: bigint;
    withdrawCollateralDelta: bigint;
    borrowAssetsDelta: bigint;
    repayAssetsDelta: bigint;
    currentNetValue: bigint;
    targetNetValue: bigint;
    extraProvidedValue: bigint;
    expectedTokenTransferredBack: bigint;
    invariantHolds: boolean;
};

type Call = {
    to: string;
    data: Hex;
    value: bigint;
    skipRevert: boolean;
    callbackHash: Hex;
};

type AddressBook = {
    bundler: string;
    generalAdapter: string;
    nestAdapter: string;
    morpho: string;
    vault: string;
    initiator: string;
    positionOwner: string;
    depositReceiver: string;
    redeemReceiver: string;
};

type JsonConfig = {
    rpcUrl?: string;
    expectedMarketId?: string;
    addresses: {
        bundler: string;
        generalAdapter: string;
        nestAdapter?: string;
        morpho: string;
        vault: string;
        initiator: string;
        positionOwner?: string;
        depositReceiver?: string;
        redeemReceiver?: string;
    };
    marketParams: {
        loanToken: string;
        collateralToken: string;
        oracle: string;
        irm: string;
        lltv: string | number;
    };
    targetPosition: {
        borrowShares: string | number;
        collateral: string | number;
    };
    currentPosition?: {
        borrowShares: string | number;
        collateral: string | number;
    };
    marketState?: {
        totalBorrowAssets: string | number;
        totalBorrowShares: string | number;
    };
    extraInputs?: {
        extraLoanAssets?: string | number;
        extraCollateral?: string | number;
        extraSharesSupplied?: string | number;
        tokenTransferredBackToUser?: string | number;
    };
    collateralPrice: string | number;
    oraclePriceScale: string | number;
    minBorrowSharePriceE27?: string | number;
    maxRepaySharePriceE27?: string | number;
};

type IncreaseParams = {
    flashLoanAssets: bigint;
    flashLoanToNestAssets: bigint;
    extraLoanToNestAssets: bigint;
    depositAssets: bigint;
    collateralFromInitiatorAssets: bigint;
    supplyCollateralAssets: bigint;
    borrowAssets: bigint;
    minBorrowSharePriceE27: bigint;
};

type DecreaseParams = {
    flashLoanAssets: bigint;
    repayAssets: bigint;
    maxRepaySharePriceE27: bigint;
    withdrawCollateralAssets: bigint;
    redeemShares: bigint;
    loanFromInitiatorAssets: bigint;
};

const VIRTUAL_SHARES = 1_000_000n;
const VIRTUAL_ASSETS = 1n;
const MAX_UINT256 = (1n << 256n) - 1n;
const DEFAULT_MIN_BORROW_SHARE_PRICE_E27 = 0n;
const DEFAULT_MAX_REPAY_SHARE_PRICE_E27 = MAX_UINT256;
const ZERO_HASH = ethers.constants.HashZero;
const ZERO_ADDRESS = ethers.constants.AddressZero;
const CALL_TUPLE_ARRAY_TYPE =
    "tuple(address to,bytes data,uint256 value,bool skipRevert,bytes32 callbackHash)[]";

const generalAdapterAbi = new ethers.utils.Interface([
    "function erc20TransferFrom(address token,address receiver,uint256 amount)",
    "function morphoFlashLoan(address token,uint256 assets,bytes data)",
    "function morphoSupplyCollateral((address loanToken,address collateralToken,address oracle,address irm,uint256 lltv) marketParams,uint256 assets,address onBehalf,bytes data)",
    "function morphoBorrow((address loanToken,address collateralToken,address oracle,address irm,uint256 lltv) marketParams,uint256 assets,uint256 shares,uint256 minSharePriceE27,address receiver)",
    "function morphoRepay((address loanToken,address collateralToken,address oracle,address irm,uint256 lltv) marketParams,uint256 assets,uint256 shares,uint256 maxSharePriceE27,address onBehalf,bytes data)",
    "function morphoWithdrawCollateral((address loanToken,address collateralToken,address oracle,address irm,uint256 lltv) marketParams,uint256 assets,address receiver)",
]);

const coreAdapterAbi = new ethers.utils.Interface([
    "function erc20Transfer(address token,address receiver,uint256 amount)",
]);

const nestAdapterAbi = new ethers.utils.Interface([
    "function nestDeposit(address vault,uint256 assets,uint256 maxSharePriceE27,address receiver)",
    "function nestInstantRedeem(address vault,uint256 shares,uint256 minSharePriceE27,address receiver,address owner)",
    "function nestRedeem(address vault,uint256 shares,uint256 minSharePriceE27,address receiver,address owner)",
    "function morphoWithdrawCollateralOnBehalf((address loanToken,address collateralToken,address oracle,address irm,uint256 lltv) marketParams,uint256 assets,address onBehalf,address receiver)",
]);

const bundlerAbi = new ethers.utils.Interface([
    "function multicall((address to,bytes data,uint256 value,bool skipRevert,bytes32 callbackHash)[] bundle)",
]);

const morphoViewAbi = new ethers.utils.Interface([
    "function position(bytes32 id,address user) view returns ((uint256 supplyShares,uint128 borrowShares,uint128 collateral) p)",
    "function market(bytes32 id) view returns ((uint128 totalSupplyAssets,uint128 totalSupplyShares,uint128 totalBorrowAssets,uint128 totalBorrowShares,uint128 lastUpdate,uint128 fee) m)",
]);

export async function runRouteScript(route: BundleRoute): Promise<void> {
    try {
        const configPath = readConfigPathFromCli(process.argv.slice(2));
        const parsed = loadConfig(configPath);
        const resolved = await resolveCurrentState(parsed);
        const quote = quoteAndCheckInvariant(
            resolved.currentPosition,
            parsed.targetPosition,
            resolved.marketState,
            parsed.collateralPrice,
            parsed.oraclePriceScale,
            parsed.extraInputs
        );

        const bundle =
            route === "increase"
                ? buildIncreaseBundle(parsed.addresses, parsed.marketParams, quote, parsed.extraInputs, parsed.minBorrowSharePriceE27)
                : buildDecreaseBundle(
                      route,
                      parsed.addresses,
                      parsed.marketParams,
                      quote,
                      parsed.extraInputs,
                      parsed.maxRepaySharePriceE27
                  );
        const multicallCalldata = bundlerAbi.encodeFunctionData("multicall", [toAbiCalls(bundle)]);

        printSummary(route, configPath, parsed, resolved.currentPosition, resolved.marketState, quote);
        printBundle(route, bundle, parsed.addresses, parsed.marketParams);
        console.log("");
        console.log("multicall.calldata:");
        console.log(multicallCalldata);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`Bundle build failed: ${message}`);
        process.exitCode = 1;
    }
}

export async function runPositionScript(defaultDecreaseRoute: DecreaseRoute = "decrease-instant"): Promise<void> {
    try {
        const argv = process.argv.slice(2);
        const configPath = readConfigPathFromCli(argv);
        const decreaseRoute = readDecreaseRouteFromCli(argv, defaultDecreaseRoute);
        const parsed = loadConfig(configPath);
        const resolved = await resolveCurrentState(parsed);
        const quote = quoteAndCheckInvariant(
            resolved.currentPosition,
            parsed.targetPosition,
            resolved.marketState,
            parsed.collateralPrice,
            parsed.oraclePriceScale,
            parsed.extraInputs
        );
        const route = resolvePositionRoute(quote, decreaseRoute);

        const bundle =
            route === "increase"
                ? buildIncreaseBundle(parsed.addresses, parsed.marketParams, quote, parsed.extraInputs, parsed.minBorrowSharePriceE27)
                : buildDecreaseBundle(
                      route,
                      parsed.addresses,
                      parsed.marketParams,
                      quote,
                      parsed.extraInputs,
                      parsed.maxRepaySharePriceE27
                  );
        const multicallCalldata = bundlerAbi.encodeFunctionData("multicall", [toAbiCalls(bundle)]);

        printSummary(route, configPath, parsed, resolved.currentPosition, resolved.marketState, quote);
        printBundle(route, bundle, parsed.addresses, parsed.marketParams);
        console.log("");
        console.log("multicall.calldata:");
        console.log(multicallCalldata);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`Bundle build failed: ${message}`);
        process.exitCode = 1;
    }
}

export async function runInvariantScript(): Promise<void> {
    try {
        const configPath = readConfigPathFromCli(process.argv.slice(2));
        const parsed = loadConfig(configPath);
        const resolved = await resolveCurrentState(parsed);
        const quote = quoteAndCheckInvariant(
            resolved.currentPosition,
            parsed.targetPosition,
            resolved.marketState,
            parsed.collateralPrice,
            parsed.oraclePriceScale,
            parsed.extraInputs
        );

        printSummary("invariant-check", configPath, parsed, resolved.currentPosition, resolved.marketState, quote);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`Invariant validation failed: ${message}`);
        process.exitCode = 1;
    }
}

function readConfigPathFromCli(argv: string[]): string {
    const configIndex = argv.lastIndexOf("--config");
    if (configIndex === -1 || configIndex + 1 >= argv.length) {
        throw new Error("Missing --config <path> argument.");
    }
    return path.resolve(process.cwd(), argv[configIndex + 1]);
}

function readDecreaseRouteFromCli(argv: string[], fallback: DecreaseRoute): DecreaseRoute {
    const routeIndex = argv.indexOf("--decrease-route");
    if (routeIndex === -1) return fallback;
    if (routeIndex + 1 >= argv.length) {
        throw new Error("Missing --decrease-route <instant|redeem> argument.");
    }

    const value = argv[routeIndex + 1].trim().toLowerCase();
    if (value === "instant" || value === "decrease-instant") return "decrease-instant";
    if (value === "redeem" || value === "async" || value === "decrease-redeem") return "decrease-redeem";
    throw new Error(`Unsupported --decrease-route value: ${value}. Use instant|redeem.`);
}

function resolvePositionRoute(quote: Quote, decreaseRoute: DecreaseRoute): BundleRoute {
    const hasIncreaseLeg = quote.borrowAssetsDelta !== 0n || quote.supplyCollateralDelta !== 0n;
    const hasDecreaseLeg = quote.repayAssetsDelta !== 0n || quote.withdrawCollateralDelta !== 0n;

    if (!hasIncreaseLeg && !hasDecreaseLeg) {
        throw new Error("Current position already matches target position.");
    }
    if (hasIncreaseLeg && hasDecreaseLeg) {
        throw new Error(
            "Mixed route (one side increasing, the other decreasing) is not supported by current bundle builders."
        );
    }
    return hasIncreaseLeg ? "increase" : decreaseRoute;
}

function loadConfig(configPath: string): {
    rpcUrl?: string;
    expectedMarketId?: Hex;
    addresses: AddressBook;
    marketParams: MarketParams;
    targetPosition: Position;
    currentPosition?: Position;
    marketState?: MarketState;
    extraInputs: ExtraInputs;
    collateralPrice: bigint;
    oraclePriceScale: bigint;
    minBorrowSharePriceE27: bigint;
    maxRepaySharePriceE27: bigint;
} {
    const raw = fs.readFileSync(configPath, "utf8");
    const input = JSON.parse(raw) as JsonConfig;
    const generalAdapter = normalizeAddress(input.addresses.generalAdapter);
    const configuredNestAdapter = input.addresses.nestAdapter === undefined
        ? generalAdapter
        : normalizeAddress(input.addresses.nestAdapter);
    const nestAdapter = sameAddress(configuredNestAdapter, ZERO_ADDRESS)
        ? generalAdapter
        : configuredNestAdapter;

    const addresses: AddressBook = {
        bundler: normalizeAddress(input.addresses.bundler),
        generalAdapter,
        nestAdapter,
        morpho: normalizeAddress(input.addresses.morpho),
        vault: normalizeAddress(input.addresses.vault),
        initiator: normalizeAddress(input.addresses.initiator),
        positionOwner: normalizeAddress(input.addresses.positionOwner ?? input.addresses.initiator),
        depositReceiver: normalizeAddress(input.addresses.depositReceiver ?? input.addresses.initiator),
        redeemReceiver: normalizeAddress(input.addresses.redeemReceiver ?? input.addresses.initiator),
    };

    const marketParams: MarketParams = {
        loanToken: normalizeAddress(input.marketParams.loanToken),
        collateralToken: normalizeAddress(input.marketParams.collateralToken),
        oracle: normalizeAddress(input.marketParams.oracle),
        irm: normalizeAddress(input.marketParams.irm),
        lltv: bi(input.marketParams.lltv, "marketParams.lltv"),
    };
    const expectedMarketId = parseOptionalBytes32(input.expectedMarketId, "expectedMarketId");
    const computedMarketId = computeMarketId(marketParams);
    if (expectedMarketId !== undefined && expectedMarketId !== computedMarketId) {
        throw new Error(
            `Expected market id ${expectedMarketId} does not match computed market id ${computedMarketId} from marketParams.`
        );
    }

    const targetPosition: Position = {
        borrowShares: bi(input.targetPosition.borrowShares, "targetPosition.borrowShares"),
        collateral: bi(input.targetPosition.collateral, "targetPosition.collateral"),
    };

    const currentPosition =
        input.currentPosition === undefined
            ? undefined
            : {
                  borrowShares: bi(input.currentPosition.borrowShares, "currentPosition.borrowShares"),
                  collateral: bi(input.currentPosition.collateral, "currentPosition.collateral"),
              };

    const marketState =
        input.marketState === undefined
            ? undefined
            : {
                  totalBorrowAssets: bi(input.marketState.totalBorrowAssets, "marketState.totalBorrowAssets"),
                  totalBorrowShares: bi(input.marketState.totalBorrowShares, "marketState.totalBorrowShares"),
              };

    const extraLoanAssets = bi(input.extraInputs?.extraLoanAssets ?? 0, "extraInputs.extraLoanAssets");
    const extraCollateralExplicit = input.extraInputs?.extraCollateral;
    const extraSharesSupplied = input.extraInputs?.extraSharesSupplied;
    const extraCollateral = bi(extraCollateralExplicit ?? extraSharesSupplied ?? 0, "extraInputs.extraCollateral");
    const tokenTransferredBackToUser = bi(
        input.extraInputs?.tokenTransferredBackToUser ?? 0,
        "extraInputs.tokenTransferredBackToUser"
    );

    return {
        rpcUrl: input.rpcUrl,
        expectedMarketId,
        addresses,
        marketParams,
        targetPosition,
        currentPosition,
        marketState,
        extraInputs: {
            extraLoanAssets,
            extraCollateral,
            tokenTransferredBackToUser,
        },
        collateralPrice: bi(input.collateralPrice, "collateralPrice"),
        oraclePriceScale: bi(input.oraclePriceScale, "oraclePriceScale"),
        minBorrowSharePriceE27: bi(input.minBorrowSharePriceE27 ?? DEFAULT_MIN_BORROW_SHARE_PRICE_E27, "minBorrowSharePriceE27"),
        maxRepaySharePriceE27: bi(input.maxRepaySharePriceE27 ?? DEFAULT_MAX_REPAY_SHARE_PRICE_E27, "maxRepaySharePriceE27"),
    };
}

async function resolveCurrentState(parsed: {
    rpcUrl?: string;
    expectedMarketId?: Hex;
    addresses: AddressBook;
    marketParams: MarketParams;
    targetPosition: Position;
    currentPosition?: Position;
    marketState?: MarketState;
    extraInputs: ExtraInputs;
    collateralPrice: bigint;
    oraclePriceScale: bigint;
    minBorrowSharePriceE27: bigint;
    maxRepaySharePriceE27: bigint;
}): Promise<{ currentPosition: Position; marketState: MarketState }> {
    if (parsed.currentPosition && parsed.marketState) {
        return {
            currentPosition: parsed.currentPosition,
            marketState: parsed.marketState,
        };
    }
    if (!parsed.rpcUrl) {
        throw new Error(
            "rpcUrl is required when currentPosition or marketState is not provided."
        );
    }

    const provider = new ethers.providers.JsonRpcProvider(parsed.rpcUrl);
    const marketId = computeMarketId(parsed.marketParams);
    const morpho = new ethers.Contract(parsed.addresses.morpho, morphoViewAbi, provider);

    const [position, market] = await Promise.all([
        morpho.position(marketId, parsed.addresses.positionOwner),
        morpho.market(marketId),
    ]);

    const currentPosition: Position = {
        borrowShares: bnToBigInt(position.borrowShares),
        collateral: bnToBigInt(position.collateral),
    };
    const marketState: MarketState = {
        totalBorrowAssets: bnToBigInt(market.totalBorrowAssets),
        totalBorrowShares: bnToBigInt(market.totalBorrowShares),
    };
    return { currentPosition, marketState };
}

function quoteAndCheckInvariant(
    current: Position,
    target: Position,
    market: MarketState,
    collateralPrice: bigint,
    oraclePriceScale: bigint,
    extra: ExtraInputs
): Quote {
    if (oraclePriceScale === 0n) throw new Error("oraclePriceScale cannot be zero.");

    let borrowSharesDelta = 0n;
    let repaySharesDelta = 0n;
    let borrowAssetsDelta = 0n;
    let repayAssetsDelta = 0n;

    if (target.borrowShares >= current.borrowShares) {
        borrowSharesDelta = target.borrowShares - current.borrowShares;
        borrowAssetsDelta = toAssetsUp(borrowSharesDelta, market.totalBorrowAssets, market.totalBorrowShares);
    } else {
        repaySharesDelta = current.borrowShares - target.borrowShares;
        repayAssetsDelta = toAssetsUp(repaySharesDelta, market.totalBorrowAssets, market.totalBorrowShares);
    }

    const supplyCollateralDelta =
        target.collateral >= current.collateral ? target.collateral - current.collateral : 0n;
    const withdrawCollateralDelta =
        target.collateral < current.collateral ? current.collateral - target.collateral : 0n;

    const currentBorrowAssets = toAssetsUp(current.borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
    const targetBorrowAssets = toAssetsUp(target.borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
    const currentCollateralValue = collateralToLoanValue(current.collateral, collateralPrice, oraclePriceScale);
    const targetCollateralValue = collateralToLoanValue(target.collateral, collateralPrice, oraclePriceScale);
    const extraCollateralValue = collateralToLoanValue(extra.extraCollateral, collateralPrice, oraclePriceScale);

    const currentNetValue = currentCollateralValue - currentBorrowAssets;
    const targetNetValue = targetCollateralValue - targetBorrowAssets;
    const extraProvidedValue = extra.extraLoanAssets + extraCollateralValue;
    const availableValue = currentNetValue + extraProvidedValue;
    const requiredValue = targetNetValue + extra.tokenTransferredBackToUser;

    return {
        borrowSharesDelta,
        repaySharesDelta,
        supplyCollateralDelta,
        withdrawCollateralDelta,
        borrowAssetsDelta,
        repayAssetsDelta,
        currentNetValue,
        targetNetValue,
        extraProvidedValue,
        expectedTokenTransferredBack: availableValue - targetNetValue,
        invariantHolds: availableValue >= requiredValue,
    };
}

function buildIncreaseBundle(
    addresses: AddressBook,
    marketParams: MarketParams,
    quote: Quote,
    extra: ExtraInputs,
    minBorrowSharePriceE27: bigint
): Call[] {
    if (quote.repayAssetsDelta !== 0n || quote.withdrawCollateralDelta !== 0n) {
        throw new Error("Increase route expects non-decreasing borrow and collateral.");
    }
    if (quote.borrowAssetsDelta === 0n) {
        throw new Error("Increase route requires a positive borrow delta (flash-loan backed shape).");
    }

    const adaptersAreShared = sameAddress(addresses.generalAdapter, addresses.nestAdapter);
    const nestExecutionAdapter = adaptersAreShared ? addresses.generalAdapter : addresses.nestAdapter;
    const params = deriveIncreaseParams(quote, extra, minBorrowSharePriceE27, adaptersAreShared);
    const callbackBundle: Call[] = [];

    if (params.flashLoanToNestAssets !== 0n && !adaptersAreShared) {
        callbackBundle.push(
            mkCall(
                addresses.generalAdapter,
                coreAdapterAbi.encodeFunctionData("erc20Transfer", [
                    marketParams.loanToken,
                    nestExecutionAdapter,
                    params.flashLoanToNestAssets.toString(),
                ])
            )
        );
    }

    if (params.depositAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                nestExecutionAdapter,
                nestAdapterAbi.encodeFunctionData("nestDeposit", [
                    addresses.vault,
                    params.depositAssets.toString(),
                    MAX_UINT256.toString(),
                    addresses.depositReceiver,
                ])
            )
        );
    }

    if (params.collateralFromInitiatorAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                addresses.generalAdapter,
                generalAdapterAbi.encodeFunctionData("erc20TransferFrom", [
                    marketParams.collateralToken,
                    addresses.generalAdapter,
                    params.collateralFromInitiatorAssets.toString(),
                ])
            )
        );
    }

    if (params.supplyCollateralAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                addresses.generalAdapter,
                generalAdapterAbi.encodeFunctionData("morphoSupplyCollateral", [
                    toMarketParamsTuple(marketParams),
                    params.supplyCollateralAssets.toString(),
                    addresses.initiator,
                    "0x",
                ])
            )
        );
    }

    if (params.borrowAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                addresses.generalAdapter,
                generalAdapterAbi.encodeFunctionData("morphoBorrow", [
                    toMarketParamsTuple(marketParams),
                    params.borrowAssets.toString(),
                    "0",
                    params.minBorrowSharePriceE27.toString(),
                    addresses.generalAdapter,
                ])
            )
        );
    }

    const callbackData = encodeCallArray(callbackBundle);
    const bundle: Call[] = [];
    if (params.extraLoanToNestAssets !== 0n) {
        bundle.push(
            mkCall(
                addresses.generalAdapter,
                generalAdapterAbi.encodeFunctionData("erc20TransferFrom", [
                    marketParams.loanToken,
                    nestExecutionAdapter,
                    params.extraLoanToNestAssets.toString(),
                ])
            )
        );
    }
    bundle.push(
        mkCall(
            addresses.generalAdapter,
            generalAdapterAbi.encodeFunctionData("morphoFlashLoan", [
                marketParams.loanToken,
                params.flashLoanAssets.toString(),
                callbackData,
            ]),
            ethers.utils.keccak256(callbackData)
        )
    );
    return bundle;
}

function buildDecreaseBundle(
    route: "decrease-instant" | "decrease-redeem",
    addresses: AddressBook,
    marketParams: MarketParams,
    quote: Quote,
    extra: ExtraInputs,
    maxRepaySharePriceE27: bigint
): Call[] {
    if (quote.borrowAssetsDelta !== 0n || quote.supplyCollateralDelta !== 0n) {
        throw new Error("Decrease route expects non-increasing borrow and collateral.");
    }
    if (quote.repayAssetsDelta === 0n) {
        throw new Error("Decrease route requires a positive repay delta (flash-loan backed shape).");
    }

    const params = deriveDecreaseParams(quote, extra, maxRepaySharePriceE27);
    const adaptersAreShared = sameAddress(addresses.generalAdapter, addresses.nestAdapter);
    const nestExecutionAdapter = adaptersAreShared ? addresses.generalAdapter : addresses.nestAdapter;
    const useSolverWithdrawCollateral =
        addresses.positionOwner.toLowerCase() !== addresses.initiator.toLowerCase();
    const callbackBundle: Call[] = [];

    callbackBundle.push(
        mkCall(
            addresses.generalAdapter,
            generalAdapterAbi.encodeFunctionData("morphoRepay", [
                toMarketParamsTuple(marketParams),
                params.repayAssets.toString(),
                "0",
                params.maxRepaySharePriceE27.toString(),
                addresses.positionOwner,
                "0x",
            ])
        )
    );

    if (params.withdrawCollateralAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                useSolverWithdrawCollateral ? nestExecutionAdapter : addresses.generalAdapter,
                useSolverWithdrawCollateral
                    ? nestAdapterAbi.encodeFunctionData("morphoWithdrawCollateralOnBehalf", [
                        toMarketParamsTuple(marketParams),
                        params.withdrawCollateralAssets.toString(),
                        addresses.positionOwner,
                        addresses.positionOwner,
                    ])
                    : generalAdapterAbi.encodeFunctionData("morphoWithdrawCollateral", [
                        toMarketParamsTuple(marketParams),
                        params.withdrawCollateralAssets.toString(),
                        addresses.initiator,
                    ])
            )
        );
    }

    if (params.redeemShares !== 0n) {
        callbackBundle.push(
            mkCall(
                nestExecutionAdapter,
                route === "decrease-instant"
                    ? nestAdapterAbi.encodeFunctionData("nestInstantRedeem", [
                      addresses.vault,
                      params.redeemShares.toString(),
                      "0",
                      addresses.redeemReceiver,
                      addresses.positionOwner,
                  ])
                : nestAdapterAbi.encodeFunctionData("nestRedeem", [
                      addresses.vault,
                      params.redeemShares.toString(),
                      "0",
                      addresses.redeemReceiver,
                      addresses.positionOwner,
                  ])
            )
        );
    }

    if (params.loanFromInitiatorAssets !== 0n) {
        callbackBundle.push(
            mkCall(
                addresses.generalAdapter,
                generalAdapterAbi.encodeFunctionData("erc20TransferFrom", [
                    marketParams.loanToken,
                    addresses.generalAdapter,
                    params.loanFromInitiatorAssets.toString(),
                ])
            )
        );
    }

    const callbackData = encodeCallArray(callbackBundle);
    return [
        mkCall(
            addresses.generalAdapter,
            generalAdapterAbi.encodeFunctionData("morphoFlashLoan", [
                marketParams.loanToken,
                params.flashLoanAssets.toString(),
                callbackData,
            ]),
            ethers.utils.keccak256(callbackData)
        ),
    ];
}

function deriveIncreaseParams(
    quote: Quote,
    extra: ExtraInputs,
    minBorrowSharePriceE27: bigint,
    adaptersAreShared: boolean
): IncreaseParams {
    const supplyCollateralAssets = quote.supplyCollateralDelta;
    const borrowAssets = quote.borrowAssetsDelta;
    const flashLoanAssets = borrowAssets;
    const depositAssets = supplyCollateralAssets > extra.extraCollateral
        ? supplyCollateralAssets - extra.extraCollateral
        : 0n;
    const requiredExtraLoanToNestAssets = depositAssets > flashLoanAssets ? depositAssets - flashLoanAssets : 0n;
    const extraLoanToNestAssets = min(extra.extraLoanAssets, requiredExtraLoanToNestAssets);
    const flashLoanToNestAssets = adaptersAreShared ? 0n : depositAssets - extraLoanToNestAssets;
    if (!adaptersAreShared && flashLoanToNestAssets > flashLoanAssets) {
        throw new Error(
            "Computed flashLoanToNestAssets exceeds flashLoanAssets. Increase extraLoanAssets or reduce target collateral."
        );
    }
    if (adaptersAreShared && depositAssets > flashLoanAssets + extraLoanToNestAssets) {
        throw new Error(
            "Computed depositAssets exceeds available adapter assets in shared-adapter mode. Increase extraLoanAssets or reduce target collateral."
        );
    }

    return {
        flashLoanAssets,
        flashLoanToNestAssets,
        extraLoanToNestAssets,
        depositAssets,
        collateralFromInitiatorAssets: supplyCollateralAssets,
        supplyCollateralAssets,
        borrowAssets,
        minBorrowSharePriceE27: minBorrowSharePriceE27 === 0n ? DEFAULT_MIN_BORROW_SHARE_PRICE_E27 : minBorrowSharePriceE27,
    };
}

function deriveDecreaseParams(
    quote: Quote,
    extra: ExtraInputs,
    maxRepaySharePriceE27: bigint
): DecreaseParams {
    const repayAssets = quote.repayAssetsDelta;
    const flashLoanAssets = repayAssets;
    const loanFromInitiatorAssets = flashLoanAssets;

    const redeemShares = loanFromInitiatorAssets > extra.extraLoanAssets
        ? loanFromInitiatorAssets - extra.extraLoanAssets
        : 0n;
    const availableSharesForRedeem = quote.withdrawCollateralDelta + extra.extraCollateral;
    if (redeemShares > availableSharesForRedeem) {
        throw new Error(
            "Not enough shares for redeem to refill flash-loan payback. Increase extraLoanAssets or extraSharesSupplied."
        );
    }
    if (redeemShares > repayAssets + extra.extraCollateral) {
        throw new Error(
            "Decrease route would reduce net vault-share exposure (redeemShares > repayAssets + extraSharesSupplied)."
        );
    }

    return {
        flashLoanAssets,
        repayAssets,
        maxRepaySharePriceE27: maxRepaySharePriceE27 === 0n ? DEFAULT_MAX_REPAY_SHARE_PRICE_E27 : maxRepaySharePriceE27,
        withdrawCollateralAssets: quote.withdrawCollateralDelta,
        redeemShares,
        loanFromInitiatorAssets,
    };
}

function encodeCallArray(calls: Call[]): Hex {
    return ethers.utils.defaultAbiCoder.encode(
        [CALL_TUPLE_ARRAY_TYPE],
        [toAbiCalls(calls)]
    );
}

function toAbiCalls(calls: Call[]): Array<[string, string, string, boolean, string]> {
    return calls.map((call) => [
        call.to,
        call.data,
        call.value.toString(),
        call.skipRevert,
        call.callbackHash,
    ]);
}

function mkCall(to: string, data: Hex, callbackHash: Hex = ZERO_HASH): Call {
    return {
        to,
        data,
        value: 0n,
        skipRevert: false,
        callbackHash,
    };
}

function computeMarketId(marketParams: MarketParams): Hex {
    const encoded = ethers.utils.defaultAbiCoder.encode(
        ["tuple(address loanToken,address collateralToken,address oracle,address irm,uint256 lltv)"],
        [toMarketParamsTuple(marketParams)]
    );
    return ethers.utils.keccak256(encoded);
}

function toMarketParamsTuple(marketParams: MarketParams): {
    loanToken: string;
    collateralToken: string;
    oracle: string;
    irm: string;
    lltv: string;
} {
    return {
        loanToken: marketParams.loanToken,
        collateralToken: marketParams.collateralToken,
        oracle: marketParams.oracle,
        irm: marketParams.irm,
        lltv: marketParams.lltv.toString(),
    };
}

function toAssetsUp(shares: bigint, totalAssets: bigint, totalShares: bigint): bigint {
    if (shares === 0n) return 0n;
    return mulDivUp(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
}

function collateralToLoanValue(collateral: bigint, price: bigint, scale: bigint): bigint {
    if (collateral === 0n || price === 0n) return 0n;
    return (collateral * price) / scale;
}

function mulDivUp(x: bigint, y: bigint, d: bigint): bigint {
    if (d === 0n) throw new Error("Division by zero.");
    return (x * y + (d - 1n)) / d;
}

function printSummary(
    route: Route,
    configPath: string,
    parsed: {
        expectedMarketId?: Hex;
        addresses: AddressBook;
        marketParams: MarketParams;
        targetPosition: Position;
        extraInputs: ExtraInputs;
        collateralPrice: bigint;
        oraclePriceScale: bigint;
    },
    currentPosition: Position,
    marketState: MarketState,
    quote: Quote
): void {
    const marketId = computeMarketId(parsed.marketParams);
    console.log(`route: ${route}`);
    console.log(`config: ${configPath}`);
    console.log(`marketId: ${marketId}`);
    if (parsed.expectedMarketId !== undefined) {
        console.log(`expectedMarketId: ${parsed.expectedMarketId}`);
    }
    console.log(`initiator: ${parsed.addresses.initiator}`);
    console.log(`positionOwner: ${parsed.addresses.positionOwner}`);
    console.log(`depositReceiver: ${parsed.addresses.depositReceiver}`);
    console.log(`redeemReceiver: ${parsed.addresses.redeemReceiver}`);
    console.log("");
    console.log("positions:");
    console.log(`  current.borrowShares: ${currentPosition.borrowShares.toString()}`);
    console.log(`  current.collateral: ${currentPosition.collateral.toString()}`);
    console.log(`  target.borrowShares: ${parsed.targetPosition.borrowShares.toString()}`);
    console.log(`  target.collateral: ${parsed.targetPosition.collateral.toString()}`);
    console.log("");
    console.log("market:");
    console.log(`  totalBorrowAssets: ${marketState.totalBorrowAssets.toString()}`);
    console.log(`  totalBorrowShares: ${marketState.totalBorrowShares.toString()}`);
    console.log(`  collateralPrice: ${parsed.collateralPrice.toString()}`);
    console.log(`  oraclePriceScale: ${parsed.oraclePriceScale.toString()}`);
    console.log("");
    console.log("extras:");
    console.log(`  extraLoanAssets: ${parsed.extraInputs.extraLoanAssets.toString()}`);
    console.log(`  extraCollateral(extraSharesSupplied): ${parsed.extraInputs.extraCollateral.toString()}`);
    console.log(`  tokenTransferredBackToUser(input): ${parsed.extraInputs.tokenTransferredBackToUser.toString()}`);
    console.log("");
    console.log("quote:");
    console.log(`  borrowSharesDelta: ${quote.borrowSharesDelta.toString()}`);
    console.log(`  repaySharesDelta: ${quote.repaySharesDelta.toString()}`);
    console.log(`  borrowAssetsDelta: ${quote.borrowAssetsDelta.toString()}`);
    console.log(`  repayAssetsDelta: ${quote.repayAssetsDelta.toString()}`);
    console.log(`  supplyCollateralDelta: ${quote.supplyCollateralDelta.toString()}`);
    console.log(`  withdrawCollateralDelta: ${quote.withdrawCollateralDelta.toString()}`);
    console.log(`  expectedTokenTransferredBack: ${quote.expectedTokenTransferredBack.toString()}`);
    console.log(`  invariantHolds(with provided tokenTransferredBack): ${quote.invariantHolds}`);
}

function printBundle(route: Route, bundle: Call[], addresses: AddressBook, marketParams: MarketParams): void {
    console.log("");
    console.log(`bundle.calls (${route}):`);

    bundle.forEach((call, index) => {
        const decoded = decodeCall(call, addresses, marketParams);
        console.log(
            `  [${index}] ${decoded.summary} value=${call.value.toString()} skipRevert=${call.skipRevert} callbackHash=${call.callbackHash}`
        );

        if (decoded.callbackData !== undefined) {
            const callbackCalls = ethers.utils.defaultAbiCoder.decode([CALL_TUPLE_ARRAY_TYPE], decoded.callbackData)[0] as Array<{
                to: string;
                data: string;
                value: ethers.BigNumber;
                skipRevert: boolean;
                callbackHash: string;
            }>;

            callbackCalls.forEach((nested, nestedIndex) => {
                const nestedCall: Call = {
                    to: nested.to,
                    data: nested.data,
                    value: bnToBigInt(nested.value),
                    skipRevert: nested.skipRevert,
                    callbackHash: nested.callbackHash,
                };
                const nestedDecoded = decodeCall(nestedCall, addresses, marketParams);
                console.log(
                    `    [cb:${nestedIndex}] ${nestedDecoded.summary} value=${nestedCall.value.toString()} skipRevert=${nestedCall.skipRevert} callbackHash=${nestedCall.callbackHash}`
                );
            });
        }
    });
}

function decodeCall(
    call: Call,
    addresses: AddressBook,
    marketParams: MarketParams
): { summary: string; callbackData?: string } {
    const parsedGeneral = tryParseCall(generalAdapterAbi, call.data);
    if (parsedGeneral) {
        if (parsedGeneral.name === "erc20TransferFrom") {
            const [token, receiver, amount] = parsedGeneral.args as [string, string, ethers.BigNumber];
            return {
                summary: `${labelAddress(call.to, addresses)}.erc20TransferFrom(token=${labelToken(token, marketParams)}, receiver=${labelAddress(receiver, addresses)}, amount=${amount.toString()})`,
            };
        }
        if (parsedGeneral.name === "morphoFlashLoan") {
            const [token, assets, callbackData] = parsedGeneral.args as [string, ethers.BigNumber, string];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoFlashLoan(token=${labelToken(token, marketParams)}, assets=${assets.toString()})`,
                callbackData,
            };
        }
        if (parsedGeneral.name === "morphoSupplyCollateral") {
            const [market, assets, onBehalf] = parsedGeneral.args as [
                { loanToken: string; collateralToken: string; oracle: string; irm: string; lltv: ethers.BigNumber },
                ethers.BigNumber,
                string,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoSupplyCollateral(${formatMarketParams(market)}, assets=${assets.toString()}, onBehalf=${labelAddress(onBehalf, addresses)})`,
            };
        }
        if (parsedGeneral.name === "morphoBorrow") {
            const [market, assets, shares, minSharePriceE27, receiver] = parsedGeneral.args as [
                { loanToken: string; collateralToken: string; oracle: string; irm: string; lltv: ethers.BigNumber },
                ethers.BigNumber,
                ethers.BigNumber,
                ethers.BigNumber,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoBorrow(${formatMarketParams(market)}, assets=${assets.toString()}, shares=${shares.toString()}, minSharePriceE27=${minSharePriceE27.toString()}, receiver=${labelAddress(receiver, addresses)})`,
            };
        }
        if (parsedGeneral.name === "morphoRepay") {
            const [market, assets, shares, maxSharePriceE27, onBehalf] = parsedGeneral.args as [
                { loanToken: string; collateralToken: string; oracle: string; irm: string; lltv: ethers.BigNumber },
                ethers.BigNumber,
                ethers.BigNumber,
                ethers.BigNumber,
                string,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoRepay(${formatMarketParams(market)}, assets=${assets.toString()}, shares=${shares.toString()}, maxSharePriceE27=${maxSharePriceE27.toString()}, onBehalf=${labelAddress(onBehalf, addresses)})`,
            };
        }
        if (parsedGeneral.name === "morphoWithdrawCollateral") {
            const [market, assets, receiver] = parsedGeneral.args as [
                { loanToken: string; collateralToken: string; oracle: string; irm: string; lltv: ethers.BigNumber },
                ethers.BigNumber,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoWithdrawCollateral(${formatMarketParams(market)}, assets=${assets.toString()}, receiver=${labelAddress(receiver, addresses)})`,
            };
        }
        return { summary: `${labelAddress(call.to, addresses)}.${parsedGeneral.name}(...)` };
    }

    const parsedCore = tryParseCall(coreAdapterAbi, call.data);
    if (parsedCore?.name === "erc20Transfer") {
        const [token, receiver, amount] = parsedCore.args as [string, string, ethers.BigNumber];
        return {
            summary: `${labelAddress(call.to, addresses)}.erc20Transfer(token=${labelToken(token, marketParams)}, receiver=${labelAddress(receiver, addresses)}, amount=${amount.toString()})`,
        };
    }

    const parsedNest = tryParseCall(nestAdapterAbi, call.data);
    if (parsedNest) {
        if (parsedNest.name === "nestDeposit") {
            const [vault, assets, maxSharePriceE27, receiver] = parsedNest.args as [
                string,
                ethers.BigNumber,
                ethers.BigNumber,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.nestDeposit(vault=${labelAddress(vault, addresses)}, assets=${assets.toString()}, maxSharePriceE27=${maxSharePriceE27.toString()}, receiver=${labelAddress(receiver, addresses)})`,
            };
        }
        if (parsedNest.name === "nestInstantRedeem") {
            const [vault, shares, minSharePriceE27, receiver, owner] = parsedNest.args as [
                string,
                ethers.BigNumber,
                ethers.BigNumber,
                string,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.nestInstantRedeem(vault=${labelAddress(vault, addresses)}, shares=${shares.toString()}, minSharePriceE27=${minSharePriceE27.toString()}, receiver=${labelAddress(receiver, addresses)}, owner=${labelAddress(owner, addresses)})`,
            };
        }
        if (parsedNest.name === "nestRedeem") {
            const [vault, shares, minSharePriceE27, receiver, owner] = parsedNest.args as [
                string,
                ethers.BigNumber,
                ethers.BigNumber,
                string,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.nestRedeem(vault=${labelAddress(vault, addresses)}, shares=${shares.toString()}, minSharePriceE27=${minSharePriceE27.toString()}, receiver=${labelAddress(receiver, addresses)}, owner=${labelAddress(owner, addresses)})`,
            };
        }
        if (parsedNest.name === "morphoWithdrawCollateralOnBehalf") {
            const [market, assets, onBehalf, receiver] = parsedNest.args as [
                { loanToken: string; collateralToken: string; oracle: string; irm: string; lltv: ethers.BigNumber },
                ethers.BigNumber,
                string,
                string
            ];
            return {
                summary: `${labelAddress(call.to, addresses)}.morphoWithdrawCollateralOnBehalf(${formatMarketParams(market)}, assets=${assets.toString()}, onBehalf=${labelAddress(onBehalf, addresses)}, receiver=${labelAddress(receiver, addresses)})`,
            };
        }
        return { summary: `${labelAddress(call.to, addresses)}.${parsedNest.name}(...)` };
    }

    return {
        summary: `${labelAddress(call.to, addresses)}.unknown(selector=${selector(call.data)}, data=${truncateHex(call.data, 26)})`,
    };
}

function tryParseCall(iface: ethers.utils.Interface, data: string): ethers.utils.TransactionDescription | undefined {
    try {
        return iface.parseTransaction({ data });
    } catch {
        return undefined;
    }
}

function labelAddress(address: string, addresses: AddressBook): string {
    const isGeneralAdapter = sameAddress(address, addresses.generalAdapter);
    const isNestAdapter = sameAddress(address, addresses.nestAdapter);
    if (isGeneralAdapter && isNestAdapter) return `Adapter(general+nest)(${address})`;
    if (isGeneralAdapter) return `GeneralAdapter1(${address})`;
    if (isNestAdapter) return `NestAdapter(${address})`;
    if (sameAddress(address, addresses.morpho)) return `Morpho(${address})`;
    if (sameAddress(address, addresses.vault)) return `NestVault(${address})`;
    if (sameAddress(address, addresses.bundler)) return `Bundler3(${address})`;
    if (sameAddress(address, addresses.initiator)) return `Initiator(${address})`;
    if (sameAddress(address, addresses.positionOwner)) return `PositionOwner(${address})`;
    if (sameAddress(address, addresses.depositReceiver)) return `DepositReceiver(${address})`;
    if (sameAddress(address, addresses.redeemReceiver)) return `RedeemReceiver(${address})`;
    return address;
}

function labelToken(address: string, marketParams: MarketParams): string {
    if (address.toLowerCase() === marketParams.loanToken.toLowerCase()) return `loanToken(${address})`;
    if (address.toLowerCase() === marketParams.collateralToken.toLowerCase()) return `collateralToken(${address})`;
    return address;
}

function formatMarketParams(market: {
    loanToken: string;
    collateralToken: string;
    oracle: string;
    irm: string;
    lltv: ethers.BigNumber;
}): string {
    return `market(loanToken=${market.loanToken}, collateralToken=${market.collateralToken}, oracle=${market.oracle}, irm=${market.irm}, lltv=${market.lltv.toString()})`;
}

function selector(data: string): string {
    return data.slice(0, 10);
}

function truncateHex(value: string, maxLength: number): string {
    if (value.length <= maxLength) return value;
    return `${value.slice(0, maxLength)}...`;
}

function normalizeAddress(value: string): string {
    return ethers.utils.getAddress(value);
}

function sameAddress(a: string, b: string): boolean {
    return a.toLowerCase() === b.toLowerCase();
}

function parseOptionalBytes32(value: string | undefined, fieldName: string): Hex | undefined {
    if (value === undefined) return undefined;
    if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
        throw new Error(`Invalid bytes32 value for ${fieldName}: ${value}`);
    }
    return value.toLowerCase();
}

function bi(value: string | number | bigint, fieldName: string): bigint {
    try {
        if (typeof value === "bigint") return value;
        if (typeof value === "number") {
            if (!Number.isSafeInteger(value) || value < 0) throw new Error("unsafe integer");
            return BigInt(value);
        }
        const normalized = value.trim();
        if (normalized.startsWith("-")) throw new Error("negative values are not supported");
        return BigInt(normalized);
    } catch {
        throw new Error(`Invalid bigint value for ${fieldName}: ${String(value)}`);
    }
}

function bnToBigInt(value: ethers.BigNumber): bigint {
    return BigInt(value.toString());
}

function min(a: bigint, b: bigint): bigint {
    return a < b ? a : b;
}
