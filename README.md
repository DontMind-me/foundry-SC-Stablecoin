# SC-Stablecoin

## About

This project is a stablecoin where users can deposit WETH and WBTC in exchange for a token pegged to the US dollar. The protocol is all programatic.

1. **Relative stability**: Anchored / Pegged to the US Dollar. 
2. **Stability Mechanism**: Algorithmic (Users can only mint stablecoin with enough collateral)
3. **Collateral**: Exogenous (Collateral comes from outside the protocol meaning that if our stablecoin fails, the collateral doesn't fail)

## License

MIT

## Clone Repository 

```
git clone https://github.com/DontMind-me/foundry-SC-Stablecoin
cd foundry-SC-Stablecoin
forge build
```

## Installs

To interact with the contract, you will have to download the following packages 

```
forge install cyfrin/foundry-devops@0.2.2 --no-commit
```

```
forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
```

```
forge install foundry-rs/forge-std@v1.8.2 --no-commit
```

```
 forge install transmissions11/solmate@v6 --no-commit
```

--------------------------------------------------------------------------------------

## THANK YOU FOR VISITING MY PROJECT
