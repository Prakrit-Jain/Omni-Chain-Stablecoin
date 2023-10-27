const SprtDeploymentHelper = require("../utils/deploymentHelper-Sprt.js")
const { Deployer } = require("./deployer-common.js")

/**
 * Exported deployment script, invoked from hardhat tasks defined on hardhat.config.js
 */
class SprtDeployer extends Deployer {
	helper
	coreContracts
	SprtContracts
	deploymentState

	constructor(hre, targetNetwork) {
		super(hre, targetNetwork)
		this.helper = new SprtDeploymentHelper(this.hre, this.config, this.deployerWallet)
		this.deploymentState = this.helper.loadPreviousDeployment()
	}

	async run() {
		console.log(`Deploying Gravita SPRT on ${this.targetNetwork}...`)

		await this.printDeployerBalance()

		// SprtContracts = await helper.deploySprtContracts(TREASURY_WALLET, deploymentState)
		// await deployOnlySPRTContracts()
		// await helper.connectSprtContractsToCore(SprtContracts, coreContracts, TREASURY_WALLET)
		// await approveSPRTTokenAllowanceForCommunityIssuance()
		// await this.transferSprtContractsOwnerships()

		this.helper.saveDeployment(this.deploymentState)

		await this.transferContractsOwnerships(this.coreContracts)

		await this.printDeployerBalance()
	}

	async deployOnlySPRTContracts() {
		console.log("INIT SPRT ONLY")
		const partialContracts = await helper.deployPartially(TREASURY_WALLET, deploymentState)
		// create vesting rule to beneficiaries
		console.log("Beneficiaries")
		if (
			(await partialContracts.SPRTToken.allowance(deployerWallet.address, partialContracts.lockedSprt.address)) == 0
		) {
			await partialContracts.SPRTToken.approve(partialContracts.lockedSprt.address, ethers.constants.MaxUint256)
		}
		for (const [wallet, amount] of Object.entries(config.SPRT_BENEFICIARIES)) {
			if (amount == 0) continue
			if (!(await partialContracts.lockedSprt.isEntityExits(wallet))) {
				console.log("Beneficiary: %s for %s", wallet, amount)
				const txReceipt = await helper.sendAndWaitForTransaction(
					partialContracts.lockedSprt.addEntityVesting(wallet, amount.concat("0".repeat(18)))
				)
				deploymentState[wallet] = {
					amount: amount,
					txHash: txReceipt.transactionHash,
				}
				helper.saveDeployment(deploymentState)
			}
		}
		await transferOwnership(partialContracts.lockedSprt, TREASURY_WALLET)
		const balance = await partialContracts.SPRTToken.balanceOf(deployerWallet.address)
		console.log(`Sending ${balance} SPRT to ${TREASURY_WALLET}`)
		await partialContracts.SPRTToken.transfer(TREASURY_WALLET, balance)
		console.log(`deployerETHBalance after: ${await ethers.provider.getBalance(deployerWallet.address)}`)
	}

	async approveSPRTTokenAllowanceForCommunityIssuance() {
		const allowance = await SprtContracts.SPRTToken.allowance(
			deployerWallet.address,
			SprtContracts.communityIssuance.address
		)
		if (allowance == 0) {
			await SprtContracts.SPRTToken.approve(SprtContracts.communityIssuance.address, ethers.constants.MaxUint256)
		}
	}
}

module.exports = CoreDeployer
