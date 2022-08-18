// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {OwnableUpgradeable} from "../dependencies/openzeppelin/contracts/proxy/OwnableUpgradeable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {ReserveConfiguration} from "../protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {DataTypesHelper} from "./libraries/DataTypesHelper.sol";

// ERC721 imports
import {IERC721} from "../dependencies/openzeppelin/contracts/IERC721.sol";
import {IERC721Receiver} from "../dependencies/openzeppelin/contracts/IERC721Receiver.sol";
import {IPunks} from "../misc/interfaces/IPunks.sol";
import {IWrappedPunks} from "../misc/interfaces/IWrappedPunks.sol";
import {IWPunkGateway} from "./interfaces/IWPunkGateway.sol";
import {INToken} from "../interfaces/INToken.sol";
import {ReentrancyGuard} from "../dependencies/openzeppelin/contracts/ReentrancyGuard.sol";

contract WPunkGateway is
    ReentrancyGuard,
    IWPunkGateway,
    IERC721Receiver,
    OwnableUpgradeable
{
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    IPunks internal immutable Punk;
    IWrappedPunks internal immutable WPunk;
    IPool internal immutable Pool;
    address public proxy;

    address public immutable punk;
    address public immutable wpunk;
    address public immutable pool;

    /**
     * @dev Sets the WETH address and the PoolAddressesProvider address. Infinite approves pool.
     * @param _punk Address of the Punk contract
     * @param _wpunk Address of the Wrapped Punk contract
     * @param _pool Address of the proxy pool of this contract
     **/
    constructor(
        address _punk,
        address _wpunk,
        address _pool
    ) {
        punk = _punk;
        wpunk = _wpunk;
        pool = _pool;

        Punk = IPunks(punk);
        WPunk = IWrappedPunks(wpunk);
        Pool = IPool(pool);
    }

    function initialize() external initializer {
        __Ownable_init();

        // create new WPunk Proxy for PunkGateway contract
        WPunk.registerProxy();

        // address(this) = WPunkGatewayProxy
        // proxy of PunkGateway contract is the new Proxy created above
        proxy = WPunk.proxyInfo(address(this));

        WPunk.setApprovalForAll(pool, true);
    }

    /**
     * @dev supplies (deposits) WPunk into the reserve, using native Punk. A corresponding amount of the overlying asset (xTokens)
     * is minted.
     * @param pool address of the targeted underlying pool
     * @param punkIndexes punkIndexes to supply to gateway
     * @param onBehalfOf address of the user who will receive the xTokens representing the supply
     * @param referralCode integrators are assigned a referral code and can potentially receive rewards.
     **/
    function supplyPunk(
        address pool,
        DataTypes.ERC721SupplyParams[] calldata punkIndexes,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        for (uint256 i = 0; i < punkIndexes.length; i++) {
            Punk.buyPunk(punkIndexes[i].tokenId);
            Punk.transferPunk(proxy, punkIndexes[i].tokenId);
            // gatewayProxy is the sender of this function, not the original gateway
            WPunk.mint(punkIndexes[i].tokenId);
        }

        Pool.supplyERC721(
            address(WPunk),
            punkIndexes,
            onBehalfOf,
            referralCode
        );
    }

    /**
     * @dev withdraws the WPUNK _reserves of msg.sender.
     * @param pool address of the targeted underlying pool
     * @param punkIndexes indexes of nWPunks to withdraw and receive native WPunk
     * @param to address of the user who will receive native Punks
     */
    function withdrawPunk(
        address pool,
        uint256[] calldata punkIndexes,
        address to
    ) external {
        INToken nWPunk = INToken(
            Pool.getReserveData(address(WPunk)).xTokenAddress
        );
        for (uint256 i = 0; i < punkIndexes.length; i++) {
            nWPunk.safeTransferFrom(msg.sender, address(this), punkIndexes[i]);
        }
        Pool.withdrawERC721(address(WPunk), punkIndexes, address(this));
        for (uint256 i = 0; i < punkIndexes.length; i++) {
            WPunk.burn(punkIndexes[i]);
            Punk.transferPunk(to, punkIndexes[i]);
        }
    }

    function acceptBidWithCredit(
        bytes32 marketplaceId,
        bytes calldata data,
        DataTypes.Credit calldata credit,
        uint256[] calldata punkIndexes,
        uint16 referralCode
    ) external nonReentrant {
        for (uint256 i = 0; i < punkIndexes.length; i++) {
            Punk.buyPunk(punkIndexes[i]);
            Punk.transferPunk(proxy, punkIndexes[i]);
            // gatewayProxy is the sender of this function, not the original gateway
            WPunk.mint(punkIndexes[i]);

            IERC721(address(WPunk)).safeTransferFrom(
                address(this),
                msg.sender,
                punkIndexes[i]
            );
            IERC721(address(WPunk)).approve(address(Pool), punkIndexes[i]);
        }
        Pool.acceptBidWithCredit(
            marketplaceId,
            data,
            credit,
            msg.sender,
            referralCode
        );
    }

    // // gives app permission to withdraw n token
    // // permitV, permitR, permitS. passes signature parameters
    // /**
    //  * @dev withdraws the WPUNK _reserves of msg.sender.
    //  * @param pool address of the targeted underlying pool
    //  * @param punkIndexes punkIndexes of nWPunks to withdraw and receive native WPunk
    //  * @param to address of the user who will receive native Punks
    //  * @param deadline validity deadline of permit and so depositWithPermit signature
    //  * @param permitV V parameter of ERC712 permit sig
    //  * @param permitR R parameter of ERC712 permit sig
    //  * @param permitS S parameter of ERC712 permit sig
    //  */
    // function withdrawPunkWithPermit(
    //     address pool,
    //     uint256[] calldata punkIndexes,
    //     address to,
    //     uint256 deadline,
    //     uint8 permitV,
    //     bytes32 permitR,
    //     bytes32 permitS
    // ) external override {
    //     INToken nWPunk = INToken(
    //         Pool.getReserveData(address(WPunk)).xTokenAddress
    //     );

    //     for (uint256 i = 0; i < punkIndexes.length; i++) {
    //         nWPunk.permit(
    //             msg.sender,
    //             address(this),
    //             punkIndexes[i],
    //             deadline,
    //             permitV,
    //             permitR,
    //             permitS
    //         );
    //         nWPunk.safeTransferFrom(msg.sender, address(this), punkIndexes[i]);
    //     }
    //     Pool.withdrawERC721(address(WPunk), punkIndexes, address(this));
    //     for (uint256 i = 0; i < punkIndexes.length; i++) {
    //         WPunk.burn(punkIndexes[i]);
    //         Punk.transferPunk(to, punkIndexes[i]);
    //     }
    // }

    /**
     * @dev transfer ERC721 from the utility contract, for ERC721 recovery in case of stuck tokens due
     * direct transfers to the contract address.
     * @param from punk owner of the transfer
     * @param to recipient of the transfer
     * @param tokenId tokenId to send
     */
    function emergencyTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyOwner {
        IERC721(address(WPunk)).safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev transfer native Punk from the utility contract, for native Punk recovery in case of stuck Punk
     * due selfdestructs or transfer punk to pre-computated contract address before deployment.
     * @param to recipient of the transfer
     * @param punkIndex punk to send
     */
    function emergencyPunkTransfer(address to, uint256 punkIndex)
        external
        onlyOwner
    {
        Punk.transferPunk(to, punkIndex);
    }

    /**
     * @dev Get WPunk address used by WPunkGateway
     */
    function getWPunkAddress() external view returns (address) {
        return address(WPunk);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
