// Copyright 2024 IOTA Stiftung
// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@iota/iscmagic/ISC.sol";
import "@iota/iscmagic/ISCTypes.sol";
import "@iota/iscmagic/ISCAccounts.sol";
import "@iota/iscmagic/ISCSandbox.sol";
import "@iota/iscmagic/ERC20NativeTokens.sol";

contract NativeTokenController is Ownable {
    event FoundryCreated(uint32 serialNum);
    event ERC20NativeTokenRegistered(
        string name,
        string symbol,
        uint8 decimals,
        uint32 foundrySN,
        address erc20Token
    );
    event NativeTokensMinted(uint32 foundrySN, uint256 amount);

    constructor() payable Ownable(msg.sender) {}

    function sendCrossChain(
        bytes memory chainAddress,
        address _destination,
        ISCChainID _chainID,
        uint32 _foundrySN,
        uint256 _amount,
        uint64 _storageDeposit
    ) public payable onlyOwner {
        L1Address memory l1Address = L1Address({data: chainAddress});
        ISCAssets memory metadataAssets = makeAllowanceBaseTokens(0);

        metadataAssets.nativeTokens = new NativeToken[](1);
        metadataAssets.nativeTokens[0] = NativeToken(
            __iscSandbox.getNativeTokenID(_foundrySN),
            _amount
        );

        ISCAssets memory sendAssets = makeAllowanceBaseTokens(_storageDeposit);
        sendAssets.nativeTokens = new NativeToken[](1);
        sendAssets.nativeTokens[0] = NativeToken(
            __iscSandbox.getNativeTokenID(_foundrySN),
            _amount
        );
        ISCAgentID memory agentID = newEthereumAgentID(_destination, _chainID);

        ISCDict memory params = ISCDict(new ISCDictItem[](1));
        params.items[0] = ISCDictItem("a", agentID.data);

        ISCSendMetadata memory metadata = ISCSendMetadata({
            targetContract: ISC.util.hn("accounts"),
            entrypoint: ISC.util.hn("transferAllowanceTo"),
            params: params,
            allowance: metadataAssets,
            gasBudget: 0xFFFFFFFFFFFFFFFF //try max uint64
        });

        ISCSendOptions memory options = ISCSendOptions({
            timelock: 0,
            expiration: ISCExpiration({
            time: 0,
            returnAddress: L1Address({data: new bytes(0)})
        })
        });

        ISC.sandbox.send(l1Address, sendAssets, false, metadata, options);
    }


    function newEthereumAgentID(address addr, ISCChainID iscChainID)
    internal
    pure
    returns (ISCAgentID memory)
    {
        bytes memory chainIDBytes = abi.encodePacked(iscChainID);
        bytes memory addrBytes = abi.encodePacked(addr);
        ISCAgentID memory r;
        r.data = new bytes(1 + addrBytes.length + chainIDBytes.length);
        r.data[0] = bytes1(ISCAgentIDKindEthereumAddress);

        //write chainID
        for (uint256 i = 0; i < chainIDBytes.length; i++) {
            r.data[i + 1] = chainIDBytes[i];
        }

        //write eth addr
        for (uint256 i = 0; i < addrBytes.length; i++) {
            r.data[i + 1 + chainIDBytes.length] = addrBytes[i];
        }
        return r;
    }

    function mintTokens(
        uint32 _foundrySN,
        uint256 _amount,
        uint64 _storageDeposit
    ) public payable onlyOwner {
        ISCAssets memory allowanceBaseTokens;
        allowanceBaseTokens.baseTokens = _storageDeposit;
        ISC.accounts.mintNativeTokens(_foundrySN, _amount, allowanceBaseTokens);
        emit NativeTokensMinted(_foundrySN, _amount);
    }

    function transfer(
        uint32 _foundrySN,
        uint256 _amount,
        address _destination
    ) public payable onlyOwner returns (bool) {
        ERC20NativeTokens token = ERC20NativeTokens(
            ISC.sandbox.erc20NativeTokensAddress(_foundrySN)
        );
        return token.transfer(_destination, _amount);
    }

    function createNativeTokenFoundry(
        uint256 _maxSupply,
        uint64 _storageDeposit
    ) public payable onlyOwner {
        // check that value was set when deploying so we have smr for storage deposits
        require(
            address(this).balance > 0,
            "contract requires base tokens for storage deposits"
        );

        // create token foundry
        NativeTokenScheme memory tokenScheme;
        tokenScheme.maximumSupply = _maxSupply;
        uint32 foundrySN = ISC.accounts.foundryCreateNew(
            tokenScheme,
            makeAllowanceBaseTokens(_storageDeposit)
        );
        emit FoundryCreated(foundrySN);
    }

    function registerERC20NativeToken(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        uint32 _foundrySN,
        uint64 _storageDeposit
    ) public payable onlyOwner {
        require(
            address(this).balance > 0,
            "contract requires base tokens for storage deposits"
        );

        ISC.sandbox.registerERC20NativeToken(
            _foundrySN,
            _name,
            _symbol,
            _decimals,
            makeAllowanceBaseTokens(_storageDeposit)
        );

        address tokenAddress = ISC.sandbox.erc20NativeTokensAddress(_foundrySN);

        emit ERC20NativeTokenRegistered(
            _name,
            _symbol,
            _decimals,
            _foundrySN,
            tokenAddress
        );
    }

    function registerERC20NativeTokenOnRemoteChain(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        uint32 _foundrySN,
        bytes memory _chainID,
        uint64 _storageDeposit
    ) public payable onlyOwner {
        require(
            address(this).balance > 0,
            "contract requires base tokens for storage deposits"
        );

        ISCDict memory params = ISCDict(new ISCDictItem[](5));
        params.items[0] = ISCDictItem(
            "fs",
            encodeUint32LittleEndian(_foundrySN)
        );
        params.items[1] = ISCDictItem("n", bytes(_name));
        params.items[2] = ISCDictItem("t", bytes(_symbol));
        params.items[3] = ISCDictItem("d", encodeUint8LittleEndian(_decimals));
        params.items[4] = ISCDictItem("A", _chainID);

        ISC.sandbox.call(
            ISC.util.hn("evm"),
            ISC.util.hn("registerERC20NativeTokenOnRemoteChain"),
            params,
            makeAllowanceBaseTokens(_storageDeposit)
        );
    }


    function nativeTokenID(uint32 foundrySN)
    public
    view
    returns (bytes memory)
    {
        return ISC.sandbox.getNativeTokenID(foundrySN).data;
    }

    function erc20NativeTokensAddress(uint32 foundrySN)
    public
    view
    returns (address)
    {
        return ISC.sandbox.erc20NativeTokensAddress(foundrySN);
    }

    function getERC20ExternalNativeTokenAddress(bytes memory _nativeTokenID)
    public
    view
    returns (address)
    {
        ISCDict memory params = ISCDict(new ISCDictItem[](1));

        params.items[0] = ISCDictItem("N", _nativeTokenID);
        ISCDict memory returnedDict = ISC.sandbox.callView(
            ISC.util.hn("evm"),
            ISC.util.hn("getERC20ExternalNativeTokenAddress"),
            params
        );

        ISCDictItem memory item = returnedDict.items[0];
        return bytesToAddress(item.value);
    }

    function bytesToAddress(bytes memory b) public pure returns (address) {
        require(b.length == 20, "Bytes length must be exactly 20");

        address addr;
        // Use assembly to convert from bytes to address
        assembly {
            addr := mload(add(b, 0x14)) // Load the 20 bytes at offset 20 of the input into addr
        }
        return addr;
    }


    // create an allowance
    function makeAllowanceBaseTokens(uint64 amount)
    internal
    pure
    returns (ISCAssets memory)
    {
        return ISCAssets({
            baseTokens: amount,
            nativeTokens: new NativeToken[](0),
            nfts: new NFTID[](0)
        });
    }

    // ISC uses little endian encoding, solidity uses big, so we need to write a special packer
    function encodeUint32LittleEndian(uint32 value)
    internal
    pure
    returns (bytes memory)
    {
        bytes memory b = new bytes(4);
        for (uint256 i = 0; i < 4; i++) {
            b[i] = bytes1(uint8(value >> (i * 8)));
        }
        return b;
    }

    function encodeUint8LittleEndian(uint8 value)
    internal
    pure
    returns (bytes memory)
    {
        bytes memory b = new bytes(1);
        b[0] = bytes1(value);
        return b;
    }

    receive() external payable {}

    function withdraw() public onlyOwner {
        address payable to = payable(msg.sender);
        to.transfer(address(this).balance);
    }
}
