const { test } = require("node:test");
const assert = require("node:assert");
const { parseHost, createUUIDValidator } = require("../src/utils/parser");

// 地址前面放一个占位字节，确认 startIndex 偏移生效
function withPrefix(bytes) {
  return Buffer.from([0xff, ...bytes]);
}

test("解析 IPv4 地址", () => {
  const msg = withPrefix([1, 192, 168, 1, 10, 0xaa]);
  assert.deepStrictEqual(parseHost(msg, 1), { host: "192.168.1.10", endIndex: 6 });
});

test("解析域名地址", () => {
  const domain = "example.com";
  const msg = withPrefix([2, domain.length, ...Buffer.from(domain), 0xaa]);
  assert.deepStrictEqual(parseHost(msg, 1), { host: domain, endIndex: 2 + 1 + domain.length });
});

test("解析 IPv6 地址", () => {
  const ip = Buffer.from("20010db8000000000000000000000001", "hex");
  const msg = withPrefix([3, ...ip, 0xaa]);
  assert.deepStrictEqual(parseHost(msg, 1), {
    host: "2001:0db8:0000:0000:0000:0000:0000:0001",
    endIndex: 18,
  });
});

test("未知地址类型返回 null", (t) => {
  t.mock.method(console, "error", () => {});
  assert.deepStrictEqual(parseHost(withPrefix([9, 1, 2, 3]), 1), { host: null, endIndex: 1 });
});

test("UUID 校验支持带或不带连字符", () => {
  const uuid = "4b1b6efa-1f0d-49ae-b66f-2ef036c26138";
  const id = Buffer.from(uuid.replace(/-/g, ""), "hex");
  assert.ok(createUUIDValidator(uuid)(id));
  assert.ok(createUUIDValidator(uuid.replace(/-/g, ""))(id));
  assert.ok(!createUUIDValidator(uuid)(Buffer.alloc(16)));
});
