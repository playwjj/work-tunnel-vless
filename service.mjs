// @ts-check
import node from "@prisma/composer/node";
import { compute } from "@prisma/composer-prisma-cloud";

export default compute({
  name: "work-tunnel-vless",
  deps: {},
  build: node({ module: import.meta.url, dir: "src", entry: "server.js", dependencies: "external" }),
});
