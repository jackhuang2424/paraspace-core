import {ZERO_ADDRESS} from "../../../helpers/constants";
import {
  deployMockBendDaoLendPool,
  deployPoolComponents,
  deployPoolParaProxyInterfaces,
  deployPoolPositionMover,
} from "../../../helpers/contracts-deployments";
import {
  getPoolProxy,
  getPoolAddressesProvider,
  getAutoCompoundApe,
  getAllTokens,
  getUniswapV3SwapRouter,
  getWETH,
} from "../../../helpers/contracts-getters";
import {
  getContractAddressInDb,
  registerContractInDb,
} from "../../../helpers/contracts-helpers";
import {GLOBAL_OVERRIDES} from "../../../helpers/hardhat-constants";
import {
  getParaSpaceConfig,
  isLocalTestnet,
  waitForTx,
} from "../../../helpers/misc-utils";
import {eContractid, ERC20TokenContractId} from "../../../helpers/types";

export const step_06 = async (verify = false) => {
  const addressesProvider = await getPoolAddressesProvider();
  const paraSpaceConfig = getParaSpaceConfig();

  try {
    const {
      poolCore,
      poolParameters,
      poolMarketplace,
      poolApeStaking,
      poolCoreSelectors,
      poolParametersSelectors,
      poolMarketplaceSelectors,
      poolApeStakingSelectors,
    } = await deployPoolComponents(addressesProvider.address, verify);

    const {poolParaProxyInterfaces, poolParaProxyInterfacesSelectors} =
      await deployPoolParaProxyInterfaces(verify);

    await waitForTx(
      await addressesProvider.updatePoolImpl(
        [
          {
            implAddress: poolParameters.address,
            action: 0,
            functionSelectors: poolParametersSelectors,
          },
        ],
        ZERO_ADDRESS,
        "0x",
        GLOBAL_OVERRIDES
      )
    );

    await waitForTx(
      await addressesProvider.updatePoolImpl(
        [
          {
            implAddress: poolMarketplace.address,
            action: 0,
            functionSelectors: poolMarketplaceSelectors,
          },
        ],
        ZERO_ADDRESS,
        "0x",
        GLOBAL_OVERRIDES
      )
    );

    if (paraSpaceConfig.BendDAO.LendingPoolLoan || isLocalTestnet()) {
      const bendDaoLendPoolLoan =
        paraSpaceConfig.BendDAO.LendingPoolLoan ||
        (await getContractAddressInDb(eContractid.MockBendDaoLendPool)) ||
        (await deployMockBendDaoLendPool((await getWETH()).address)).address;
      const bendDaoLendPool =
        paraSpaceConfig.BendDAO.LendingPool ||
        (await getContractAddressInDb(eContractid.MockBendDaoLendPool)) ||
        (await deployMockBendDaoLendPool((await getWETH()).address)).address;
      const {poolPositionMover, poolPositionMoverSelectors} =
        await deployPoolPositionMover(
          addressesProvider.address,
          bendDaoLendPoolLoan,
          bendDaoLendPool,
          verify
        );

      await waitForTx(
        await addressesProvider.updatePoolImpl(
          [
            {
              implAddress: poolPositionMover.address,
              action: 0,
              functionSelectors: poolPositionMoverSelectors,
            },
          ],
          ZERO_ADDRESS,
          "0x",
          GLOBAL_OVERRIDES
        )
      );
    }

    if (poolApeStaking) {
      await waitForTx(
        await addressesProvider.updatePoolImpl(
          [
            {
              implAddress: poolApeStaking.address,
              action: 0,
              functionSelectors: poolApeStakingSelectors,
            },
          ],
          ZERO_ADDRESS,
          "0x",
          GLOBAL_OVERRIDES
        )
      );
    }

    const poolAddress = await addressesProvider.getPool();

    await waitForTx(
      await addressesProvider.updatePoolImpl(
        [
          {
            implAddress: poolCore.address,
            action: 0,
            functionSelectors: poolCoreSelectors,
          },
        ],
        poolAddress,
        poolCore.interface.encodeFunctionData("initialize", [
          addressesProvider.address,
        ]),
        GLOBAL_OVERRIDES
      )
    );

    await waitForTx(
      await addressesProvider.updatePoolImpl(
        [
          {
            implAddress: poolParaProxyInterfaces.address,
            action: 0,
            functionSelectors: poolParaProxyInterfacesSelectors,
          },
        ],
        ZERO_ADDRESS,
        "0x",
        GLOBAL_OVERRIDES
      )
    );

    const poolProxy = await getPoolProxy(poolAddress);
    const uniswapV3Router = await getUniswapV3SwapRouter();
    const allTokens = await getAllTokens();

    if (allTokens[ERC20TokenContractId.APE]) {
      const cAPE = await getAutoCompoundApe();
      await waitForTx(
        await poolProxy.unlimitedApproveTo(
          allTokens[ERC20TokenContractId.APE].address,
          uniswapV3Router.address
        )
      );
      await waitForTx(
        await poolProxy.unlimitedApproveTo(
          allTokens[ERC20TokenContractId.APE].address,
          cAPE.address
        )
      );
    }

    await registerContractInDb(eContractid.PoolProxy, poolProxy, [
      addressesProvider.address,
    ]);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
};
