import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const publicDir = new URL("../public/", import.meta.url);

test("public legal and support pages are present and cross-linked", async () => {
  const names = ["index.html", "privacy.html", "terms.html", "support.html"];
  const pages = await Promise.all(
    names.map((name) => readFile(new URL(name, publicDir), "utf8")),
  );

  for (const page of pages) {
    assert.match(page, /<meta charset="utf-8"/i);
    assert.doesNotMatch(page, /basel\.ashraf@studygrades\.com/i);
  }
  assert.match(pages[0], /privacy\.html/);
  assert.match(pages[0], /terms\.html/);
  assert.match(pages[0], /support\.html/);
  assert.match(pages[1], /بيانات الطلاب/);
  assert.match(pages[2], /الاشتراكات والدفع/);
  assert.match(pages[3], /لا ترسل كلمة المرور/);
});
