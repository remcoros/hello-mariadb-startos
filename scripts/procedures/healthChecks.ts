import { healthUtil, types as T } from "../deps.ts";

export const health: T.ExpectedExports.health = {
  "app-ui": healthUtil.checkWebUrl("http://hello-mariadb.embassy:80"),
  "dbgate-ui": healthUtil.checkWebUrl("http://hello-mariadb.embassy:3000"),
};
