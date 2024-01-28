# Setup

Create two chains and copy their chain IDs from the wasp-cli output. In this example they are:

- Chain A: `tst1pzcsxkrgxflzzcet6858j95ajzzw4tuyzp3pa7cksl4ze2qhsx9vvd8y98h`
- Chain B: `tst1pzftt2azhfz6cl5p9asd2upfw930nnrh7k54guaxkzytft7rzrn5xf5tc6h`

Deploy the contract. Set value to 1 eth (smr) so there's some funds on the contract to cover storage deposits later.
Call `createNativeTokenFoundry` with `_maxSupply = 100` and `_storageDeposit = 1000000`. If you didn't send any tokens
when the contract was deployed, you must set the value for this transaction to 1 ETH so the contract will have funds for 
L1 operations. You can recover any unused funds later with the `withdraw` method.

You can see the result of this operation on L1 in [createNativeTokenFoundryBlock.json](createNativeTokenFoundryBlock.json)

# ERC20 Creation

We need to register the native token foundry on `Chain A` and `Chain B` as normal ERC20 contacts as well as save some of 
the returned data for use once we move to `Chain B`.

## Chain A ERC20 Registration

Call `registerERC20NativeToken` to create an ERC20 token on the same chain as the controller contract. I used the following
parameters: `_name = DemoToken`, `_symbol = DMO`, `_decimals = 2`, `_foundrySN = 1`, `_storageDeposit = 10000`
Note that `_foundrySN` is retrieved from the logs of the foundry creation transaction. Since we are doing this on a fresh
chain, it will always be `1` for the first one you create, then `2`, etc.

The output of token registration results in a log output with the erc20 token address. If your foundrySN was `1` then it
will be the same as mine: `0x1074020100000000000000000000000000000000`. You can add this token to metamask using this 
address.

The L1 block containing this transaction looks like [this](registerERC20Block.json)

## Chain B ERC20 Registration

Call `registerERC20NativeTokenOnRemoteChain` to register these native tokens on `Chain B`. You'll need the chain ID of the
chain as bytes to pass into the demo contract. You can use [this][golang-bech32] tool to convert the wasp chain ID to
the hex bytes the contract is expecting. Since this token is going on another chain, I like to differentiate it by calling
it 'wrapped demo token' so I used the following inputs: 
`_name = Wrapped DemoToken`, `_symbol = wDMO`, `_decimals = 2`, `_foundrySN = 1`, 
`_chainID = 0x0892b5aba2ba45ac7e812f60d570297162f9cc77f5a95473a6b088b4afc310e743`,`_storageDeposit = 1000000`. 
This creates two transactions on L1: [first](registerERC20RemoteChainBlock1.json) and then
the [second](registerERC20RemoteChainBlock2.json)

The last bit of info we need is the `native token id` for our foundry. Call `nativeTokenID` with `foundrySN = 1`
which in this example returned `0x08b1035868327e21632bd1e879169d9084eaaf8410621efb1687ea2ca817818ac60100000000`. You
may notice that this is the concatenation of the `chain id` and the `foundry serial number`.

# Minting

Now that initial setup is complete, we are ready to mint some tokens and send them to users.

Call `mintTokens` with `_foundrySN = 1`, `_amount = 100`, and `_storageDeposit = 1000000`. This will create 100 tokens
that belong to the smart contract. L1 output is [here](mintTokensBlock.json).

# Transfer

Now that the tokens are created, we can send them to regular chain users. We must use the ERC20 token contract to call
the transfer method, and it has to be the foundry owner that does it, so we have a method on our demo contract named
`transfer` that does just that. Once the tokens belong to a regular EVM account they are free to transfer them as normal
using the standard ERC20 interface.

## Intra-chain Transfer

You can have the contract transfer some tokens to your metamask account by calling `transfer` with `_foundrySN = 1`,
`_amount = 1`, `_destination = <your metamask wallet>`. [L1 output](transfer.json).
If you check your metamask you should see that you now have 0.01 DMO on Chain A. This is because we have `decimals = 2`
so when we minted `100` and sent `1` we actually minted `1.00` tokens and sent `0.01` to our wallet.

## Transfer to External Chain

Now for the good part: transferring tokens to another EVM chain. We're going to call `sendCrossChain` with the following:

- `chainAddress = 0x0892b5aba2ba45ac7e812f60d570297162f9cc77f5a95473a6b088b4afc310e743` this is the chain ID for `Chain B`
- `destination = 0xaEe61A70C6cE785B2eAf350E8B66647c88073C53` this is the metamask wallet address that you want to
  receive the tokens on the other side
- `_chainID = 0x92b5aba2ba45ac7e812f60d570297162f9cc77f5a95473a6b088b4afc310e743` this is the `Chain B` chain ID, minus
  the leading `08` hex byte that identifies the address as being an alias address[^1].
- `_foundrySN = 1`
- `_amount = 2` we'll use 2 here to differentiate it from the `0.01` we control on this chain
- `_storageDeposit = 1000000`

At this point, you may have received an error "MoveBetweenAccounts: not enough funds". This is due to the balance of eth/smr
on the contract running low due to all the storage deposits. Go ahead and set `value` to `1` eth/smr for this transaction
to add more to the contract.

Here is a screenshot showing these inputs in remix:

![screenshot showing input data in remix for sending cross chain](cross%20chain%20send.png)

Execute the transaction, and you'll see two outputs on L1: [output 2](crossChainSend1.json) and [output 2](crossChainSend2.json)

### Receiving on Chain B

Now it's time to switch your metamask to `Chain B` and add the tokens to your wallet. In order to do that, we need to
get the ERC20 contract address for the native tokens on this chain. Go ahead and deploy the contract on Chain B[^2]. I
have included the L1 output [here](chainBcontractDeploy.json), although it's probably not useful. Next, call
`getERC20ExternalNativeTokenAddress` with
`_nativeTokenID = 0x08b1035868327e21632bd1e879169d9084eaaf8410621efb1687ea2ca817818ac60100000000` which is the value we
saved while we were on Chain A earlier. In my case this returned `0x107405CBC313Bb96bac5460720ab9708bbbb4aac`. This is the
ERC20 contract address for the tokens on this chain. You can use that to add it to your metamask. You should see that
you have a balance of 0.02 wDMO.

You are now free to treat these tokens as you would any other ERC20 token. 

# Misc

You can execute the commands below to create two EVM chains on a fresh wasp [local setup](https://github.com/iotaledger/wasp/tree/develop/tools/local-setup)
where `<metamask address>` is the ethereum address of the wallet you want to use to interact on the chain(s).

```shell
wasp-cli request-funds
wasp-cli chain deploy --chain=chain-a
wasp-cli chain deploy --chain=chain-b
wasp-cli chain deposit <metamask address> base:10000000000 --chain=chain-a
wasp-cli chain deposit <metamask address> base:10000000000 --chain=chain-b
```

Another set of commands that can help reset the docker environment is below. I like to run these and then follow up with
the wasp-cli commands above to set up the two chains again:

```shell
docker compose down
docker volume rm wasp-db hornet-nest-db
docker volume create --name hornet-nest-db
docker volume create --name wasp-db
docker-compose up -d
```

[golang-bech32]: https://go.dev/play/p/QnHB990_kMM

[^1]: This is something that will be improved in the future but was left as is for time's sake
[^2]: If this transaction sits in your activity log as 'pending' go into metamask settings -> advanced and
clear activity log. This happens when you reset the chains frequently and metamask tries to use an invalid nonce for the
transaction. Once you clear the log you can resubmit the transaction again as normal. Sometimes remix hangs for a long
time after doing this. Simply open a new tab with remix in it, and use it. Do not close the original tab, as that has
the address for your deployed contract on Chain A in it which you will need to interact with the foundry.
