# Nest Protocol

Nest is an ERC-4626/7540/7575-compliant vault stack that standardizes deposits/redemptions (sync and async) and extends Boring Vault economics across chains by bridging shares via LayerZero OFT (assets stay on their origin chain). Two operating modes:
- **Existing BoringVault deployments (no native cross-chain)**: `NestVaultOFT` is the entrypoint and pairs with `NestShareOFT` to bridge shares over LayerZero OFT, letting the legacy BoringVault stay single-chain while users move shares cross-chain.
- **New deployments (no BoringVault on-chain)**: `NestVault` is the entrypoint and speaks to `NestShareOFT`, a refined BoringVault replacement that natively supports cross-chain shares.

Compliance and integrations:
- **KYC/predicate gating** via `NestVaultPredicateProxy`, which fronts the vault and enforces Predicate policies before minting shares.
- **Pendle Finance integration** through `BoringVaultSY`, wrapping Pendle SY for yield and Merkl rewards while using the same accountant/rate-provider flow.
- **BoringVault integration**: this repo uses the BoringVault accountant/rate-provider contracts; it does not ship the base BoringVault itself.

## Contracts and Addresses

* Msigs (links to gnosis safe)
  * [`Plume`](https://safe.onchainden.com/transactions/history?safe=plume:0xa08a0dc480bd60d1d56c8eec6c722125eafea982)
  * [`Ethereum`](https://app.safe.global/home?safe=eth:0xa08a0dc480bd60d1d56c8eec6c722125eafea982)
  * [`Arbitrum`](https://app.safe.global/home?safe=arb:0xa08a0dc480bd60d1d56c8eec6c722125eafea982)
  * [`Plasma`](https://app.safe.global/home?safe=plasma:0xa08a0dc480bd60d1d56c8eec6c722125eafea982)
  * [`BNB`](https://app.safe.global/home?safe=bsc:0xa08a0dc480bd60d1d56c8eec6c722125eafea982)

### BoringVaultSY

* Chain - `ethereum`
   * SY Vaults
     * nBASIS - `0xA08c5b18a05317dc0Ed43c9eEa9ea6db85D84eD1`
       * ProxyAdmin (ethereum): `0xa28c08f165116587d4f3e708743b4dee155c5e64`

### Nest Vaults

#### Admin

* Common contracts
  * AtomicQueueUCP (old)
    * `plume`, `ethereum`, `plasma`: `0x228C44Bb4885C6633F4b6C83f14622f37D5112E5`
    * `bnb`: `0x220dc6d4569C1F406D532f9633D5Be5Bc86e8264`
  * AtomicQueue (new)
    * `plume`, `ethereum`, `plasma`, `bnb`, `worldchain`: `0x220dc6d4569c1f406d532f9633d5be5bc86e8264`
  * AtomicSolver
    * `plume`, `ethereum`, `plasma`, `bnb`, `worldchain`: `0x77fb098A1C28a5b50BFAdb69Ca1bEE515a7FC974`
  * Teller with PredicateProxy (old)
    * `plume`, `ethereum`, `plasma`, `bnb`: `0x6104fe10ca937a086ba7AdbD0910A4733d380cB6`
  * NestVaultPredicateProxy
    * `plume`, `worldchain`: `0xfc0c4222b3a0c9b060c0b959dec62442036b9035`
      * ProxyAdmin: `0xeff5d7efccd4492a65a6bc539adc5bdb28d575f0`
  * NestCCTPRelayer
    * `plume`: `0x7de01896d36Bea9CF072Ac64E41685418941d8bE`
      * ProxyAdmin: `0x45f63e668cb8c8ebcf95eab4889e4c0c1b63d8e8`
  * RolesAuthority (OVault)
    * `shared`: `0x93786916e1EE5913A45662a5986559f5785a5BA4`
  * RolesAuthority
    * `plume`, `ethereum`, `plasma`, `bnb`, `worldchain`: `0x6dea7e8445a2b2546b9134626e81e3c307141ec0`

* Nest ALPHA Boring Vault (nALPHA)
  * `plume`, `ethereum`, `plasma`, `bnb`, `worldchain`
    * BoringVault : `0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db`
    * Accountant : `0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1`
      * ProxyAdmin (worldchain): `0xe4c9d4f770aa42aef9ef1135bf48efb863eeb691`
    * Teller : `0xc9F6a492Fb1D623690Dc065BBcEd6DfB4a324A35`
    * Manager : `0xf71DE9Ba3Bc45Eab9014A89A11563e0f398C0c81`
    * NestVaultComposer (USDC) : `0x3eb8a97552e6D4b4Bc90Fe59D42d9333cA8a5727`
      * ProxyAdmin (plume): `0x8c66329249dfcc4526a592ff1d45da6b41681bb5`
    * NestVault (USDC) : `0x0342EE795e7864319fB8D48651b47feBf1163C34`
      * ProxyAdmin (plume, worldchain): `0xd7036e717c4e009b93064a18292e127183c69bed`
    * RolesAuthority : `0xe04eD3c5b41B4F0B82F952d14aec5598B1092b15`
    * Solana mint (OFT share mint) : `G6SkPqYTbtVFYU4krZLDgHf5MVMfARG57G1kog4RYH2n`

* Nest Treasuries Boring Vault (nTBILL)
  * `plume`, `ethereum`, `arbitrum`, `plasma`, `bnb`, `worldchain`
    * BoringVault : `0xe72fe64840f4ef80e3ec73a1c749491b5c938cb9`
    * Accountant : `0x0b738cd187872b265a689e8e4130c336e76892ec`
      * ProxyAdmin (worldchain): `0x3255e6688f71071c3baf7d3ec87eadf0851230c4`
    * Teller : `0x1492062b3ae7996c71f87a2b390b6b82afea0c59`
    * Manager : `0xf713a353f38d2e90245b94c1b004c10ab3a34857`
    * NestVaultComposer (USDC) : `0x719e01497eD0E4e917fd0482355b9A64ddbad873`
      * ProxyAdmin (plume): `0xe2cc6853e4a65cf2069b98e37f4f900c1d2c5cd6`
    * NestVault (USDC) : `0x250c2D14Ed6376fB392FbA1edd2cfd11d2Bf7F12`
      * ProxyAdmin (plume, worldchain): `0xcec84cac23a659217f10ee2a9476d6c4a8901067`
    * RolesAuthority : `0x0a4f939b5d51157c58ba053275eaf77a782b4996`
    * Solana mint (OFT share mint) : `2sA2jW9e8EYJkLFpq9hkhxfVUQBwVGJwq6iP4TmTKrL4`

* Nest High Yield Boring Vault (nYIELD)
  * `plume`, `ethereum`
    * BoringVault : `0x892dff5257b39f7afb7803dd7c81e8ecdb6af3e8`
    * Accountant : `0x5da1a1d004fe6b63b37228f08db6caeb418a6467`
    * Teller : `0x92a735f600175fe9ba350a915572a86f68ebbe66`
    * Manager : `0x912d14e0584b8e3273e5605c301033b77e34d940`
    * RolesAuthority : `0xeacce72066b12dfc16bed7a08a4323ac0e31ed3a`

* Nest USD Yield Boring Vault (nUSDY)
  * `plume`, `ethereum`
    * BoringVault : `0x7fca0df900a11ae1d17338134a9e079a7ee87e31`
    * Accountant : `0x16c4509b7b090319023571080d3430c7bee84f49`
    * Teller : `0xcc7623e60f4508b7e9b3ed059ebf65465660f370`
    * Manager : `0x956c47af358ee03e47fe5b98f4578686e7102b69`
    * RolesAuthority : `0xB0cfbda22602c05851dd742a29A26a2cb43048E4`

* Nest Elixir Boring Vault (nELIXIR)
  * `plume`, `ethereum`
    * BoringVault : `0x9fbC367B9Bb966a2A537989817A088AFCaFFDC4c`
    * Accountant : `0xAdB076707AbED7D19E3A75d98E77FCDFa4c15D93`
    * Teller : `0xd65D39c859C6754B3BC14f5c03c4A1aE80FC4c15`
    * Manager : `0xAC4ea2cEaac605A2F7fEb66F13B25A9FBd691A1B`
    * RolesAuthority : `0x1320b933bfcaebf5c84a47a46d491d612653d807`

* Nest Institutional Elixir Boring Vault (inELIXIR)
  * `plume`, `ethereum`
    * BoringVault : `0xd3bfd6e6187444170a1674c494e55171587b5641`
    * Accountant : `0x4ff98c6dbfda19eede2a4f930b6bdc9232405af7`
    * Teller : `0xe498f5c63f9405ee7c7b90063cdb45de4fe9ce21`
    * Manager : `0xb7db22a4c3e8ed60bba4b23c206339842a6dad20`
    * RolesAuthority : `0x9fE18EEB1Cff95A8f9E423aAc2D3B5a2D6f872e3`

* Nest Basis Vault (nBASIS)
  * `plume`, `ethereum`, `plasma`, `bnb`, `worldchain`
    * BoringVault : `0x11113Ff3a60C2450F4b22515cB760417259eE94B`
    * Accountant : `0xa67d20A49e6Fe68Cf97E556DB6b2f5DE1dF4dC2f`
      * ProxyAdmin (worldchain): `0xbcb5820d016ac1f6ced6fadbe9a706fa8f3edffc`
    * Teller : `0xAD60d43a33cA26e40eAcc5BBc60f1C7136FFB89b`
    * Manager : `0x17767f384cead5182cAaf9056635bAc14aFC24a1`
    * NestVaultComposer (USDC) : `0x22B41d16c935Fab4C2b807Ebb72899f0715c42Ee`
      * ProxyAdmin (plume): `0x1074303ca048d2e14f6576a59cc2495c1157cc67`
    * NestVault (USDC) : `0x5F35D1cef957467F4c7b35B36371355170A0DbB1`
      * ProxyAdmin (plume, worldchain): `0xb4efd5fc2950377965956306d5ffaf22e2412f59`
    * RolesAuthority : `0x5886A35bE0bD4533C2295C0e8083364ab0b27205`

* Nest Credit Vault (nCREDIT)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0xa5f78b2a0ab85429d2dfbf8b60abc70f4cec066c`
    * Accountant : `0x486e0362b0641c0fca21cac2e317f6e21a8b19f3`
    * Teller : `0x27200293aac3d04d2b305244f78d013b3c759f9d`
    * Manager : `0xca88561210221b9611a5ed15389611bac87afc63`
    * RolesAuthority : `0xa0D1a1462b76DCAbFE1B1df49a6E29A5315F90db`

* Nest Institutional Vault (nINSTO)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0xbfc5770631641719cd1cf809d8325b146aed19de`
    * Accountant : `0xb00bbbd72a377a34eac434226dd3e0e12d12a55b`
    * Teller : `0xf288a085622808b5c616ff45d740459741a6551c`
    * Manager : `0x23d8f2517f3753db257425f46064a58514e65eca`
    * RolesAuthority : `0x22eb63226bF94b2154Fba1332f222aD17FaEc744`

* Nest PayFi Vault (nPAYFI)
  * `plume`, `ethereum`
    * BoringVault : `0xb52b090837a035f93a84487e5a7d3719c32aa8a9`
    * Accountant : `0xb0d00195ce43f2708aaebb9f6e37c202389019fc`
    * Teller : `0xe0322021c957998c8cc85e1b0abb1f58d598f06f`
    * Manager : `0x0d2b422f442d3605a230c7f80d15892a52050094`
    * RolesAuthority : `0xE66024dF86F3E30f8e034ad1FEf8283202bcfBFF`

* Nest Bitcoin Vault (nBTC)
  * `plume`, `ethereum`
    * BoringVault : `0x02cdb5ccc97d5dc7ed2747831b516669eb635706`
    * Accountant : `0x77e77f47cf0524955c91968fb8b479ac52db087a`
    * Teller : `0x94f07e453b5539532114de4875f508ae53e3cd4d`
    * Manager : `0xacecb63117c56059b8946329b62c141e5b8994c9`
    * RolesAuthority : `0xB7eb9eA013689a862828Cb7d46A2cd9F45463Fb4`

* Nest ETF Vault (nETF)
  * `plume`, `ethereum`
    * BoringVault : `0xdeA736937d464d288eC80138bcd1a2E109A200e3`
    * Accountant : `0x2f35AedE6662408a897642739c9BE999054a9F68`
    * Teller : `0xF09ffBeB3afE5c21C0A197765766e6f356590646`
    * Manager : `0xb6f43c7E380f810be1d862925D430819Fb0D29Ee`
    * RolesAuthority : `0xA911A8268C9fbd949AA56B20dd5cC888f1519dbe`

* Nest Institutional Alpha Vault (inALPHA)
  * `plume`, `ethereum`
    * BoringVault : `0x64ab176c545bb85eca75d53c3ffcb361deafb855`
    * Accountant : `0xa65e054d2d9f7a9789065e0a6381132efbd41a90`
    * Teller : `0x20428f901a50ec69f5a2b56d313491cc686fafff`
    * Manager : `0x72391dade9e7d32f09fde0569fccf5876ab61955`
    * RolesAuthority : `0x5E500500968388A13B3Ff885C3EeD7158a5D82eF`

* Nest Apollo ACRDX Vault (nACRDX)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0x2A3e301dbd45c143DFbb7b1CE1C55bf0BBF161cb`
    * Accountant : `0xF76bC95969e5Aa32b7b95Bb4caAA1bcbB2dDcAB9`
    * Teller : `0xA1D572b63C963c6421236C22A10140305C6d41fd`
    * Manager : `0xd9Ec26255ffA085af8BCa8e42D5e930D4a466063`
    * RolesAuthority : `0x3ac371896A1c17256DF1D80EEc498920418127A7`

* Nest Mineral Vault (nMNRL)
  * `plume`, `ethereum`
    * BoringVault : `0x9D08946Ca5856f882A56c29042FbEDC5142663b9`
    * Accountant : `0xb64F566E1ca00B510Fd1A4bceFFC32Eb718eeD42`
    * Teller : `0x3F73b03eCb7F89501808E2f3Ded8232b02C3cdAa`
    * Manager : `0xEDD04D08bbE1D892759332F6BD3b36F8828A6BaE`
    * RolesAuthority : `0xe07725238Dd8cDBC0ae30B35cAB822Acb48b613f`

* Nest WisdomTree Vault (nWISDOM)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0x29bF22381A5811deC89dC7b46A5Ce57aD02c0240`
    * Accountant : `0x5f57AE7Bf41806b2c8F5ddBf1E6a09D7a6D916f6`
    * Teller : `0x7D218B7ce9EE5Ee4D500ba048240537b728E0d25`
    * Manager : `0x8226B661EbaF1CBA4e2A92aE2616CCF2348F18cc`
    * NestVaultComposer (USDC) : `0x312a0219E8af66C4e8849a3fEF4047415c3b4974`
      * ProxyAdmin (plume): `0x4ad55a5b2d5a4e6490545cc6d6a6a45632d714e3`
    * NestVault (USDC) : `0x6330a14FC1520CFdF0834CCf23B15FD47a89a651`
      * ProxyAdmin (plume): `0xc74385e727fe3340d09982646eb6605e9e310704`
    * RolesAuthority : `0x57Aa9D6C6Be5695ddD1eBD3D0B6D3e38C0ec5Ccf`
    * Solana mint (OFT share mint) : `77DTSzxisdQWshFYHP9M2JBDuHNojLAVoC7GBNC2yadT`

* Nest BlackOpal LiquidStone II Vault  (nOPAL)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165`
    * Accountant : `0x2Ed2f77a961fc92F73D1087786099c39C894Ed1D`
    * Teller : `0xA5F8e5843dd597a179453bF782844e8Bf808A90b`
    * Manager : `0xea452B14FC86847182F8DD0486206eb56dDA0393`
    * NestVaultComposer (USDC) : `0x9053e541c4bf3f44A8dbb7e25625639B6D0b62c9`
      * ProxyAdmin (plume): `0x013ee87003e6836a9dbee40af6f18ffe74c3153a`
    * NestVault (USDC) : `0xD258029cF5a177e3306E09Fbea63424543a505c0`
      * ProxyAdmin (plume): `0xa8ebf1df79594cb6147613bda62977ac40c0c20e`
    * RolesAuthority : `0x4e9be1e46366e0F255ca7578467e3e0BBE7514DE`
    * Solana mint (OFT share mint) : `GArhnnDj3GYhmQeApKVXaRv4TQFwhPcs3SNF6FXsTeXq`

* Nest Goldfinch Prime Vault (nGPRIME)
  * `plume`, `ethereum`, `plasma`, `bnb`
    * BoringVault : `0x2B89048D45E9EfF64bC5ff563B8ba40A2f0aa83E`
    * Accountant : `0x4aab7DdC15C1FFe71440A6Ee832A5201B796262d`
    * Teller : `0x7A5E29bA2e8dD49444252EB13049FC3b4E0658dB`
    * Manager : `0x899d77B7Fa7b7a6AB8691Cd145F54eB0a02fb76f`
    * RolesAuthority : `0xD59b873CF1042B70d143c1Fbf1d9e7beF1A1d158`

* Nest Hamilton Lane SCOPE Vault (nSCOPE)
  * `plume`, `plasma`, `bnb`
    * BoringVault : `0x770C2D6b16c8F8AB5535ae719A5475411c120f6e`
    * Accountant : `0x0Db69B857b4502493B5c11c3458dbfF6105eD337`
      * ProxyAdmin (plume): `0x0d5a0eddb15cbb178137118c091ddc201f04cca5`
    * Teller : `0x38cc506c005C312Ef1DD6e566d26c2eDeA4f9B45`
    * NestVaultComposer (USDC) : `0xEe47001b301557186DBfb9999Aa219846BBf188D`
      * ProxyAdmin (plume): `0xd7180a91d01efe368cee990d6c5d6f6728fc6a48`
    * NestVault (pUSD) : `0x31131beBcf4E886aD1Fe6931c71632ECDf6aC909`
      * ProxyAdmin (plume): `0x5323dba5c874b9ce303feb531ebf2e36f95025ec`
    * NestVault (USDC) : `0x237A3452404009C9B612D706fD031Fd8F50C473C`
      * ProxyAdmin (plume): `0x9aa04bdc24d650b2793add46214272709bd28b95`
    * RolesAuthority : `0x3ef618d5850f4352C61Da9700d97a7e8e5cA30B9`
    * Solana mint (OFT share mint) : `2GazQTpcdPkxiRyeSBKoCm2DCFUUnMxn3RfCjZ1zRQvh`

* Nest Liquid Credit Vault (nLCRD)
  * `plume`
    * BoringVault : `0xdf45b8322Ea4ce898331602E2d1F3d1A67aE0ee8`
    * Accountant : `0x334dc7fd04a3758CC597598091F3Db2d212cC7Df`
      * ProxyAdmin: `0x4475dd0e3d90bef4e2937c9de6467717b69e56bc`
    * Teller : `0x47dc8Daf3E62219A4853f1b20831278b7ac0288D`
    * NestVaultComposer (USDC) : `0x63c7a4f0D9a19BF8916837603cCDEa400d9D6295`
      * ProxyAdmin: `0xb8a605506cc05378a21b32e3394ecaa57a23de18`
    * NestVault (USDC) : `0x7195De4eAb3e43910E3BAd93882A7b15B9Eb6c8e`
      * ProxyAdmin: `0x078e875b8e17b95ec38d15b16054575a8179f09a`
    * NestVault (pUSD) : `0x67B2e065adcd7a8b5112F9582388dFb57C0BeDC2`
      * ProxyAdmin: `0x808d8f120e4041a9514610fd7465eb806a1df93d`
    * RolesAuthority : `0xD970CeA62BD2C19498Df72B74B8f5B2715913dc0`
    * Solana mint (OFT share mint) : `14BM5Nvq2kuJPn4vFNqiPM3XSBzVaqEjZrDT7ZYLS2nB`

* Nest Test Vault (nTEST)
  * `plume`
    * BoringVault : `0xED7AeA61da92f901983bD85b63ba7d217797e405`
    * Accountant : `0x5881Ae1DCA1172a33f1b6920c92CeEF99bbfdADD`
    * Teller : `0xa6dF99599254AbC496D91E4aA13529f2Ff827934`
    * Manager : `0xa9Dfd34a4D261daF28929088F5080f43911f13FF`
    * NestVault (USDC) : `0x802E1f92A6890430bCF350Ad553C936fA425266c`
      * ProxyAdmin: `0xb77e6c1d97c26df33f0d68b4dbecba2b52a63b8a`
    * RolesAuthority : `0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478`



