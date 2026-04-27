// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/StdJson.sol";

import {L0Config, L0ConfigConstant} from "script/L0Constants.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";

import {
    SetConfigParam,
    IMessageLibManager
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import {BaseInherited} from "./BaseInherited.sol";
import {Script} from "forge-std/Script.sol";

contract SetDVNs is BaseInherited, Script {
    using Strings for uint256;
    using stdJson for string;

    address[] public dvnStackTemp;

    struct DvnStack {
        address lz;
        address nethermind;
    }

    function setDVNs(L0Config memory _connectedConfig, address[] memory _connectedOfts, L0Config[] memory _configs)
        public
        virtual
    {
        for (uint256 _o = 0; _o < _connectedOfts.length; _o++) {
            for (uint256 _c = 0; _c < _configs.length; _c++) {
                // Skip if setting config to self
                if (_connectedConfig.chainid == _configs[_c].chainid) continue;
                setConfigs({
                    _connectedConfig: _connectedConfig, _connectedOft: _connectedOfts[_o], _config: _configs[_c]
                });
            }
        }
    }

    function setConfigs(L0Config memory _connectedConfig, address _connectedOft, L0Config memory _config)
        public
        virtual
    {
        setConfig({
            _srcConfig: _connectedConfig, _dstConfig: _config, _lib: _connectedConfig.sendLib302, _oft: _connectedOft
        });
        setConfig({
            _srcConfig: _connectedConfig, _dstConfig: _config, _lib: _connectedConfig.receiveLib302, _oft: _connectedOft
        });
    }

    function setConfig(L0Config memory _srcConfig, L0Config memory _dstConfig, address _lib, address _oft)
        public
        virtual
    {
        // get the current DVN stack for the given oft and library
        bytes memory _currentUlnConfigBytes = IMessageLibManager(_srcConfig.endpoint)
            .getConfig({
                _oapp: _oft, _lib: _lib, _eid: uint32(_dstConfig.eid), _configType: L0ConfigConstant.CONFIG_TYPE_ULN
            });
        UlnConfig memory _currentUlnConfig = abi.decode(_currentUlnConfigBytes, (UlnConfig));

        // generate the DVN stack as defined in the config
        address[] memory desiredDVNs = craftDvnStack({_srcChainId: _srcConfig.chainid, _dstChainId: _dstConfig.chainid});

        // Determine if we are working with a different array of DVNs than what is currently configured
        // Do nothing if the stack is the same as before
        if (arraysAreEqual(_currentUlnConfig.requiredDVNs, desiredDVNs)) return;

        // generate the config
        UlnConfig memory _desiredUlnConfig;
        _desiredUlnConfig.requiredDVNCount = uint8(desiredDVNs.length);
        _desiredUlnConfig.requiredDVNs = desiredDVNs;

        SetConfigParam[] memory setConfigParamArray = new SetConfigParam[](1);
        setConfigParamArray[0] = SetConfigParam({
            eid: uint32(_dstConfig.eid),
            configType: L0ConfigConstant.CONFIG_TYPE_ULN,
            config: abi.encode(_desiredUlnConfig)
        });

        // generate data and call
        bytes memory data = abi.encodeCall(IMessageLibManager.setConfig, (_oft, _lib, setConfigParamArray));
        (bool success,) = _srcConfig.endpoint.call(data);
        require(success, "Unable to setConfig");
        pushSerializedTx({_name: "setConfig", _to: _srcConfig.endpoint, _value: 0, _data: data});
    }

    function arraysAreEqual(address[] memory _dvnStackA, address[] memory _dvnStackB)
        public
        pure
        virtual
        returns (bool)
    {
        if (_dvnStackA.length != _dvnStackB.length) {
            return false;
        } else {
            for (uint256 i = 0; i < _dvnStackA.length; i++) {
                if (_dvnStackA[i] != _dvnStackB[i]) {
                    return false;
                }
            }
        }
        return true;
    }

    // Returns the ascending-sorted DVN stack of the connected chain
    function craftDvnStack(uint256 _srcChainId, uint256 _dstChainId)
        public
        virtual
        returns (address[] memory desiredDVNs)
    {
        DvnStack memory srcDVNs = getDvnStack({_srcChainId: _srcChainId, _dstChainId: _dstChainId});
        DvnStack memory dstDVNs = getDvnStack({_srcChainId: _dstChainId, _dstChainId: _srcChainId});

        // start with a fresh array
        delete dvnStackTemp;

        // populate the temporary dvn stack array

        if (srcDVNs.lz != address(0) || dstDVNs.lz != address(0)) {
            require(
                srcDVNs.lz != address(0) && dstDVNs.lz != address(0),
                incorrectDvnMatchMsg("lz", _srcChainId, _dstChainId)
            );
            dvnStackTemp.push(srcDVNs.lz);
        }

        if (srcDVNs.nethermind != address(0) || dstDVNs.nethermind != address(0)) {
            require(
                srcDVNs.nethermind != address(0) && dstDVNs.nethermind != address(0),
                incorrectDvnMatchMsg("nethermind", _srcChainId, _dstChainId)
            );
            dvnStackTemp.push(srcDVNs.nethermind);
        }

        // populate the output array and sort ascending
        desiredDVNs = new address[](dvnStackTemp.length);
        for (uint256 i = 0; i < dvnStackTemp.length; i++) {
            desiredDVNs[i] = dvnStackTemp[i];
        }
        desiredDVNs = Arrays.sort(desiredDVNs);
    }

    function incorrectDvnMatchMsg(string memory dvnName, uint256 chainId1, uint256 chainId2)
        public
        pure
        virtual
        returns (string memory)
    {
        string memory message = string.concat("DVN Stack misconfigured: ", chainId1.toString());
        message = string.concat(message, " <> ");
        message = string.concat(message, chainId2.toString());
        message = string.concat(message, " - ");
        message = string.concat(message, dvnName);
        return message;
    }

    function getDvnStack(uint256 _srcChainId, uint256 _dstChainId)
        public
        view
        virtual
        returns (DvnStack memory dvnStack)
    {
        require(_srcChainId != _dstChainId, "_srcChainId == _dstChainId"); // cannot set dvn options to self

        // craft path
        string memory root = vm.projectRoot();
        root = string.concat(root, "/config/mainnet/dvn/");
        string memory name = string.concat(_srcChainId.toString(), ".json");
        string memory path = string.concat(root, name);

        // load json
        string memory jsonFile = vm.readFile(path);

        // NOTE: a missing key will cause this decoding to revert
        string memory key = string.concat(".", _dstChainId.toString());
        dvnStack = abi.decode(jsonFile.parseRaw(key), (DvnStack));
    }
}
