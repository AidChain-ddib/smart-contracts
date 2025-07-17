const {
  Client,
  AccountId,
  PrivateKey,
  ContractCreateFlow,
  ContractExecuteTransaction,
  ContractCallQuery,
  Hbar,
  ContractFunctionParameters,
} = require("@hashgraph/sdk");
const fs = require("fs");
require("dotenv").config();

async function deployWithHederaSDK() {
  console.log("🚀 Starting Hedera Smart Contract Deployment with SDK...");

  const client = Client.forTestnet();
  const accountId = AccountId.fromString(process.env.HEDERA_TESTNET_ACCOUNT_ID);
  const privateKey = PrivateKey.fromString(
    process.env.HEDERA_TESTNET_PRIVATE_KEY
  );

  client.setOperator(accountId, privateKey);

  const platformWallet =
    process.env.PLATFORM_WALLET_ADDRESS || accountId.toString();
  console.log("📝 Deploying contracts with account:", accountId.toString());
  console.log("💰 Platform wallet address:", platformWallet);

  try {
    console.log("\n1️⃣ Deploying ProjectRegistry...");
    const projectRegistryId = await deployContract(client, "ProjectRegistry", [
      platformWallet,
    ]);
    console.log(
      "✅ ProjectRegistry deployed with ID:",
      projectRegistryId.toString()
    );

    console.log("\n2️⃣ Deploying DisputeResolution...");
    const disputeResolutionId = await deployContract(
      client,
      "DisputeResolution",
      [projectRegistryId.toString()]
    );
    console.log(
      "✅ DisputeResolution deployed with ID:",
      disputeResolutionId.toString()
    );

    console.log("\n3️⃣ Deploying ReputationSystem...");
    const reputationSystemId = await deployContract(
      client,
      "ReputationSystem",
      [projectRegistryId.toString(), disputeResolutionId.toString()]
    );
    console.log(
      "✅ ReputationSystem deployed with ID:",
      reputationSystemId.toString()
    );

    const deploymentInfo = {
      network: "hedera-testnet",
      deployer: accountId.toString(),
      platformWallet: platformWallet,
      contracts: {
        ProjectRegistry: projectRegistryId.toString(),
        DisputeResolution: disputeResolutionId.toString(),
        ReputationSystem: reputationSystemId.toString(),
      },
      deploymentTime: new Date().toISOString(),
    };

    if (!fs.existsSync("deployments")) {
      fs.mkdirSync("deployments");
    }

    fs.writeFileSync(
      "deployments/hedera_testnet_deployment.json",
      JSON.stringify(deploymentInfo, null, 2)
    );

    console.log("\n🎉 All contracts deployed successfully!");
    console.log(
      "📁 Deployment info saved to: deployments/hedera_testnet_deployment.json"
    );

    return deploymentInfo;
  } catch (error) {
    console.error("❌ Deployment failed:", error);
    throw error;
  } finally {
    client.close();
  }
}

async function deployContract(client, contractName, constructorParams = []) {
  try {
    console.log(`\n📋 Processing ${contractName} deployment...`);

    const contractPath = `artifacts/contracts/contracts.sol/${contractName}.json`;
    if (!fs.existsSync(contractPath)) {
      throw new Error(`Contract file not found: ${contractPath}`);
    }

    const contractJson = JSON.parse(fs.readFileSync(contractPath, "utf8"));

    if (!contractJson.bytecode) {
      throw new Error(`No bytecode found in ${contractPath}`);
    }

    let bytecodeHex = contractJson.bytecode;
    if (typeof bytecodeHex !== "string") {
      throw new Error(`Invalid bytecode format in ${contractPath}`);
    }

    if (bytecodeHex.startsWith("0x")) {
      bytecodeHex = bytecodeHex.slice(2);
    }

    if (!/^[0-9a-fA-F]*$/.test(bytecodeHex)) {
      throw new Error(`Invalid hex bytecode in ${contractPath}`);
    }

    if (bytecodeHex.length === 0) {
      throw new Error(`Empty bytecode in ${contractPath}`);
    }

    console.log(`📊 Bytecode length: ${bytecodeHex.length / 2} bytes`);

    const bytecodeBuffer = Buffer.from(bytecodeHex, "hex");
    const bytecode = new Uint8Array(bytecodeBuffer);

    let constructorParameters = null;
    if (constructorParams.length > 0) {
      console.log(
        `🔧 Constructor parameters: ${JSON.stringify(constructorParams)}`
      );
      constructorParameters = new ContractFunctionParameters();

      for (const param of constructorParams) {
        if (typeof param === "string") {
          if (param.match(/^\d+\.\d+\.\d+$/)) {
            constructorParameters.addAddress(param);
          } else if (param.startsWith("0x") && param.length === 42) {
            constructorParameters.addAddress(param);
          } else {
            constructorParameters.addString(param);
          }
        } else if (typeof param === "number") {
          constructorParameters.addUint256(param);
        } else if (typeof param === "boolean") {
          constructorParameters.addBool(param);
        }
      }
    }

    const contractCreateFlow = new ContractCreateFlow()
      .setGas(3000000)
      .setBytecode(bytecode);

    if (constructorParameters) {
      contractCreateFlow.setConstructorParameters(constructorParameters);
    }

    console.log(`📤 Submitting ${contractName} contract creation...`);
    const contractCreateSubmit = await contractCreateFlow.execute(client);

    console.log(`⏳ Waiting for ${contractName} contract creation receipt...`);
    const contractCreateReceipt = await contractCreateSubmit.getReceipt(client);

    const contractId = contractCreateReceipt.contractId;
    console.log(
      `✅ ${contractName} contract created with ID: ${contractId.toString()}`
    );

    return contractId;
  } catch (error) {
    console.error(`❌ Failed to deploy ${contractName}:`, error);

    if (error.message.includes("ERROR_DECODING_BYTESTRING")) {
      console.error("💡 This error usually means:");
      console.error("   - Bytecode is not properly hex-encoded");
      console.error("   - Contract compilation failed");
      console.error("   - Invalid bytecode format");
      console.error("   - Try recompiling your contracts");
    }

    throw error;
  }
}

async function callContract(
  client,
  contractId,
  functionName,
  parameters = null,
  gasLimit = 100000
) {
  try {
    const contractExecuteTransaction = new ContractExecuteTransaction()
      .setContractId(contractId)
      .setGas(gasLimit)
      .setFunction(functionName, parameters);

    const contractExecuteSubmit = await contractExecuteTransaction.execute(
      client
    );
    const contractExecuteReceipt = await contractExecuteSubmit.getReceipt(
      client
    );

    return contractExecuteReceipt;
  } catch (error) {
    console.error(
      `❌ Failed to call ${functionName} on contract ${contractId}:`,
      error
    );
    throw error;
  }
}

async function queryContract(
  client,
  contractId,
  functionName,
  parameters = null,
  gasLimit = 100000
) {
  try {
    const contractCallQuery = new ContractCallQuery()
      .setContractId(contractId)
      .setGas(gasLimit)
      .setFunction(functionName, parameters);

    const contractCallResult = await contractCallQuery.execute(client);

    return contractCallResult;
  } catch (error) {
    console.error(
      `❌ Failed to query ${functionName} on contract ${contractId}:`,
      error
    );
    throw error;
  }
}

async function main() {
  try {
    if (!process.env.HEDERA_TESTNET_ACCOUNT_ID) {
      throw new Error("Missing HEDERA_TESTNET_ACCOUNT_ID environment variable");
    }
    if (!process.env.HEDERA_TESTNET_PRIVATE_KEY) {
      throw new Error(
        "Missing HEDERA_TESTNET_PRIVATE_KEY environment variable"
      );
    }

    const deploymentInfo = await deployWithHederaSDK();

    console.log("\n📋 Deployment Summary:");
    console.log("====================");
    console.log(`Network: ${deploymentInfo.network}`);
    console.log(`Deployer: ${deploymentInfo.deployer}`);
    console.log(`Platform Wallet: ${deploymentInfo.platformWallet}`);
    console.log("\n📄 Contract IDs:");
    console.log(`ProjectRegistry: ${deploymentInfo.contracts.ProjectRegistry}`);
    console.log(
      `DisputeResolution: ${deploymentInfo.contracts.DisputeResolution}`
    );
    console.log(
      `ReputationSystem: ${deploymentInfo.contracts.ReputationSystem}`
    );

    console.log("\n🔗 Next Steps:");
    console.log(
      "1. Save these contract IDs in your frontend/backend configuration"
    );
    console.log("2. Fund your platform wallet with HBAR for transaction fees");
    console.log(
      "3. Set up your backend to interact with these contracts using contract IDs"
    );
    console.log("4. Configure your frontend with the contract IDs");
    console.log(
      "5. Test contract interactions using the helper functions provided"
    );

    return deploymentInfo;
  } catch (error) {
    console.error("❌ Deployment process failed:", error);
    process.exit(1);
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = {
  deployWithHederaSDK,
  deployContract,
  callContract,
  queryContract,
};
