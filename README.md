# Float.state smart contracts
Float.state is an innovative platform for establishing and governing autonomous floating marine communities, built on the Ethereum platform using the L2 layer Polygon zkEVM and consists of four smart contracts and the [float.systems](https://float.systems/) website connected to them. The contracts are based on secure and battle-tested upgradeable (UUPS proxy pattern) smart contracts from @openzeppelin. 

Smart contracts are linked - they use each other's functions and storages. To prevent unauthorized use of functions, contracts are initialized with the addresses of contracts included in the system and some important functions can only be called by an authorized contract.

Contracts were deployed to Polygon zkEVM. When deploying an upgradeable smart contract, the UUPS deployment plugin creates two smart contracts: a proxy and an implementation contract. 

**Library GovernanceLibrary** - Library for FloatGovernance contract functions.

**FloatToken** - JSG token contract based on ERC20VotesUpgradeable by @openzeppelin.

**FloatExchange** - Contract for trading JSG tokens at a fixed price.

**FloatGovernance** - Governance contract for projects funding.

**FloatLaws** - Contract for establishing and changing through weighted voting laws, system parameters and contract upgrading.
