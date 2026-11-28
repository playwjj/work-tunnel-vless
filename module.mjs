// @ts-check
import { appRoot } from "@prisma/composer";
import workTunnelVlessService from "./service.mjs";

export default appRoot("work-test", ({ provision }) => {
  provision(workTunnelVlessService, { id: "worktunnelvless" });
});
