import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TorqueRouterModule = buildModule("TorqueRouterModule", (m) => {
  const torqueRouter = m.contract("TorqueRouter");

  return { torqueRouter };
});

export default TorqueRouterModule; 