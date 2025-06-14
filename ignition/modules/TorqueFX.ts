// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const JAN_1ST_2030 = 1893456000;
const ONE_GWEI: bigint = 1_000_000_000n;

const TorqueFXModule = buildModule("TorqueFXModule", (m) => {
  const torqueDEXAddress = m.getParameter("torqueDEXAddress", "0x..."); // Replace with actual address or parameter
  const torqueAccountAddress = m.getParameter("torqueAccountAddress", "0x..."); // Replace with actual address or parameter

  const torqueFX = m.contract("TorqueFX", [torqueDEXAddress, torqueAccountAddress]);

  return { torqueFX };
});

export default TorqueFXModule;
