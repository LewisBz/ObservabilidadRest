import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 2,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const base = __ENV.K6_TARGET || "http://rest-develop:8080";
const path = __ENV.K6_PATH || "/metrics";

export default function () {
  const res = http.get(`${base}${path}`);
  check(res, {
    "status is 200": (r) => r.status === 200,
  });
  sleep(1);
}
