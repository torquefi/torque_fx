import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TorqueModule = buildModule("TorqueModule", (m) => {
  const torque = m.contract("Torque");

  return { torque };
});

export default TorqueModule; 