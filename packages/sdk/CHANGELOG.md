## [1.0.0](https://github.com/ReineiraOS/protocol/compare/sdk-v0.3.2...sdk-v1.0.0) (2026-06-08)

### ⚠ BREAKING CHANGES

* **AP-15:** Storage layout incompatible with v0.1 deployments

Changes:
- Replace _escrowCovered bool flag with _escrowCoverages uint256[] mapping
- Add _coveragePaid mapping for per-(escrow, coverage) duplicate payment tracking
- Modify escrow _stampFee to accumulate underwriter fees from multiple coverages
- Add getCoveragesForEscrow() and isCoveragePaid() view functions
- Add CoverageAlreadyPaid error to prevent duplicate claims
- Update tests to verify multi-coverage flows
- Add comprehensive storage migration documentation

Resolves: AP-15
Coordinates with: DEV-67, DEV-70, AP-36
Blocks: AP-14
* **escrow:** for any external resolver implementer.

After this commit core contracts no longer compile (fixed in
following commits).

* feat(escrow): add 6 fee module contracts (plain + confidential)

Plain modules:
- ProtocolFeeModule: stateful, stores (uint16 bps, address treasury);
  owner-configurable via setProtocolFee.
- ConditionFeeModule: stateless wrapper around
  IConditionResolver.getConditionFee with MAX_CONDITION_FEE_BPS
  guard (reverts on overage).
- UnderwriterPolicyFeeModule: stateless pass-through validator
  (placeholder for future per-pool caps / blacklists).

Confidential mirrors with FHE math:
- ConfidentialProtocolFeeModule: stores plain uint16 (public config),
  returns FHE.asEuint64 with allowTransient choreography.
- ConfidentialConditionFeeModule: queries plain
  IConditionResolver.getConditionFee, validates against
  MAX_CONDITION_FEE_BPS (plain revert path), encrypts result.
  Confidential resolver interface dropped — condition fees stay
  plaintext even in FHE branch (resolver authorship is public).
- ConfidentialUnderwriterPolicyFeeModule: FHE pass-through with
  allowTransient.

All modules inherit TestnetCoreBase (Initializable + UUPS + Ownable
+ ReentrancyGuard + ERC2771).

* refactor(escrow): rewrite Escrow.sol + ConfidentialEscrow.sol with bps-stamping

Storage:
- Fee struct: uint256 amount -> uint16 bps (euint64 bps in
  confidential variant), recipient + set unchanged.
- _fees mapping: single Fee -> Fee[4] indexed by FeeKind.
- New _totalStampedBps tracker (uint16 plain / euint64 confidential)
  enforces sum invariant.
- Drop _insuranceManager, replace with _coverageManager.
- Add _feeModules[4] and _reservedBpsForKind[4] fixed arrays.

Lifecycle:
- Escrow.create now calls _stampProtocolFee(escrowId) right after
  the EscrowData write, and _stampConditionFee(escrowId, resolver)
  right after _setCondition.
- New setUnderwriterFee(escrowId, holder, effectiveBps, recipient)
  callable only by _coverageManager; preserves branchless
  (holder == owner || holder == caller) auth.
- redeem and redeemMultiple iterate the 4 fee slots and distribute
  proportionally: amount_i = (paidAmount * bps_i) / 10000.
  No external calls — fees are pre-stamped from module values.
  Confidential branch uses FHE.mul + FHE.div with FHE.asEuint64
  for the bps and divisor constants.

Invariants enforced at stamp time:
- sum(bps_i) <= MAX_TOTAL_BPS (revert in plain, FHE.select silent
  cap in confidential — required because revert on encrypted
  comparison would leak the bps).
- bps_i <= reservedBpsForKind[i] if reserved budget is set.

setReservedBps enforces sum of all reservations <= MAX_TOTAL_BPS.

Storage layout incompatible with previous Escrow proxies —
redeploy required on Arbitrum Sepolia (testnet only, contracts
marked "TODO: Remove upgradability after testnet").

* refactor(escrow): swap MockInsuranceManager for MockCoverageManager

- Delete MockInsuranceManager + MockConfidentialInsuranceManager.
- Add MockCoverageManager + MockConfidentialCoverageManager —
  thin adapters that call escrow.setUnderwriterFee with the new
  (holder, effectiveBps, recipient) shape. Confidential variant
  performs FHE.allow choreography for holder + bps before the call.
- Extend MockConditionResolver with feeBps + feeRecipient state
  and getConditionFee getter for testing the condition-fee
  stamping path.

* refactor(insurance): migrate CoverageManager to new fee API

CoverageManager._computeAndSetFee:
- Fetch escrowAmount via _escrow.getAmount(escrowId).
- Compute effectiveBps = (coverageAmount * riskScore) / escrowAmount
  (clamped to 10000). Encodes the existing absolute-premium formula
  premium = coverage * risk / 10000 as a fraction of escrowAmount.
- Skip stamping if escrowAmount == 0 (defensive).
- Call escrow.setUnderwriterFee(escrowId, holder, uint16 bps, pool).

ConfidentialCoverageManager: same logic with FHE primitives.
Split _capCoverage into its own helper and bundle finalization
args into PurchaseParams struct to keep stack pressure under the
16-slot limit (viaIR catches the rest).

External interfaces (insurance/interfaces/external):
- IEscrow.setFeeFromInsurance -> setUnderwriterFee with uint16 bps.
- IConfidentialEscrow.setFeeFromInsurance -> setUnderwriterFee
  with euint64 effectiveBps.

Mocks (MockEscrow / MockConfidentialEscrow): match new interface;
expose getFeeBps for tests.

After this commit all contracts compile across packages.

* test(escrow): rewrite tests for bps-based fee distribution

Escrow.t.sol (full rewrite):
- Wire ProtocolFeeModule + ConditionFeeModule +
  UnderwriterPolicyFeeModule via _registerAllModules helper.
- New coverage: protocol fee stamp on create, condition fee stamp
  via resolver, MAX_CONDITION_FEE_BPS guard, branchless auth for
  underwriter fee, NotCoverageManager guard, FeeBudgetExceeded,
  proportional distribution, total stamped bps tracker,
  setReservedBps global cap enforcement.

ConfidentialEscrowFHE.t.sol: same shape with FHE primitives;
uses MockConfidentialCoverageManager + Confidential-prefixed
modules. Preserves the branchless-auth FHE test.

ConfidentialEscrow.t.sol + EscrowSettlement.t.sol: minimal patch —
rename setInsuranceManager -> setCoverageManager / event renames,
swap absolute FEE_AMOUNT for FEE_BPS in settlement test.

All 137 escrow tests passing.

* chore(escrow): update deploy scripts to register fee modules

Deploy and ConfidentialDeploy:
1. Deploy Escrow / ConfidentialEscrow proxy.
2. Deploy three module proxies (Protocol with 25 bps default
   + treasury, Condition stateless, Underwriter stateless).
3. registerFeeModule for each kind on the escrow.
4. setReservedBps: Protocol=25, Condition=1000, Underwriter=8000
   (sum 9025, leaves 975 headroom for DEV-119 royalty in
   Reserved slot).
5. Deploy CCTPV2 receiver as before.

Reads PROTOCOL_TREASURY env var (defaults to deployer for testnet).

Old setInsuranceManager wiring removed.

* feat(sdk): sync ABIs + event types with new fee API

Both CONFIDENTIAL_ESCROW_ABI and PLAIN_ESCROW_ABI:
- Remove setFeeFromInsurance, setInsuranceManager, FeeSet event,
  InsuranceManagerSet event.
- Add setUnderwriterFee, setCoverageManager, registerFeeModule,
  setReservedBps; view methods getFee/getFeeModule/
  getReservedBps/getTotalStampedBps; events FeeStamped,
  FeeDistributed, FeeModuleRegistered, CoverageManagerSet,
  ReservedBpsUpdated.

EscrowEventName union updated accordingly. SDK consumers will
fail at compile time if they reference removed event names —
intentional, breaking change.

78 SDK tests still passing.

* docs(arch): add DEV-35 fee system ADR + decision docs

docs/architecture/fee-system.md (new ADR):
- Architecture overview (storage layout, lifecycle, invariants)
- Reserved budget defaults table
- Module catalogue
- Module mutability rules
- Breaking changes summary
- Deferred items (INS-MN-01, DEV-119, fixed fees, cancel flow)

tasks/dev-35-variants.md: full decision history — 7 architectural
variants evaluated (F/A/D/B/C/G/H) with comparison matrix, plus
4 product questions resolved (cap order, versioned config,
resolver cap, module mutability).

tasks/dev-35-implementation-plan.md: the implementation plan
this branch follows (file-by-file change list, lifecycle
walkthrough, verification steps).

* chore(tasks): drop dev-35 tracking files

### Features

* **AP-15:** Multi-recipient underwriter fees + remove dead error ([4504a52](https://github.com/ReineiraOS/protocol/commit/4504a520e9c183abc24e7b855ccd68a09a681649))
* **AP-15:** Support multiple coverages per escrow ([1e67426](https://github.com/ReineiraOS/protocol/commit/1e6742622e7d280a32a624fa7697798987b07268))
* **AP-36:** Introduce IEscrow interface abstraction ([10d5aaa](https://github.com/ReineiraOS/protocol/commit/10d5aaa97938c0b6f2e2b13f26092f252c380f7b))
* **escrow:** DEV-35 fee system restructuring (plugin modules + bps) ([#25](https://github.com/ReineiraOS/protocol/issues/25)) ([c958fd4](https://github.com/ReineiraOS/protocol/commit/c958fd4c0b7815463468eee38fb38d43691ad014)), closes [#5](https://github.com/ReineiraOS/protocol/issues/5)
* **insurance:** DEV-43 open/private pools + multi-owner role separation ([3cf070b](https://github.com/ReineiraOS/protocol/commit/3cf070bcb2398327665ebc4126cb20ed023283b4)), closes [#32](https://github.com/ReineiraOS/protocol/issues/32) [#26](https://github.com/ReineiraOS/protocol/issues/26) [#32](https://github.com/ReineiraOS/protocol/issues/32) [#30](https://github.com/ReineiraOS/protocol/issues/30)
* **insurance:** pool liquidity routing foundation (DEV-114) ([b92079c](https://github.com/ReineiraOS/protocol/commit/b92079c9dbff3a6f1e789bfdc5dd837990a34401))
* **insurance:** StrategyRouter — allocation controls (DEV-115) ([af193c3](https://github.com/ReineiraOS/protocol/commit/af193c382ab6d4288ab0d204fbd755c07c6c444d))
* **shared:** CoverageInviteLib — EIP-712 closed-pool admission voucher ([#32](https://github.com/ReineiraOS/protocol/issues/32)) ([916f1a7](https://github.com/ReineiraOS/protocol/commit/916f1a7836bdf23c929d7aa63f813a0e0981b8be))

### Bug Fixes

* Add escrow setup in max coverages unit tests ([835f21b](https://github.com/ReineiraOS/protocol/commit/835f21bb0fc2004d4f5d58ff5480831e3abf6f58))
* **AP-15:** Add MAX_COVERAGES_PER_ESCROW limit and update tests ([2f71877](https://github.com/ReineiraOS/protocol/commit/2f718773efcc9ca673ecbd17a75bda27cbe609cd))
* **insurance/router:** clear pending maxDebt state on detach + reject execute on detached adapter ([79526fe](https://github.com/ReineiraOS/protocol/commit/79526fef79e7e974bb4c55721594383df124796f)), closes [#31](https://github.com/ReineiraOS/protocol/issues/31)
* **sdk:** coerce plain coverage status to a number enum ([c7ca48c](https://github.com/ReineiraOS/protocol/commit/c7ca48ca332a776cb31a9c9ff5fe4c6a415e86d6))

### Refactors

* **insurance:** drop duplicate errors from interfaces, route reverts via libs ([72f1028](https://github.com/ReineiraOS/protocol/commit/72f10285e77562fca4624652c7e5ba8f050f66d0))
* **insurance:** extract IXEvents interfaces and dedupe event declarations ([771db60](https://github.com/ReineiraOS/protocol/commit/771db608439fa90a0df33b6d3e132ab5e16c6643))

## [0.3.2](https://github.com/ReineiraOS/protocol/compare/sdk-v0.3.1...sdk-v0.3.2) (2026-05-04)

### Bug Fixes

* **mcp-docs:** unblock deploy — exact category filter + test fix ([#16](https://github.com/ReineiraOS/protocol/issues/16)) ([9a9b9c5](https://github.com/ReineiraOS/protocol/commit/9a9b9c5dfd66efebb86f7f6e9af4db0756d7ef5f)), closes [#11](https://github.com/ReineiraOS/protocol/issues/11)

## [0.3.1](https://github.com/ReineiraOS/protocol/compare/sdk-v0.3.0...sdk-v0.3.1) (2026-05-01)

### Refactors

* **escrow:** drop duplicate errors from interfaces, route reverts via EscrowLib ([feb6097](https://github.com/ReineiraOS/protocol/commit/feb609764103c39901fa196b1931449c51e7b801))
* **escrow:** extract IEscrowEvents and dedupe event declarations ([5520919](https://github.com/ReineiraOS/protocol/commit/552091947a51b2087a4d4d72b990927b9a08c3d6))
* **escrow:** merge ConfidentialEscrowCondition into EscrowCondition ([c7a8b31](https://github.com/ReineiraOS/protocol/commit/c7a8b3171f9ad10779cc713caf853fdf416261cb))

## [0.3.0](https://github.com/ReineiraOS/protocol/compare/sdk-v0.2.0...sdk-v0.3.0) (2026-04-30)

### Features

* **escrow+insurance:** add plain Deploy.s.sol scripts ([0c83bec](https://github.com/ReineiraOS/protocol/commit/0c83bec31844ba2639e9acc0472afb156de0c3fb))
* **escrow+insurance:** add plain mocks under bare names ([6a7b940](https://github.com/ReineiraOS/protocol/commit/6a7b94076ec4afe1da908c079b5b76ea007fbcb4))
* **escrow:** add plain Escrow + CCTPV2EscrowReceiver ([12e3bb9](https://github.com/ReineiraOS/protocol/commit/12e3bb91b537bc1f7bf675b8ced4e56407401218))
* **insurance:** add plain InsurancePool, PoolFactory, PolicyRegistry, CoverageManager ([7d54410](https://github.com/ReineiraOS/protocol/commit/7d54410c5ab506827087492869887cc648cfaeac))
* migrate Hardhat to Foundry across all Solidity packages (PRVD-32) ([c8919f5](https://github.com/ReineiraOS/protocol/commit/c8919f5d78994ef4e0fba3060ce0da33791ede3b))
* **sdk:** add plain (non-FHE) modules for mainnet launch path ([f3f2d23](https://github.com/ReineiraOS/protocol/commit/f3f2d238647a7b49c3764c94fb1483bd71068039))
* **shared:** add plain libraries and interfaces for plain mode ([3e02346](https://github.com/ReineiraOS/protocol/commit/3e023463d43fdbc02c0638ecaf8f530b8ed92645))

### Bug Fixes

* **ci:** add .prettierignore to exclude auto-generated CHANGELOG ([335dba3](https://github.com/ReineiraOS/protocol/commit/335dba308ad62a69cc51f923451c516136d1c53f))
* **ci:** format docs markdown files (pre-existing on main) ([dc8f95b](https://github.com/ReineiraOS/protocol/commit/dc8f95bbfdc52af9ece159f197eb5524ade3c939))
* **ci:** install Foundry in publish-sdk workflow ([0828170](https://github.com/ReineiraOS/protocol/commit/08281703a0c93f048c8fade2d2158e9768a7b215))
* **ci:** resolve pipeline failures after Foundry migration ([2a2b907](https://github.com/ReineiraOS/protocol/commit/2a2b9077b2f0d887e63020932e3e8b97e444062e))
* **ci:** revert sdk CHANGELOG formatting (pre-existing issue on main) ([5a40eff](https://github.com/ReineiraOS/protocol/commit/5a40eff320afedc88ec8ae4fe308346e6fa1ef3f))
* **ci:** scope offchain pnpm scripts to local packages only ([dace35b](https://github.com/ReineiraOS/protocol/commit/dace35ba7c1451b6c64317cfe20309f509323080))
* clean up Hardhat remnants from Foundry migration ([da09c9b](https://github.com/ReineiraOS/protocol/commit/da09c9b71f5e083c8f8b8dcc28467079477c8c0a))
* **insurance:** add access control to PolicyRegistry and PoolFactory ([20c8edf](https://github.com/ReineiraOS/protocol/commit/20c8edf795e6ee745db031965b7bc7c81eae05ef))
* **sdk:** replace ethers NonceManager with SequentialNonceWallet ([a86dc0e](https://github.com/ReineiraOS/protocol/commit/a86dc0e9c246a07bb92feb8e53a2b4b97ad9480b))
* **sdk:** use getRedeemedStatus to match plain Escrow contract ([4c77e3b](https://github.com/ReineiraOS/protocol/commit/4c77e3b454fd94190a11c3ebd6038ad3afdb42bf))

### Refactors

* **escrow+insurance:** rename FHE contracts to Confidential* prefix ([5506f4f](https://github.com/ReineiraOS/protocol/commit/5506f4ff96a4a285365d2769195a23296fcd1a3a))
* **escrow:** rename ICCTPV2EscrowReceiver interface to ICCTPV2ConfidentialEscrowReceiver ([dc6fc04](https://github.com/ReineiraOS/protocol/commit/dc6fc04c15283a694d6a41e426a58b2eea80e271))

## [0.2.0](https://github.com/ReineiraOS/protocol/compare/sdk-v0.1.1...sdk-v0.2.0) (2026-03-22)

### Features

* add MCP docs server to monorepo ([c707a67](https://github.com/ReineiraOS/protocol/commit/c707a6733fba3d374ccd85e473ecbd4e321af804))

### Bug Fixes

* **ci:** add pnpm bin to PATH for SAM esbuild discovery ([34cbe16](https://github.com/ReineiraOS/protocol/commit/34cbe16d405581ad6b2edc0edc0580b89c1cccc7))
* **ci:** correct setup-sam action SHA pin ([a127313](https://github.com/ReineiraOS/protocol/commit/a127313fea829875cea25a4e03c9773ad27ba2e8))
* **ci:** install esbuild globally for SAM build + self-trigger path ([ae38cfe](https://github.com/ReineiraOS/protocol/commit/ae38cfe686ac759a2a7bae03b56f324cc21867ed))
* **ci:** pass SAM deploy params inline (samconfig.toml is gitignored) ([8d34a4a](https://github.com/ReineiraOS/protocol/commit/8d34a4ad9a9e2ea409de2f77d732a198d4dc53eb))
* **mcp-docs:** add esbuild as devDependency for SAM build in CI ([4ea2a7e](https://github.com/ReineiraOS/protocol/commit/4ea2a7ed200d961770dd8ceedbab13f6d7af2b96))
* **mcp-docs:** create content output dir before bundling ([f1bc5af](https://github.com/ReineiraOS/protocol/commit/f1bc5af02be9f8ee01c923f8a3257c9e657f57ff))
* update litepaper build path and rebuild PDFs for cUSDC rename ([53591e2](https://github.com/ReineiraOS/protocol/commit/53591e2ac8647fb7797ac849474b8b83f7d04d6e))

### Refactors

* **mcp-docs:** clean up tools, migrate to registerTool, fix deploy config ([7fab973](https://github.com/ReineiraOS/protocol/commit/7fab973d555a0643b739c146aa3822d0ae7fa6ff))
* **sdk:** rename .withInsurance() to .insurance() on EscrowBuilder ([b8929ca](https://github.com/ReineiraOS/protocol/commit/b8929cae8ff6d958886b4842f4521bf0acef9056))

## [0.1.1](https://github.com/ReineiraOS/protocol/compare/sdk-v0.1.0...sdk-v0.1.1) (2026-03-20)

### Bug Fixes

* CCTPV2EscrowReceiver FHE test 2-arg initialize + format CHANGELOG ([d6ca4ae](https://github.com/ReineiraOS/protocol/commit/d6ca4aeef2de20027107823d18e24b4c3b8d2237))
* format files and update CCTPV2EscrowReceiver test for 2-arg initialize ([8bc0606](https://github.com/ReineiraOS/protocol/commit/8bc06065d7e6ea13d42f0c849db8f3c7d93913b0))
* **offchain:** disable unsafe-* eslint rules globally for operator-cli compat ([928c82f](https://github.com/ReineiraOS/protocol/commit/928c82fe1dbb9db634ce53fccfdcfe8b2f37531c))
* **offchain:** fix CI failures — types, eslint, and test script ([6ce8943](https://github.com/ReineiraOS/protocol/commit/6ce8943b4d80b19ab1990f3751c9253ec2149724))
* remove wrapper references from upgrade-escrow task ([f321966](https://github.com/ReineiraOS/protocol/commit/f321966be6998593c368f4b5d0a693180fbf3165))
* restrict TypeScript types to node in offchain packages + fix integration test ([ba32b85](https://github.com/ReineiraOS/protocol/commit/ba32b856267d82344a41b403bef046ed83558e18))

### Refactors

* **escrow:** remove ConfidentialEscrowUnwrap extension ([98589d4](https://github.com/ReineiraOS/protocol/commit/98589d46dca151ce849abdaac93701f9e2853b53))

## [0.1.0](https://github.com/ReineiraOS/protocol/compare/sdk-v0.0.0...sdk-v0.1.0) (2026-03-16)

### Features

- add staging E2E infrastructure and fix SDK bugs ([75f0b7e](https://github.com/ReineiraOS/protocol/commit/75f0b7e7454411b7374d3ed09de624d4e2f513d2))
- **protocol:** add core protocol packages ([cfba4c6](https://github.com/ReineiraOS/protocol/commit/cfba4c68fa9eb2b0e7ef8277bb7720d965bbba39))
- **sdk:** add @reineira/sdk TypeScript SDK ([c7158d8](https://github.com/ReineiraOS/protocol/commit/c7158d837c6a4acebce3b968b4ea9466b98da7dd))

### Refactors

- rename [@reineira](https://github.com/reineira) scope to [@reineira-os](https://github.com/reineira-os), update CI to Node 24, and refresh docs ([26c090c](https://github.com/ReineiraOS/protocol/commit/26c090c5fc16e916aaa775ec55553f6bdbca912f))
- rename packages/operators to packages/offchain ([9724a6e](https://github.com/ReineiraOS/protocol/commit/9724a6eacedb4ca7644267787da5298a1b080933))
