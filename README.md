# Arbitrum Governor Upgrade

## New Address Registry

After the upgrade, a new address registry contract can be deployed by running the following command in the [Arbitrum Governance](https://github.com/ArbitrumFoundation/governance) repo:

```ts
make
forge create src/gov-action-contracts/address-registries/L2AddressRegistry.sol:L2AddressRegistry --constructor-args <NEW_CORE_GOVERNOR_CONTRACT_ADDRESS> <NEW_TREASURY_GOVERNOR_CONTRACT_ADDRESS> 0xF3FC178157fb3c87548bAA86F9d24BA38E649B58 0x1D62fFeB72e4c360CcBbacf7c965153b00260417 --rpc-url <ARB_ONE_RPC_URL> --private-key <PRIVATE_KEY>
```

## License

The code in this repository is licensed under the [GNU Affero General Public License](LICENSE) unless otherwise indicated.

Copyright (C) 2024 ScopeLift
