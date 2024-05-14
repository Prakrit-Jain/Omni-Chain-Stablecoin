const { assert } = require("chai")
const { mine, time } =require("@nomicfoundation/hardhat-network-helpers")
const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const { dec, toBN, getDifference } = th

var contracts
var snapshotId
var initialSnapshotId

const deploy = async (treasury, mintingAccounts) => {
	contracts = await deploymentHelper.deployTestContracts(treasury, mintingAccounts)

	activePool = contracts.core.activePool
	adminContract = contracts.core.adminContract
	borrowerOperations = contracts.core.borrowerOperations
	collSurplusPool = contracts.core.collSurplusPool
	debtToken = contracts.core.debtToken
	defaultPool = contracts.core.defaultPool
	erc20 = contracts.core.erc20
	erc20B = contracts.core.erc20B
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

contract("VesselManager_ActiveInterest", async accounts => {
	const [owner, alice, bob, carol, dennis, erin, freddy, A, B, C, D, E, treasury] = accounts
	const INTEREST_PRECISON = dec(1,27)

	const getNetBorrowingAmount = async (debtWithFee, asset) => th.getNetBorrowingAmount(contracts.core, debtWithFee, asset)
	const openVessel = async params => th.openVessel(contracts.core, params)

	before(async () => {
		await deploy(treasury, accounts.slice(0, 20))
		initialSnapshotId = await network.provider.send("evm_snapshot")
		const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp

		// set active borrow interest for erc20 addres , interestRateInBPS = 1
		await th.activeInterestRate(contracts.core, erc20.address, 1)

		await time.setNextBlockTimestamp(currentTimestamp);
		await mine(1)
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

	it("collectInterests(): Fee collector collects accrued interest rate", async () => {
		// A, B open vessel
		const { collateral: A_coll_Asset, totalDebt: A_totalDebt_Asset } = await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(400, 16)),
			extraParams: { from: alice },
		})

        const timePass = 1000 // 1000 seconds passed
        await time.increase(timePass)

		// interests accrued on any debt change operation 
		await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(400, 16)),
			extraParams: { from: bob },
		})
		const balanceBefore = await debtToken.balanceOf(feeCollector.address)

        const interestFactor = th.getInterestRate() * timePass
        const activeInterestsAccrued = (interestFactor * A_totalDebt_Asset) / INTEREST_PRECISON

        await vesselManager.collectInterests(erc20.address)

		const balanceAfter = await debtToken.balanceOf(feeCollector.address)
	
		th.assertIsApproximatelyEqual(new web3.utils.BN(activeInterestsAccrued), (balanceAfter.sub(balanceBefore)))

	})

	it("liquidate(): decreases ActivePool ETH and KAIDebt by correct amounts", async () => {
		// --- SETUP ---				
		const { collateral: A_collateral_Asset, totalDebt: A_totalDebt_Asset } = await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(4, 18)),
			extraParams: { from: alice },
		})

		await time.increase(1000) // 1000 seconds passed

		const { collateral: B_collateral_Asset, totalDebt: B_totalDebt_Asset } = await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(21, 17)),
			extraParams: { from: bob },
		})

		const aliceDebtAndPendingReward = await vesselManager.getDebtAndPendingReward(erc20.address, alice)
		const aliceDebtAccrued = aliceDebtAndPendingReward[0]

		// --- TEST ---
		// check ActivePool ETH and KAI debt before
		const activePool_ETH_Before_Asset = (await activePool.getAssetBalance(erc20.address)).toString()
		const activePool_RawEther_Before_Asset = (await erc20.balanceOf(activePool.address)).toString()
		const activePooL_KAIDebt_Before_Asset = (await activePool.getDebtTokenBalance(erc20.address)).toString()
		assert.equal(activePool_ETH_Before_Asset, A_collateral_Asset.add(B_collateral_Asset))
		assert.equal(activePool_RawEther_Before_Asset, A_collateral_Asset.add(B_collateral_Asset))
		
		// assert.equal(activePooL_KAIDebt_Before_Asset)
		th.assertIsApproximatelyEqual(activePooL_KAIDebt_Before_Asset, A_totalDebt_Asset.add(B_totalDebt_Asset).add(new web3.utils.BN(aliceDebtAccrued)))
		// price drops to 1ETH:100KAI, reducing Bob's ICR below MCR
		await priceFeed.setPrice(erc20.address, "100000000000000000000")

		// Confirm system is not in Recovery Mode
		assert.isFalse(await th.checkRecoveryMode(contracts.core, erc20.address))

		await time.increase(1000) // 1000 seconds passed
		/* close Bob's Vessel. Should liquidate his ether and KAI,
		   leaving Alice’s ether and KAI debt in the ActivePool. */
		await vesselManagerOperations.liquidate(erc20.address, bob, { from: owner })

		// check ActivePool ETH and KAI debt
		const activePool_ETH_After_Asset = (await activePool.getAssetBalance(erc20.address)).toString()
		const activePool_RawEther_After_Asset = (await erc20.balanceOf(activePool.address)).toString()
		const activePooL_KAIDebt_After_Asset = (await activePool.getDebtTokenBalance(erc20.address)).toString()
		
		assert.equal(activePool_ETH_After_Asset, A_collateral_Asset)
		assert.equal(activePool_RawEther_After_Asset, A_collateral_Asset)
		// after liquidation only initial debt will be left
		th.assertIsApproximatelyEqual(activePooL_KAIDebt_After_Asset, A_totalDebt_Asset)
	})

	it("checkRecoveryMode(): returns true when TCR = 150% get reduces due to debt increased over time", async () => {
		await priceFeed.setPrice(erc20.address, dec(100, 18))

		await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(150, 16)),
			extraParams: { from: alice },
		})

		await time.increase(1000) // 1000 seconds passed

		await openVessel({
			asset: erc20.address,
			ICR: toBN(dec(150, 16)),
			extraParams: { from: bob },
		})

		// TCR < 150 % due to increase in debt because of active interest rate
		const TCR_Asset = await th.getTCR(contracts.core, erc20.address)
		const expectedTCR_Asset = await th.getExpectedTCR(contracts.core, erc20.address)

		assert.equal(TCR_Asset, expectedTCR_Asset)

		assert.isTrue(await th.checkRecoveryMode(contracts.core, erc20.address))
	})
})

contract("Reset chain state", async accounts => {})