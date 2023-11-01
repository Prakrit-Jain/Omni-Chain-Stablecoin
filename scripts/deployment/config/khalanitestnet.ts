import { BigNumber, utils } from "ethers"
const toEther = (val: any): BigNumber => utils.parseEther(String(val))

const OUTPUT_FILE = "./scripts/deployment/output/khalanitestnet.json"
const TX_CONFIRMATIONS = 2
const ETHERSCAN_BASE_URL = "https://block-explorer.testnet.khalani.network/"

const CONTRACT_UPGRADES_ADMIN = "0x26545b681d42c37fC765dCb0235d96162Bfddc90"
const SYSTEM_PARAMS_ADMIN = "0x26545b681d42c37fC765dCb0235d96162Bfddc90"
const TREASURY_WALLET = "0x26545b681d42c37fC765dCb0235d96162Bfddc90"

const COLLATERAL = [
	{
		name: "stkKlnUSDT",
		address: "0x2A1Da0bDa639d44298Ce89866c25512cBBC8D755",
		oracleAddress: "0x48731cF7e84dc94C5f84577882c14Be11a5B7456",
		oracleTimeoutMinutes: 1440,
		oracleIsEthIndexed: false,
		MCR: toEther(1.050),
		CCR: toEther(1.4),
		minNetDebt: toEther(200),
		gasCompensation: toEther(20),
		mintCap: toEther(1_500_000),
	},
    {
		name: "StkKlnUSDC",
		address: "0xF3fA74E1d5Fd30b7E384335C84413EFe4153f811",
		oracleAddress: "0x48731cF7e84dc94C5f84577882c14Be11a5B7456",
		oracleTimeoutMinutes: 1440,
		oracleIsEthIndexed: false,
		MCR: toEther(1.050),
		CCR: toEther(1.4),
		minNetDebt: toEther(200),
		gasCompensation: toEther(20),
		mintCap: toEther(1_500_000),
	},
    {
		name: "stkKlnBUSD",
		address: "0x1A13B1429d13b3C7aE656f4DFfF6a99eAFA84Cd1",
		oracleAddress: "0x48731cF7e84dc94C5f84577882c14Be11a5B7456",
		oracleTimeoutMinutes: 1440,
		oracleIsEthIndexed: false,
		MCR: toEther(1.050),
		CCR: toEther(1.4),
		minNetDebt: toEther(200),
		gasCompensation: toEther(20),
		mintCap: toEther(1_500_000),
	},

]

module.exports = {
	COLLATERAL,
	CONTRACT_UPGRADES_ADMIN,
	ETHERSCAN_BASE_URL,
	OUTPUT_FILE,
	SYSTEM_PARAMS_ADMIN,
	TREASURY_WALLET,
	TX_CONFIRMATIONS,
}
