const { run, upgrades: upgrades2 } = require("hardhat")

const upgrades = [
	{
		contract: "StabilityPool",
		address: "0x1317F2749Cd53555B33ab75f17EB46fd57B9eFaB",
	},
]

async function main() {
	for (const { contract, address } of upgrades) {
		const newContractVersion = await ethers.getContractFactory(contract)
		console.log(`[${address}] Preparing upgrade for ${contract} ...`)
		await upgrades2.upgradeProxy(address, newContractVersion)
		console.log(`[${address}] ${contract} upgraded.`)
		try {
			await run("verify:verify", { address })
			console.log(`[${address}] ${contract} verified.`)
		} catch (error) {
			// if it was already verified, it’s like a success, so let’s move forward and save it
			if (error.name != "NomicLabsHardhatPluginError") {
				console.error(`Error verifying: ${error.name}`)
				console.error(error)
			}
		}
	}
}

main()
	.then(() => process.exit(0))
	.catch(error => {
		console.error(error)
		process.exit(1)
	})