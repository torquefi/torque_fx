import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TorqueDEXModule = buildModule("TorqueDEXModule", (m) => {
  const torqueDEX = m.contract("TorqueDEX");

  return { torqueDEX };
});

export default TorqueDEXModule; 