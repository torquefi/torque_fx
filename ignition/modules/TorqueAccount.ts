import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TorqueAccountModule = buildModule("TorqueAccountModule", (m) => {
  const torqueAccount = m.contract("TorqueAccount");

  return { torqueAccount };
});

export default TorqueAccountModule; 