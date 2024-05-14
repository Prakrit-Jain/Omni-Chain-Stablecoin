const ERC20Mock = artifacts.require("ERC20Mock")

const { mine, time } =require("@nomicfoundation/hardhat-network-helpers")
 
const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const { dec, toBN, assertRevert } = th
const timeValues = testHelpers.TimeValues

/*
 * NOTE: Some of the borrowing tests do not test for specific fee values. They only test that the
 * fees are non-zero when they should occur, and that they decay over time.
 *
 * Specific fee values will depend on the final fee schedule used, and the final choice for
 * the parameter MINUTE_DECAY_FACTOR in the VesselManager, which is still TBD based on economic
 * modelling.
 */

var contracts
var snapshotId
var initialSnapshotId

const openVessel = async params => th.openVessel(contracts.core, params)
const deploy = async (treasury, mintingAccounts) => {
	contracts = await deploymentHelper.deployTestContracts(treasury, mintingAccounts)

	activePool = contracts.core.activePool
	adminContract = contracts.core.adminContract
	borrowerOperations = contracts.core.borrowerOperations
	collSurplusPool = contracts.core.collSurplusPool
	debtToken = contracts.core.debtToken
	defaultPool = contracts.core.defaultPool
	erc20 = contracts.core.erc20
	feeCollector = contracts.core.feeCollector
	gasPool = contracts.core.gasPool
	priceFeed = contracts.core.priceFeedTestnet
	sortedVessels = contracts.core.sortedVessels
	stabilityPool = contracts.core.stabilityPool
	vesselManager = contracts.core.vesselManager
	vesselManagerOperations = contracts.core.vesselManagerOperations
	shortTimelock = contracts.core.shortTimelock
	longTimelock = contracts.core.longTimelock

	sprStaking = contracts.spr.sprStaking
	communityIssuance = contracts.spr.communityIssuance
}

contract("BorrowerOperations_ActiveInterest", async accounts => {
	const [owner, alice, bob, carol, dennis, whale, A, B, C, D, E, multisig, treasury] = accounts
    const INTEREST_PRECISON = dec(1,27)

	const getOpenVesselKAIAmount = async (totalDebt, asset) =>
		th.getOpenVesselKAIAmount(contracts.core, totalDebt, asset)
	const getNetBorrowingAmount = async (debtWithFee, asset) =>
		th.getNetBorrowingAmount(contracts.core, debtWithFee, asset)
	const getVesselEntireColl = async (vessel, asset) => th.getVesselEntireColl(contracts.core, vessel, asset)
	const getVesselEntireDebt = async (vessel, asset) => th.getVesselEntireDebt(contracts.core, vessel, asset)
	const getVesselStake = async (vessel, asset) => th.getVesselStake(contracts.core, vessel, asset)

	let KAI_GAS_COMPENSATION_ERC20
	let MIN_NET_DEBT_ERC20

	withProxy = false

	describe("BorrowerOperations Mechanisms", async () => {
		before(async () => {
			await deploy(treasury, [])

            // set active borrow interest for erc20 addres , interestInBPS = 1
            await th.activeInterestRate(contracts.core, erc20.address, 1)

			await feeCollector.setRouteToSPRStaking(true) // sends fees to SPRStaking instead of treasury

			KAI_GAS_COMPENSATION_ERC20 = await adminContract.getDebtTokenGasCompensation(erc20.address)
			MIN_NET_DEBT_ERC20 = await adminContract.getMinNetDebt(erc20.address)
			BORROWING_FEE_ERC20 = await adminContract.getBorrowingFee(erc20.address)

			await communityIssuance.unprotectedAddSPRHoldings(multisig, dec(5, 24))

			for (const acc of accounts.slice(0, 20)) {
				await erc20.mint(acc, await web3.eth.getBalance(acc))
			}
			const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp
			await time.setNextBlockTimestamp(currentTimestamp);
			await mine(1)

			initialSnapshotId = await network.provider.send("evm_snapshot")
		})

		beforeEach(async () => {
			snapshotId = await network.provider.send("evm_snapshot")
		})

		afterEach(async () => {
			await network.provider.send("evm_revert", [snapshotId])
		})

		after(async () => {
			await network.provider.send("evm_revert", [initialSnapshotId])
		})

		it("openVessel(): active interest rate accrued over time",async () => {
            const { collateral: aliceCollBeforeAsset, totalDebt: aliceDebtBeforeAsset } = await openVessel({
				asset: erc20.address,
				extraKAIAmount: toBN(dec(15000, 18)),
				ICR: toBN(dec(2, 18)),
				extraParams: { from: alice },
			})

            const timeDiff = 1000
            await time.increase(timeDiff)

            const aliceAccruedDebtAndPendingReward = await vesselManager.getDebtAndPendingReward(erc20.address, alice)
            const {0: aliceDebtAccrued} = aliceAccruedDebtAndPendingReward
            const alicePendingReward = await vesselManager.getPendingDebtTokenReward(erc20.address, alice)
            const aliceNewDebt_Asset = await getVesselEntireDebt(alice, erc20.address)

            const interestFactor = th.getInterestRate() * timeDiff
			const activeInterestsAccrued = (interestFactor * aliceDebtBeforeAsset) / INTEREST_PRECISON

            const totalDebt = await vesselManager.getEntireSystemDebt(erc20.address)

            assert.isTrue(totalDebt.eq(aliceDebtBeforeAsset.add(new web3.utils.BN(activeInterestsAccrued))))
            assert.isTrue(aliceDebtAccrued.eq(aliceNewDebt_Asset.sub(alicePendingReward).sub(aliceDebtBeforeAsset)))

        })

        it("openVessel(): Correctly open a vessel with active interest debt accrued with pending rewards" , async () => {
            const { collateral: aliceCollBeforeAsset, totalDebt: aliceDebtBeforeAsset } = await openVessel({
				asset: erc20.address,
				extraKAIAmount: toBN(dec(15000, 18)),
				ICR: toBN(dec(2, 18)),
				extraParams: { from: alice },
			})

            await time.increase(1000) // increase block.timestamp by 1000 seconds

			await openVessel({
				asset: erc20.address,
				extraKAIAmount: toBN(dec(10000, 18)),
				ICR: toBN(dec(2, 18)),
				extraParams: { from: bob },
			})

            const aliceAccruedDebtAndPendingReward = await vesselManager.getDebtAndPendingReward(erc20.address, alice)
			const {0: aliceDebtAccrued ,1: alicePendingReward} = aliceAccruedDebtAndPendingReward

            const aliceNewDebt_Asset = await getVesselEntireDebt(alice, erc20.address)

            assert.isTrue(aliceNewDebt_Asset.eq(aliceDebtBeforeAsset.add(aliceDebtAccrued).add(alicePendingReward)))

        })

        it("openVessel(): open a vessel and add collateral with debt accrued" , async () => {
            const { collateral: aliceCollBeforeAsset, totalDebt: aliceDebtBeforeAsset } = await openVessel({
				asset: erc20.address,
				extraKAIAmount: toBN(dec(15000, 18)),
				ICR: toBN(dec(2, 18)),
				extraParams: { from: alice },
			})

            await time.increase(1000) // increase block.timestamp by 1000 seconds

            const aliceTopUp = toBN(dec(5, "ether"))

            await borrowerOperations.addColl(erc20.address, aliceTopUp, alice, alice, {
				from: alice,
			})

			const alicePendingRewardAsset = await vesselManager.getPendingAssetReward(erc20.address, alice)

            const aliceAccruedDebtAndPendingReward = await vesselManager.getDebtAndPendingReward(erc20.address, alice)
			const {0: aliceDebtAccrued ,1: alicePendingReward} = aliceAccruedDebtAndPendingReward

            const aliceNewColl_Asset = await getVesselEntireColl(alice, erc20.address)
			const aliceNewDebt_Asset = await getVesselEntireDebt(alice, erc20.address)

            assert.isTrue(aliceNewColl_Asset.eq(aliceCollBeforeAsset.add(alicePendingRewardAsset).add(aliceTopUp)))
            assert.isTrue(aliceNewDebt_Asset.eq(aliceDebtBeforeAsset.add(aliceDebtAccrued).add(alicePendingReward)))
        })

        it("openVessel(): open a vessel then repay some debt", async () => {
            const { collateral: aliceCollBeforeAsset, totalDebt: aliceDebtBeforeAsset } = await openVessel({
				asset: erc20.address,
				extraKAIAmount: toBN(dec(15000, 18)),
				ICR: toBN(dec(2, 18)),
				extraParams: { from: alice },
			})

            await time.increase(1000) // increase block.timestamp by 1000 seconds
            
            // alice repay 2 kai
            await borrowerOperations.repayDebtTokens(erc20.address, dec(2, 18), alice, alice, {
                from: alice,
            })

            const aliceAccruedDebtAndPendingReward = await vesselManager.getDebtAndPendingReward(erc20.address, alice)
			const {0: aliceDebtAccrued ,1: alicePendingReward} = aliceAccruedDebtAndPendingReward

            const aliceNewDebt_Asset = await getVesselEntireDebt(alice, erc20.address)
            // newDebt = oldDebt - repayAmount + debtAccrued + reward
            assert.isTrue(aliceNewDebt_Asset.eq(aliceDebtBeforeAsset.sub(new web3.utils.BN(dec(2, 18))).add(aliceDebtAccrued).add(alicePendingReward)))
        })

	})
})

contract("Reset chain state", async accounts => {})
