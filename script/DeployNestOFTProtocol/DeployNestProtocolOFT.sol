// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "../BaseL0Script.sol";
import {ICreateX} from "createx/ICreateX.sol";

import {SetDVNs} from "script/DeployNestOFTProtocol/inherited/SetDVNs.sol";

/// @title DeployNestProtocolOFT
/// @notice Base deployment script for Nest Protocol OFT (Omnichain Fungible Token) contracts
/// @dev Abstract contract that provides the foundational deployment and configuration logic for NestVaultOFT and NestShareOFT.
///      Inherits from SetDVNs for DVN configuration and BaseL0Script for LayerZero configuration.
///
///      Inheritance hierarchy:
///      - DeployNestProtocolOFT (this contract)
///        ├── DeployNestVaultOFT - for vault-backed OFTs
///        │   └── Concrete deployment scripts (e.g., DeployNestVaultOFT_nTEST_USDC)
///        └── DeployNestShareOFT - for share-based OFTs
///
///      Key functions to override in child contracts:
///      - deployOFTs(): Deploy the specific OFT contracts
///      - postDeployChecks(): Validate deployment state
///      - setupSource(): Configure the source chain
abstract contract DeployNestProtocolOFT is SetDVNs, BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    ICreateX public immutable CREATEX;

    constructor() {
        CREATEX = ICreateX(vm.envAddress("CREATEX"));
    }

    function version() public pure virtual override returns (uint256, uint256, uint256) {
        return (0, 0, 1);
    }

    function setUp() public virtual override {
        super.setUp();
    }

    function run() public virtual {
        deploySource();
        setupSource();
        setupDestinations();
    }

    function deploySource() public {
        preDeployChecks();
        deployOFTs();
        postDeployChecks();
    }

    function preDeployChecks() public view {
        // for (uint256 e = 0; e < allConfigs.length; e++) {
        //     uint32 eid = uint32(allConfigs[e].eid);
        //     require(
        //         IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
        //         "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
        //     );
        // }
    }

    function deployOFTs() public virtual;

    function postDeployChecks() internal view virtual;

    function setupDestinations() public {
        setupProxyDestinations();
    }

    function setupProxyDestinations() public virtual {
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == broadcastConfig.eid) continue;
            setupDestination({_connectedConfig: proxyConfigs[i]});
        }
    }

    function setupDestination(L0Config memory _connectedConfig) public virtual;

    function setupSource() public virtual;

    /// @dev Overloaded function that accepts single L0Config for destination chains
    function setDVNs(L0Config memory _connectedConfig, address[] memory _connectedOfts, L0Config memory _config)
        public
    {
        L0Config[] memory configs = new L0Config[](1);
        configs[0] = _config;
        setDVNs(_connectedConfig, _connectedOfts, configs);
    }

    /// @dev Overloaded function that accepts single L0Config for destination chains
    function setLibs(L0Config memory _connectedConfig, address[] memory _connectedOfts, L0Config memory _config)
        public
    {
        L0Config[] memory configs = new L0Config[](1);
        configs[0] = _config;
        setLibs(_connectedConfig, _connectedOfts, configs);
    }

    /// @dev Overloaded function that accepts single L0Config
    function setEvmPeers(address[] memory _connectedOfts, address[] memory _peerOfts, L0Config memory _config) public {
        L0Config[] memory configs = new L0Config[](1);
        configs[0] = _config;
        setEvmPeers(_connectedOfts, _peerOfts, configs);
    }

    /// @dev _connectedOfts refers to the OFTs of the RPC we are currently connected to
    function setEvmPeers(address[] memory _connectedOfts, address[] memory _peerOfts, L0Config[] memory _configs)
        public
    {
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // Set the config per chain
        for (uint256 c = 0; c < _configs.length; c++) {
            for (uint256 d = 0; d < _configs[c].assets.length; d++) {
                for (uint256 o = 0; o < _connectedOfts.length; o++) {
                    address peerOft =
                        determinePeer({_chainid: _configs[c].chainid, _oft: _peerOfts[o], _peerOfts: _peerOfts});
                    setPeer({
                        _config: _configs[c],
                        _connectedOft: _connectedOfts[o],
                        _peerOftAsBytes32: addressToBytes32(peerOft)
                    });
                }
            }
        }
    }

    // Determines the peer OFT address by mapping against known OFT addresses
    function determinePeer(uint256 _chainid, address _oft, address[] memory _peerOfts)
        public
        view
        returns (address peer)
    {
        peer = getPeerFromArray({_oft: _oft, _oftArray: _peerOfts});
        require(peer != address(0), "Invalid proxy peer");
    }

    /// @dev Maps OFT to peer based on known NestVaultOFT addresses (nALPHA, nBASIS, nOPAL, nTBILL, nWISDOM)
    function getPeerFromArray(address _oft, address[] memory _oftArray) public view virtual returns (address peer) {
        require(_oftArray.length == 5, "getPeerFromArray index mismatch");
        require(_oft != address(0), "getPeerFromArray() OFT == address(0)");
        /// @dev maintains array from deployNestVaultOFTs(), where nestVaultOFTs is pushed to in the respective order
        peer = _oftArray[0];
        if (_oft == nALPHAVaultOFT_USDC) {
            peer = _oftArray[0];
        } else if (_oft == nBASISVaultOFT_USDC) {
            peer = _oftArray[1];
        } else if (_oft == nOPALVaultOFT_USDC) {
            peer = _oftArray[2];
        } else if (_oft == nTBILLVaultOFT_USDC) {
            peer = _oftArray[3];
        } else if (_oft == nWISDOMVaultOFT_USDC) {
            peer = _oftArray[4];
        }
    }

    // Simplified peer lookup for testnet with single OFT
    function getTestnetPeerFromArray(address _oft, address[] memory _oftArray) public view returns (address peer) {
        require(_oftArray.length == 1, "getPeerFromTestnetArray index mismatch");
        require(_oft != address(0), "getPeerFromTestnetArray() OFT == address(0)");
        peer = _oftArray[0];
    }

    /// @dev Non-evm OFTs require their own unique peer address
    function setNonEvmPeers(address[] memory _connectedOfts) public virtual {
        /*
         * Set the peer for each non-EVM config and each connected OFT.
         * _nonEvmPeersArrays is a flat array of NonEvmPeer loaded from NonEvmPeers.json.
         * Each NonEvmPeer has an eid field to map to the correct nonEvmConfig (from L0Config.json#Non-EVM).
         * This enables robust, order-independent mapping between config and peer.
         */
        for (uint256 c = 0; c < nonEvmConfigs.length; c++) {
            uint32 eid = uint32(nonEvmConfigs[c].eid);
            uint256 peerCount = 0;
            for (uint256 i = 0; i < _nonEvmPeersArrays.length; i++) {
                if (_nonEvmPeersArrays[i].eid == eid) {
                    if (peerCount < _connectedOfts.length) {
                        setPeer({
                            _config: nonEvmConfigs[c],
                            _connectedOft: _connectedOfts[peerCount],
                            _peerOftAsBytes32: _nonEvmPeersArrays[i].addressBytes32
                        });
                        peerCount++;
                    }
                }
            }
        }
    }

    function setPeer(L0Config memory _config, address _connectedOft, bytes32 _peerOftAsBytes32) public {
        // cannot set peer to self
        if (block.chainid == _config.chainid) return;

        bytes memory data = abi.encodeCall(IOAppCore.setPeer, (uint32(_config.eid), _peerOftAsBytes32));
        (bool success,) = _connectedOft.call(data);
        require(success, "Unable to setPeer");
        pushSerializedTx({_name: "setPeer", _to: _connectedOft, _value: 0, _data: data});
    }

    // Overloaded function that accepts single L0Config
    function setEvmEnforcedOptions(address[] memory _connectedOfts, L0Config memory _config) public {
        L0Config[] memory configs = new L0Config[](1);
        configs[0] = _config;
        setEvmEnforcedOptions(_connectedOfts, configs);
    }

    function setEvmEnforcedOptions(address[] memory _connectedOfts, L0Config[] memory _configs) public {
        // For each peer, default
        // https://github.com/LayerZero-Labs/LayerZero-v2/blob/ab9b083410b9359285a5756807e1b6145d4711a7/packages/layerzero-v2/evm/oapp/test/OFT.t.sol#L407
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: _configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setSolanaEnforcedOptions(address[] memory _connectedOfts) public {
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000);

        L0Config[] memory configs = new L0Config[](1);
        configs[0] = nonEvmConfigs[0]; // mapped to solana

        setEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: configs,
            _optionsTypeOne: optionsTypeOne,
            _optionsTypeTwo: optionsTypeTwo
        });
    }

    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs,
        bytes memory _optionsTypeOne,
        bytes memory _optionsTypeTwo
    ) public {
        for (uint256 c = 0; c < _configs.length; c++) {
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;
            // clear out any pre-existing enforced options params
            delete enforcedOptionParams;
            for (uint256 d = 0; d < _configs[c].assets.length; d++) {
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
                enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
                for (uint256 o = 0; o < _connectedOfts.length; o++) {
                    setEnforcedOption({_connectedOft: _connectedOfts[o]});
                }
            }
        }
    }

    function setEnforcedOption(address _connectedOft) public {
        bytes memory data = abi.encodeCall(IOAppOptionsType3.setEnforcedOptions, (enforcedOptionParams));
        (bool success,) = _connectedOft.call(data);
        require(success, "Unable to setEnforcedOptions");
        pushSerializedTx({_name: "setEnforcedOptions", _to: _connectedOft, _value: 0, _data: data});
    }

    function setLibs(L0Config memory _connectedConfig, address[] memory _connectedOfts, L0Config[] memory _configs)
        public
    {
        // for each destination
        for (uint256 c = 0; c < _configs.length; c++) {
            for (uint256 d = 0; d < _configs[c].assets.length; d++) {
                // for each oft
                for (uint256 o = 0; o < _connectedOfts.length; o++) {
                    setLib({_connectedConfig: _connectedConfig, _connectedOft: _connectedOfts[o], _config: _configs[c]});
                }
            }
        }
    }

    function setLib(L0Config memory _connectedConfig, address _connectedOft, L0Config memory _config) public {
        // skip if the connected and target are the same
        if (_connectedConfig.eid == _config.eid) return;

        // set sendLib to default if not already set
        address lib = IMessageLibManager(_connectedConfig.endpoint)
            .getSendLibrary({_sender: _connectedOft, _eid: uint32(_config.eid)});
        bool isDefault = IMessageLibManager(_connectedConfig.endpoint)
            .isDefaultSendLibrary({_sender: _connectedOft, _eid: uint32(_config.eid)});
        if (lib != _connectedConfig.sendLib302 || isDefault) {
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setSendLibrary, (_connectedOft, uint32(_config.eid), _connectedConfig.sendLib302)
            );
            (bool success,) = _connectedConfig.endpoint.call(data);
            require(success, "Unable to call setSendLibrary");
            pushSerializedTx({_name: "setSendLibrary", _to: _connectedConfig.endpoint, _value: 0, _data: data});
        }

        // set receiveLib to default if not already set
        (lib, isDefault) = IMessageLibManager(_connectedConfig.endpoint)
            .getReceiveLibrary({_receiver: _connectedOft, _eid: uint32(_config.eid)});
        if (lib != _connectedConfig.receiveLib302 || isDefault) {
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setReceiveLibrary,
                (_connectedOft, uint32(_config.eid), _connectedConfig.receiveLib302, 0)
            );
            (bool success,) = _connectedConfig.endpoint.call(data);
            require(success, "Unable to call setReceiveLibrary");
            pushSerializedTx({_name: "setReceiveLibrary", _to: _connectedConfig.endpoint, _value: 0, _data: data});
        }
    }

    /// @dev overrides the virtual pushSerializedTx inherited in Set{X}.s.sol as serializedTxs does not exist in the inherited contract
    function pushSerializedTx(string memory _name, address _to, uint256 _value, bytes memory _data)
        public
        virtual
        override
    {
        serializedTxs.push(SerializedTx({name: _name, to: _to, value: _value, data: _data}));
    }

    function generateCreate3Salt(address broadcaster, string memory name) public pure returns (bytes32) {
        // hex"00 ensures address is deterministic across multi chain
        bytes32 generatedSalt = bytes32(abi.encodePacked(broadcaster, hex"00", stringHashToBytes11(name)));
        return generatedSalt;
    }

    function stringHashToBytes11(string memory name) internal pure returns (bytes11) {
        return bytes11(keccak256(bytes(name))); // first 11 bytes of the keccak256
    }
}
