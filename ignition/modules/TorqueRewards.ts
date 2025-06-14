import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TorqueRewardsModule = buildModule("TorqueRewardsModule", (m) => {
  const torqueRewards = m.contract("TorqueRewards");

  return { torqueRewards };
});

export default TorqueRewardsModule; 